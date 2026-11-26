#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <string>

#include "flutter_window.h"
#include "utils.h"
#include "window_channel.h"

namespace {

// Abrir o app de novo só traz para a frente o que já está aberto (como no
// macOS): a segunda janela falaria com o mesmo core. Dev e estável têm
// identificadores diferentes e convivem. Com EGEON_HOME (teste, e2e, pasta
// temporária) a cópia é isolada e nunca se funde com o app em uso. Devolve
// verdadeiro quando já havia outra e ela foi trazida para a frente.
bool BringExistingToFront() {
  wchar_t isolated[2];
  if (::GetEnvironmentVariableW(L"EGEON_HOME", isolated, 2) > 0) return false;

  const std::wstring name = std::wstring(L"Local\\") + EgeonApplicationId();
  // O mutex vive até o processo acabar: é ele que marca esta cópia como a
  // aberta.
  ::CreateMutexW(nullptr, FALSE, name.c_str());
  if (::GetLastError() != ERROR_ALREADY_EXISTS) return false;

  HWND existing =
      ::FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", EgeonWindowTitle());
  if (existing == nullptr) return false;
  if (::IsIconic(existing)) ::ShowWindow(existing, SW_RESTORE);
  ::SetForegroundWindow(existing);
  return true;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  if (BringExistingToFront()) return EXIT_SUCCESS;

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(EgeonWindowTitle(), origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
