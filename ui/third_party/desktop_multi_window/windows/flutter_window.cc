// Modificado pelo Egeon Deck (2026-11): GPU própria no motor da janela
// secundária (SecondaryGpuPreference); ver ../EGEON.md. Apache-2.0, como o
// resto do pacote.

#include "flutter_window.h"

#include "flutter_windows.h"

#include "tchar.h"

#include <iostream>
#include <string.h>

#include "multi_window_manager.h"
#include "multi_window_plugin_internal.h"

namespace {

// Egeon: a GPU do motor da janela secundária. Dois motores com os mesmos
// atributos de display recebem do ANGLE o MESMO display e o MESMO dispositivo
// D3D11 (o motor chega a comentar "Display is reused between instances"); cada
// um desenha na sua thread de raster e os dois disputam o contexto imediato
// do D3D11, o que derrubou o app em flutter_windows.dll (StateManager11,
// ProgramExecutableD3D) quando o segundo motor nascia com o primeiro
// desenhando. Pedir uma GPU por preferência acrescenta o LUID aos atributos:
// o ANGLE cria outro display, com outro dispositivo, para este motor. O que
// separa o display é ter o LUID, não qual GPU; a de baixo consumo é o padrão
// para não acordar a placa dedicada de um notebook só por esta janela.
// EGEON_SECONDARY_GPU=none volta ao comportamento do pacote; =high pede a de
// alto desempenho.
flutter::GpuPreference SecondaryGpuPreference() {
  char value[16] = {};
  const DWORD capacity = static_cast<DWORD>(sizeof(value));
  const DWORD length =
      GetEnvironmentVariableA("EGEON_SECONDARY_GPU", value, capacity);
  if (length > 0 && length < capacity) {
    if (strcmp(value, "none") == 0) {
      return flutter::GpuPreference::NoPreference;
    }
    if (strcmp(value, "high") == 0) {
      return flutter::GpuPreference::HighPerformancePreference;
    }
  }
  return flutter::GpuPreference::LowPowerPreference;
}

}  // namespace

FlutterWindow::FlutterWindow(const std::string& id,
                             const WindowConfiguration config)
    : id_(id), window_argument_(config.arguments) {}

bool FlutterWindow::OnCreate() {
  // Called when the window is created
  RECT frame = GetClientArea();

  flutter::DartProject project(L"data");
  // Avoid Windows fullscreen freezes in recent Flutter engines when
  // window_manager changes styles from a platform-channel call.
  project.set_ui_thread_policy(flutter::UIThreadPolicy::RunOnSeparateThread);
  project.set_gpu_preference(SecondaryGpuPreference());
  std::vector<std::string> entrypoint_args = {"multi_window", id_,
                                              window_argument_};
  project.set_dart_entrypoint_arguments(entrypoint_args);
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project);

  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    std::cerr << "Failed to setup FlutterViewController." << std::endl;
    return false;
  }

  auto view_handle = flutter_controller_->view()->GetNativeWindow();
  SetChildContent(view_handle);

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }
  MultiWindowManager::Instance()->RemoveManagedFlutterWindowLater(id_);
}

LRESULT FlutterWindow::MessageHandler(HWND hwnd,
                                      UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

FlutterWindow::~FlutterWindow() {
  // Cleanup is handled by Win32Window::Destroy()
}
