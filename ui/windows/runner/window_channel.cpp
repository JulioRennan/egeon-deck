#include "window_channel.h"

#include <windows.h>

#include <commctrl.h>
#include <dwmapi.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <flutter_windows.h>

#include <cmath>
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
// Roda uma função na thread da janela: os motores das janelas secundárias
// rodam numa thread de plataforma própria (o desktop_multi_window as cria
// assim), mas as janelas pertencem à thread da principal.
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
  if (const int32_t* small = std::get_if<int32_t>(&found->second)) {
    *out = static_cast<double>(*small);
    return true;
  }
  if (const int64_t* large = std::get_if<int64_t>(&found->second)) {
    *out = static_cast<double>(*large);
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

}  // namespace

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
