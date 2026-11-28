#include "flutter_window.h"

#include <optional>

#include <desktop_multi_window/desktop_multi_window_plugin.h>

#include "flutter/generated_plugin_registrant.h"
#include "window_channel.h"

namespace {

// As janelas secundárias (Processos, decisão 51) rodam cada uma num motor
// próprio: os plugins e o canal da janela têm de ser registrados nele.
void OnSecondaryWindowCreated(void* controller) {
  auto* view_controller =
      static_cast<flutter::FlutterViewController*>(controller);
  RegisterPlugins(view_controller->engine());
  EgeonAttachWindowChannel(view_controller, /*secondary=*/true);
  EgeonReportGpu(view_controller, /*secondary=*/true);
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  DesktopMultiWindowSetWindowCreatedCallback(OnSecondaryWindowCreated);
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  EgeonAttachWindowChannel(flutter_controller_.get(), /*secondary=*/false);
  EgeonReportGpu(flutter_controller_.get(), /*secondary=*/false);

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
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
