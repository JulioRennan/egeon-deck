#include "window_channel.h"

#include <windows.h>

#include <commctrl.h>
#include <dwmapi.h>
#include <dxgi1_6.h>
#include <wrl/client.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <flutter_windows.h>

#include <cmath>
#include <cstdio>
#include <cstring>
#include <functional>
#include <memory>
#include <string>

// Redefinido para SDKs anteriores à 10.0.22000.0.
#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif

namespace {

constexpr char kChannelName[] = "egeon/window";
constexpr UINT_PTR kSubclassId = 1;
// Roda uma função na thread da janela. O handler do canal já roda nela (a
// thread de plataforma do motor é a do laço Win32; o RunOnSeparateThread do
// desktop_multi_window só tira dela a thread de UI do Dart), então o
// SendMessage vira chamada direta; fica como garantia de que nada mexe na
// janela de outra thread.
constexpr UINT kRunOnUi = WM_APP + 0x45;
constexpr UINT_PTR kSaveTimer = 0x4547;
constexpr UINT kSaveDelayMs = 300;
// Abaixo disto a gaveta aberta ao lado no chat, os participantes e a conversa
// não cabem; repete `RootLayout.minWindow`.
constexpr int kMainMinWidth = 1000;
constexpr int kMainMinHeight = 600;

struct WindowState {
  HWND window = nullptr;
  // A secundária se esconde em vez de fechar (ver `WM_CLOSE`).
  bool secondary = false;
  // Mínimo do conteúdo, em pontos lógicos; zero é sem mínimo.
  int min_width = 0;
  int min_height = 0;
  // Nome sob o qual a posição é lembrada; vazio até o `present`.
  std::wstring autosave;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel;
};

std::wstring Wide(const std::string& utf8) {
  if (utf8.empty()) return std::wstring();
  const int size = MultiByteToWideChar(CP_UTF8, 0, utf8.data(),
                                       static_cast<int>(utf8.size()), nullptr,
                                       0);
  if (size <= 0) return std::wstring();
  std::wstring wide(static_cast<size_t>(size), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()),
                      &wide[0], size);
  return wide;
}

// Só o build release lê o ambiente; nos outros o `[[maybe_unused]]` evita o
// aviso de função sem uso, que o `/WX` transforma em erro.
[[maybe_unused]] bool EnvEquals(const wchar_t* name, const wchar_t* value) {
  wchar_t buffer[16];
  const DWORD length = GetEnvironmentVariableW(name, buffer, 16);
  return length > 0 && length < 16 && wcscmp(buffer, value) == 0;
}

double ScaleOf(HWND window) {
  const UINT dpi = FlutterDesktopGetDpiForHWND(window);
  return dpi == 0 ? 1.0 : static_cast<double>(dpi) / 96.0;
}

// O tamanho da janela (com bordas e barra de título) para um conteúdo de
// `width` x `height` pontos lógicos.
SIZE OuterSize(HWND window, double width, double height) {
  const double scale = ScaleOf(window);
  RECT rect = {0, 0, static_cast<LONG>(std::lround(width * scale)),
               static_cast<LONG>(std::lround(height * scale))};
  const DWORD style = static_cast<DWORD>(GetWindowLongPtrW(window, GWL_STYLE));
  const DWORD ex_style =
      static_cast<DWORD>(GetWindowLongPtrW(window, GWL_EXSTYLE));
  const UINT dpi = FlutterDesktopGetDpiForHWND(window);
  AdjustWindowRectExForDpi(&rect, style, FALSE, ex_style, dpi == 0 ? 96 : dpi);
  SIZE size = {rect.right - rect.left, rect.bottom - rect.top};
  return size;
}

