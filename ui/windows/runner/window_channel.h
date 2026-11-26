#ifndef RUNNER_WINDOW_CHANNEL_H_
#define RUNNER_WINDOW_CHANNEL_H_

#include <flutter/flutter_view_controller.h>

// O canal `egeon/window` de uma janela do app: o equivalente do
// `MainFlutterWindow.swift` do macOS e do `window_channel.cc` do Linux.
// `controller` é a view Flutter da janela (a principal, ou a que o
// desktop_multi_window cria para as secundárias); o canal vive e morre com a
// janela. Depois de `SetChildContent`, quando a view já tem janela pai.
//
//   activate        traz a janela para a frente, mesmo minimizada
//   frame           onde o conteúdo está na tela (para /geometry), em pontos
//                   lógicos: pixels divididos pela escala do monitor
//   present         título, tamanho, mínimo, centro e posição lembrada; mostra
//   close           fecha a janela (a secundária só se esconde)
//
// startDrag e toggleZoom ficam sem resposta de propósito: a janela principal
// usa a decoração do sistema por enquanto, e o Dart trata a ausência como
// "não há o que mover".
//
// A principal (`secondary` falso) traz o mínimo de 1000x600; a secundária o
// recebe no `present`, e fechá-la só a esconde.
void EgeonAttachWindowChannel(flutter::FlutterViewController* controller,
                              bool secondary);

// O dev é o que `EGEON_FLAVOR=dev` ou um build que não é release pedem: a
// mesma regra do `EgeonFlavor` do Dart.
bool EgeonIsDevFlavor();

// O identificador do app (o mesmo dos outros runners, com `.dev` no dev): dele saem o nome do
// mutex da instância única e a pasta onde as janelas lembram a posição.
const wchar_t* EgeonApplicationId();

// O título da janela principal: o do flavor (`EgeonFlavor.title`), já que a
// decoração do sistema o mostra.
const wchar_t* EgeonWindowTitle();

// O app é sempre escuro (nunca o tema claro do sistema): vale para a barra de
// título.
void EgeonForceDarkTitleBar(HWND window);

#endif  // RUNNER_WINDOW_CHANNEL_H_
