#ifndef RUNNER_WINDOW_CHANNEL_H_
#define RUNNER_WINDOW_CHANNEL_H_

#include <flutter_linux/flutter_linux.h>

// O canal `egeon/window` de uma janela do app: o equivalente do
// `MainFlutterWindow.swift` do macOS. `registry` é a view Flutter da janela
// (a principal, ou a que o desktop_multi_window cria para as secundárias); o
// canal vive e morre com ela.
//
//   activate        traz a janela para a frente
//   frame           onde o conteúdo está na tela (para /geometry)
//   present         título, tamanho, mínimo, centro e posição lembrada; mostra
//   close           fecha a janela
//
// startDrag e toggleZoom ficam sem resposta de propósito: a janela principal
// usa a decoração do sistema por enquanto, e o Dart trata a ausência como
// "não há o que mover".
void egeon_window_channel_attach(FlPluginRegistry* registry);

// O app é sempre escuro (nunca o tema claro do sistema): vale para a barra de
// título e os menus do GTK.
void egeon_window_force_dark_theme();

// O identificador do aplicativo GTK: o do CMake, com `.dev` quando o flavor é
// dev por `EGEON_FLAVOR=dev` num build release. Dele saem o nome do programa,
// a instância única e a pasta onde as janelas lembram a posição.
const char* egeon_application_id();

// O título da janela principal: o do flavor (`EgeonFlavor.title`), já que a
// decoração do sistema o mostra.
const char* egeon_window_title();

#endif  // RUNNER_WINDOW_CHANNEL_H_