// Onde a posição das janelas fica guardada: uma pasta por cópia do app, como o
// NSUserDefaults do macOS separa o estável do dev pelo identificador do
// bundle.
std::wstring StateFile() {
  wchar_t base[MAX_PATH];
  const DWORD length = GetEnvironmentVariableW(L"LOCALAPPDATA", base, MAX_PATH);
  if (length == 0 || length >= MAX_PATH) return std::wstring();
  const std::wstring folder =
      std::wstring(base) + L"\\" + EgeonApplicationId();
  CreateDirectoryW(folder.c_str(), nullptr);
  return folder + L"\\windows.ini";
}

void SaveFrame(const WindowState* state) {
  if (state->autosave.empty()) return;
  // Maximizada ou minimizada, o retângulo não é o que se quer lembrar.
  if (IsIconic(state->window) || IsZoomed(state->window)) return;
  RECT rect;
  if (!GetWindowRect(state->window, &rect)) return;
  const std::wstring path = StateFile();
  if (path.empty()) return;
  const wchar_t* section = state->autosave.c_str();
  const struct {
    const wchar_t* key;
    LONG value;
  } entries[] = {
      {L"x", rect.left},
      {L"y", rect.top},
      {L"width", rect.right - rect.left},
      {L"height", rect.bottom - rect.top},
  };
  for (const auto& entry : entries) {
    WritePrivateProfileStringW(section, entry.key,
                               std::to_wstring(entry.value).c_str(),
                               path.c_str());
  }
}

// Reabre onde estava; a primeira vez (sem nada guardado), ou com o retângulo
// fora de qualquer monitor, devolve falso e a janela fica no centro.
bool RestoreFrame(const std::wstring& autosave, const SIZE& minimum,
                  RECT* out) {
  const std::wstring path = StateFile();
  if (path.empty()) return false;
  const wchar_t* section = autosave.c_str();
  const int width = static_cast<int>(
      GetPrivateProfileIntW(section, L"width", 0, path.c_str()));
  const int height = static_cast<int>(
      GetPrivateProfileIntW(section, L"height", 0, path.c_str()));
  if (width <= 0 || height <= 0) return false;
  if (width < minimum.cx || height < minimum.cy) return false;
  // O arquivo guarda negativos como o complemento de dois do UINT.
  const int x = static_cast<int>(
      GetPrivateProfileIntW(section, L"x", 0, path.c_str()));
  const int y = static_cast<int>(
      GetPrivateProfileIntW(section, L"y", 0, path.c_str()));
  const RECT rect = {x, y, x + width, y + height};
  if (MonitorFromRect(&rect, MONITOR_DEFAULTTONULL) == nullptr) return false;
  *out = rect;
  return true;
}

void RunOnUi(HWND window, const std::function<void()>& function) {
  SendMessageW(window, kRunOnUi, 0, reinterpret_cast<LPARAM>(&function));
}

void Activate(HWND window) {
  ShowWindow(window, IsIconic(window) ? SW_RESTORE : SW_SHOW);
  BringWindowToTop(window);
  SetForegroundWindow(window);
}

struct PresentArguments {
  std::wstring title;
  std::wstring autosave;
  double width = 0;
  double height = 0;
  double min_width = 0;
  double min_height = 0;
};

void Present(WindowState* state, const PresentArguments& arguments) {
  HWND window = state->window;
  SetWindowTextW(window, arguments.title.c_str());
  state->min_width = static_cast<int>(std::lround(arguments.min_width));
  state->min_height = static_cast<int>(std::lround(arguments.min_height));

  const SIZE minimum =
      OuterSize(window, arguments.min_width, arguments.min_height);
  RECT target = {};
  if (!RestoreFrame(arguments.autosave, minimum, &target)) {
    SIZE size = OuterSize(window, arguments.width, arguments.height);
    MONITORINFO monitor = {};
    monitor.cbSize = sizeof(monitor);
    GetMonitorInfoW(MonitorFromWindow(window, MONITOR_DEFAULTTOPRIMARY),
                    &monitor);
    const RECT& work = monitor.rcWork;
    if (size.cx > work.right - work.left) size.cx = work.right - work.left;
    if (size.cy > work.bottom - work.top) size.cy = work.bottom - work.top;
    const LONG left = work.left + ((work.right - work.left) - size.cx) / 2;
    const LONG top = work.top + ((work.bottom - work.top) - size.cy) / 2;
    target = {left, top, left + size.cx, top + size.cy};
  }
  SetWindowPos(window, nullptr, target.left, target.top,
               target.right - target.left, target.bottom - target.top,
               SWP_NOZORDER | SWP_NOACTIVATE);
  state->autosave = arguments.autosave;
  EgeonForceDarkTitleBar(window);
  Activate(window);
}

LRESULT CALLBACK WindowProc(HWND window, UINT message, WPARAM wparam,
                            LPARAM lparam, UINT_PTR, DWORD_PTR data) {
  WindowState* state = reinterpret_cast<WindowState*>(data);
  switch (message) {
    case kRunOnUi:
      (*reinterpret_cast<const std::function<void()>*>(lparam))();
      return 1;

    case WM_GETMINMAXINFO: {
      const LRESULT result = DefSubclassProc(window, message, wparam, lparam);
      if (state->min_width > 0 && state->min_height > 0) {
        const SIZE minimum =
            OuterSize(window, state->min_width, state->min_height);
        MINMAXINFO* info = reinterpret_cast<MINMAXINFO*>(lparam);
        info->ptMinTrackSize.x = minimum.cx;
        info->ptMinTrackSize.y = minimum.cy;
      }
      return result;
    }

    // Fechar uma janela secundária a esconde: o desktop_multi_window guarda a
    // janela na lista dele, e o Dart a reabre achando-a ali.
    case WM_CLOSE:
      if (state->secondary) {
        SaveFrame(state);
        ShowWindow(window, SW_HIDE);
        return 0;
      }
      break;

    // O autosave do macOS grava a cada movimento e a cada resize; aqui o
    // aviso vem em rajada durante o arrasto, então grava 300 ms depois do
    // último.
    case WM_WINDOWPOSCHANGED:
      if (!state->autosave.empty() && IsWindowVisible(window)) {
        SetTimer(window, kSaveTimer, kSaveDelayMs, nullptr);
      }
      break;

    case WM_TIMER:
      if (wparam == kSaveTimer) {
        KillTimer(window, kSaveTimer);
        SaveFrame(state);
        return 0;
      }
      break;

    case WM_DWMCOLORIZATIONCOLORCHANGED: {
      const LRESULT result = DefSubclassProc(window, message, wparam, lparam);
      EgeonForceDarkTitleBar(window);
      return result;
    }

    // O motor cai aqui, antes do WM_NCDESTROY: o handler solta o estado antes
    // que ele seja apagado.
    case WM_DESTROY:
      state->channel->SetMethodCallHandler(nullptr);
      break;

    case WM_NCDESTROY:
      RemoveWindowSubclass(window, WindowProc, kSubclassId);
      delete state;
      return DefSubclassProc(window, message, wparam, lparam);
  }
  return DefSubclassProc(window, message, wparam, lparam);
}

bool ReadNumber(const flutter::EncodableMap& map, const char* key,
                double* out) {
  const auto found = map.find(flutter::EncodableValue(key));
  if (found == map.end()) return false;
  // O Dart manda int ou double conforme o valor.
  if (const double* real = std::get_if<double>(&found->second)) {
    *out = *real;
    return true;
  }
  if (const int32_t* int_value = std::get_if<int32_t>(&found->second)) {
    *out = static_cast<double>(*int_value);
    return true;
  }
  if (const int64_t* long_value = std::get_if<int64_t>(&found->second)) {
    *out = static_cast<double>(*long_value);
    return true;
  }
  return false;
}

bool ReadString(const flutter::EncodableMap& map, const char* key,
                std::wstring* out) {
  const auto found = map.find(flutter::EncodableValue(key));
  if (found == map.end()) return false;
  const std::string* text = std::get_if<std::string>(&found->second);
  if (text == nullptr) return false;
  *out = Wide(*text);
  return true;
}

bool ReadPresentArguments(const flutter::EncodableValue* value,
                          PresentArguments* out) {
  if (value == nullptr) return false;
  const flutter::EncodableMap* map = std::get_if<flutter::EncodableMap>(value);
  if (map == nullptr) return false;
  return ReadString(*map, "title", &out->title) &&
         ReadString(*map, "autosave", &out->autosave) &&
         ReadNumber(*map, "width", &out->width) &&
         ReadNumber(*map, "height", &out->height) &&
         ReadNumber(*map, "minWidth", &out->min_width) &&
         ReadNumber(*map, "minHeight", &out->min_height);
}

// Onde o conteúdo está na tela. O Windows já mede de cima para baixo, como o
// CGEvent; só falta passar de pixels para pontos lógicos.
bool ReadFrame(HWND window, flutter::EncodableMap* out) {
  if (!IsWindow(window)) return false;
  RECT client;
  POINT origin = {0, 0};
  if (!GetClientRect(window, &client) || !ClientToScreen(window, &origin)) {
    return false;
  }
  MONITORINFO monitor = {};
  monitor.cbSize = sizeof(monitor);
  GetMonitorInfoW(MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST),
                  &monitor);
  const double scale = ScaleOf(window);
  (*out)[flutter::EncodableValue("x")] =
      flutter::EncodableValue(static_cast<double>(origin.x) / scale);
  (*out)[flutter::EncodableValue("y")] =
      flutter::EncodableValue(static_cast<double>(origin.y) / scale);
  (*out)[flutter::EncodableValue("width")] = flutter::EncodableValue(
      static_cast<double>(client.right - client.left) / scale);
  (*out)[flutter::EncodableValue("height")] = flutter::EncodableValue(
      static_cast<double>(client.bottom - client.top) / scale);
  (*out)[flutter::EncodableValue("screenHeight")] =
      flutter::EncodableValue(static_cast<double>(monitor.rcMonitor.bottom -
                                                  monitor.rcMonitor.top) /
                              scale);
  return true;
}

void OnMethodCall(
    WindowState* state,
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  HWND window = state->window;
  const std::string& method = call.method_name();
  if (!IsWindow(window)) {
    result->Success();
  } else if (method == "activate") {
    // Clique numa notificação: traz o app, mesmo minimizado.
    RunOnUi(window, [window] { Activate(window); });
    result->Success();
  } else if (method == "frame") {
    flutter::EncodableMap frame;
    bool read = false;
    RunOnUi(window, [window, &frame, &read] { read = ReadFrame(window, &frame); });
    if (read) {
      result->Success(flutter::EncodableValue(frame));
    } else {
      result->NotImplemented();
    }
  } else if (method == "present") {
    PresentArguments arguments;
    if (ReadPresentArguments(call.arguments(), &arguments)) {
      RunOnUi(window, [state, &arguments] { Present(state, arguments); });
      result->Success();
    } else {
      result->NotImplemented();
    }
  } else if (method == "close") {
    RunOnUi(window, [window] { PostMessageW(window, WM_CLOSE, 0, 0); });
    result->Success();
  } else {
    result->NotImplemented();
  }
}

// ---- relatório da GPU ------------------------------------------------------

struct AdapterInfo {
  bool found = false;
  std::string name;
  LUID luid = {};
  bool software = false;
};

std::string Utf8(const wchar_t* wide) {
  const int size =
      WideCharToMultiByte(CP_UTF8, 0, wide, -1, nullptr, 0, nullptr, nullptr);
  if (size <= 1) return std::string();
  std::string out(static_cast<size_t>(size), '\0');
  WideCharToMultiByte(CP_UTF8, 0, wide, -1, &out[0], size, nullptr, nullptr);
  out.resize(static_cast<size_t>(size) - 1);
  return out;
}

AdapterInfo Describe(IDXGIAdapter* adapter) {
  AdapterInfo info;
  DXGI_ADAPTER_DESC desc = {};
  if (adapter != nullptr && SUCCEEDED(adapter->GetDesc(&desc))) {
    info.found = true;
    info.name = Utf8(desc.Description);
    info.luid = desc.AdapterLuid;
    // O Microsoft Basic Render Driver (WARP) é o 0x1414.
    info.software = desc.VendorId == 0x1414;
  }
  return info;
}

std::string LuidText(const LUID& luid) {
  char text[24];
  std::snprintf(text, sizeof(text), "%08lx:%08lx",
                static_cast<unsigned long>(luid.HighPart),
                static_cast<unsigned long>(luid.LowPart));
  return text;
}

std::string Text(const AdapterInfo& info) {
  if (!info.found) return "indisponível";
  return "\"" + info.name + "\" LUID " + LuidText(info.luid) +
         (info.software ? " (software)" : "");
}

// O mesmo adaptador que o motor pede por preferência (manager.cc,
// GetGpuLuidByPreference): o primeiro de `EnumAdapterByGpuPreference`.
AdapterInfo RequestedAdapter(DXGI_GPU_PREFERENCE preference) {
  Microsoft::WRL::ComPtr<IDXGIFactory1> factory1;
  if (FAILED(CreateDXGIFactory1(IID_PPV_ARGS(&factory1)))) return {};
  Microsoft::WRL::ComPtr<IDXGIFactory6> factory6;
  if (FAILED(factory1.As(&factory6))) return {};
  Microsoft::WRL::ComPtr<IDXGIAdapter1> adapter;
  if (FAILED(factory6->EnumAdapterByGpuPreference(
          0, preference, IID_PPV_ARGS(&adapter)))) {
    return {};
  }
  return Describe(adapter.Get());
}

// A mesma leitura do EGEON_SECONDARY_GPU que o plugin faz em
// `SecondaryGpuPreference`: none, high ou (o padrão) low.
const char* SecondaryGpuSetting() {
  static char value[16];
  const DWORD length = GetEnvironmentVariableA("EGEON_SECONDARY_GPU", value,
                                               static_cast<DWORD>(sizeof(value)));
  if (length > 0 && length < sizeof(value)) {
    if (strcmp(value, "none") == 0) return "none";
    if (strcmp(value, "high") == 0) return "high";
  }
  return "low";
}

void GpuLog(const std::string& line) {
  SYSTEMTIME now;
  GetLocalTime(&now);
  char stamp[40];
  std::snprintf(stamp, sizeof(stamp), "%04d-%02d-%02d %02d:%02d:%02d ",
                now.wYear, now.wMonth, now.wDay, now.wHour, now.wMinute,
                now.wSecond);
  const std::string text = std::string(stamp) + line + "\r\n";
  OutputDebugStringA(text.c_str());
  const std::wstring folder = StateFile();
  if (folder.empty()) return;
  const std::wstring path =
      folder.substr(0, folder.find_last_of(L'\\')) + L"\\gpu.log";
  HANDLE file = CreateFileW(path.c_str(), FILE_APPEND_DATA,
                            FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr,
                            OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return;
  DWORD written = 0;
  WriteFile(file, text.data(), static_cast<DWORD>(text.size()), &written,
            nullptr);
  CloseHandle(file);
}

// A identidade COM do adaptador do motor principal. O adaptador sai do
// ID3D11Device do motor (IDXGIDevice::GetAdapter): motores que dividem o
// display do ANGLE dividem o dispositivo e recebem o MESMO objeto; dispositivos
// separados, mesmo na mesma GPU, recebem objetos distintos. O ponteiro fica
// guardado para o endereço não ser reaproveitado por outro objeto.
Microsoft::WRL::ComPtr<IUnknown>& MainAdapterIdentity() {
  static Microsoft::WRL::ComPtr<IUnknown> identity;
  return identity;
}

}  // namespace

void EgeonReportGpu(flutter::FlutterViewController* controller,
                    bool secondary) {
  Microsoft::WRL::ComPtr<IDXGIAdapter> adapter;
  const bool read = controller->engine()->GetGraphicsAdapter(&adapter);
  const AdapterInfo used = read ? Describe(adapter.Get()) : AdapterInfo();
  Microsoft::WRL::ComPtr<IUnknown> identity;
  if (read) adapter.As(&identity);
  if (!secondary) {
    MainAdapterIdentity() = identity;
    GpuLog("janela principal: adaptador em uso " + Text(used));
    return;
  }
  const std::string setting = SecondaryGpuSetting();
  // Com `none` o motor não pede adaptador nenhum.
  const AdapterInfo requested =
      setting == "none"
          ? AdapterInfo()
          : RequestedAdapter(setting == "high"
                                 ? DXGI_GPU_PREFERENCE_HIGH_PERFORMANCE
                                 : DXGI_GPU_PREFERENCE_MINIMUM_POWER);
  const IUnknown* main_identity = MainAdapterIdentity().Get();
  std::string verdict;
  if (identity == nullptr || main_identity == nullptr) {
    verdict = "display INDETERMINADO: o motor não informou o adaptador";
  } else if (identity.Get() == main_identity) {
    verdict = "display COMPARTILHADO com o principal (mesmo dispositivo D3D11)";
  } else {
    verdict = "display PRÓPRIO (dispositivo D3D11 distinto do principal)";
  }
  const std::string asked =
      setting == "none" ? std::string("nenhum") : Text(requested);
  GpuLog("janela secundária: EGEON_SECONDARY_GPU=" + setting + "; pedido " +
         asked + "; em uso " + Text(used) + "; " + verdict);
}

void EgeonAttachWindowChannel(flutter::FlutterViewController* controller,
                              bool secondary) {
  HWND view = controller->view()->GetNativeWindow();
  HWND window = GetAncestor(view, GA_ROOT);
  if (window == nullptr) return;

  WindowState* state = new WindowState();
  state->window = window;
  state->secondary = secondary;
  if (!secondary) {
    state->min_width = kMainMinWidth;
    state->min_height = kMainMinHeight;
  }
  state->channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          controller->engine()->messenger(), kChannelName,
          &flutter::StandardMethodCodec::GetInstance());
  state->channel->SetMethodCallHandler(
      [state](const flutter::MethodCall<flutter::EncodableValue>& call,
              std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                  result) { OnMethodCall(state, call, std::move(result)); });
  // O canal e o estado caem com a janela (WM_NCDESTROY), depois do motor.
  SetWindowSubclass(window, WindowProc, kSubclassId,
                    reinterpret_cast<DWORD_PTR>(state));
}

bool EgeonIsDevFlavor() {
#ifdef EGEON_RELEASE_BUILD
  return EnvEquals(L"EGEON_FLAVOR", L"dev");
#else
  return true;
#endif
}

const wchar_t* EgeonApplicationId() {
  static const std::wstring id = EgeonIsDevFlavor()
                                     ? L"dev.duckcoder.egeondeck.next.dev"
                                     : L"dev.duckcoder.egeondeck.next";
  return id.c_str();
}

const wchar_t* EgeonWindowTitle() {
  return EgeonIsDevFlavor() ? L"Egeon Deck (dev)" : L"Egeon Deck";
}

void EgeonForceDarkTitleBar(HWND window) {
  const BOOL dark = TRUE;
  DwmSetWindowAttribute(window, DWMWA_USE_IMMERSIVE_DARK_MODE, &dark,
                        sizeof(dark));
}
