import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../../commons/utils/app_shortcut.dart';
import '../../../../core/domain/entities/view_mode.dart';

/// O que um atalho da casca pode pedir.
class ShellShortcutActions {
  const ShellShortcutActions({
    required this.toggleSidebar,
    required this.findBench,
    required this.showView,
    required this.nextTab,
    required this.previousTab,
    required this.back,
    required this.forward,
    required this.closeTab,
    required this.pickTab,
    this.copyTargets,
    this.showProcesses,
    this.zoomIn,
    this.zoomOut,
    this.resetZoom,
  });

  final VoidCallback toggleSidebar;

  /// ⌘K: abre a gaveta de bancadas.
  final VoidCallback findBench;
  final ValueChanged<ViewMode> showView;
  final VoidCallback nextTab;
  final VoidCallback previousTab;

  /// ⌘[ e ⌘]: voltar e avançar entre as bancadas por onde se passou.
  final VoidCallback back;
  final VoidCallback forward;
  final VoidCallback closeTab;

  /// ⌘1…⌘9: a aba de número n (a primeira é 1).
  final ValueChanged<int> pickTab;

  /// ⇧⌘T: copia os alvos de dispatch.
  final VoidCallback? copyTargets;

  /// ⌥⌘P: a janela Processos.
  final VoidCallback? showProcesses;

  /// ⌘= ⌘- ⌘0: o zoom do canvas (sem canvas na tela, nada).
  final VoidCallback? zoomIn;
  final VoidCallback? zoomOut;
  final VoidCallback? resetZoom;
}

/// Os atalhos do app que valem em qualquer lugar da janela, com o terminal
/// focado ou não. Teclas com ⌘ nunca chegam ao terminal — só o colar —, então
/// o evento sobe até aqui. Fora do macOS o modificador é Ctrl+Shift no lugar
/// do ⌘ (`app_shortcut.dart`, decisão 55).
///
/// - ⌘/ abre e fecha a gaveta de bancadas · ⌘K abre para buscar
/// - ⌥⌘1 canvas · ⌥⌘2 chat
/// - ⌘→ aba da direita · ⌘← aba da esquerda · ⌘W fecha a aba
/// - ⌘[ volta · ⌘] avança (as bancadas por onde se passou)
/// - ⌘1…⌘9 vai à aba de número n
/// - ⇧⌘T copia os alvos de dispatch · ⌥⌘P abre Processos
/// - ⌘= aproxima · ⌘- afasta · ⌘0 volta a 100%
class ShellShortcuts extends StatelessWidget {
  const ShellShortcuts({required this.actions, required this.child, super.key});

  final ShellShortcutActions actions;
  final Widget child;

  /// ⌘← e ⌘→ são início e fim da linha dentro de uma caixa de texto: com o foco
  /// num campo (o composer, um diálogo) o atalho da aba não os toma. Por isso
  /// eles não são um `SingleActivator` — que comeria o evento de qualquer jeito
  /// —, e sim uma checagem na hora.
  static bool get _inTextField =>
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<EditableText>() !=
      null;

  KeyEventResult _arrows(FocusNode node, KeyEvent event) {
    // Segurar a tecla repete a troca, como o menu do AppKit.
    // Só no macOS: fora dele as setas com Ctrl+Shift são do terminal e as abas
    // trocam por Ctrl+Tab e Ctrl+PgUp/PgDn.
    if (!usesCommandKey ||
        event is KeyUpEvent ||
        !isAppModifierPressed(HardwareKeyboard.instance)) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.arrowRight &&
        key != LogicalKeyboardKey.arrowLeft) {
      return KeyEventResult.ignored;
    }
    if (_inTextField) return KeyEventResult.ignored;
    (key == LogicalKeyboardKey.arrowRight
        ? actions.nextTab
        : actions.previousTab)();
    return KeyEventResult.handled;
  }

  /// Um `FocusScope` com autofoco, e não um `Focus` que não pede foco: depois
  /// de um clique no vazio do canvas ninguém tem o foco e o evento de tecla
  /// começa no escopo mais próximo — que precisa estar dentro deste atalho, ou
  /// ele nunca o vê. No macOS o `PlatformMenu` atende sem foco; fora dele os
  /// atalhos dependem disto (decisão 55).
  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: bindings,
    child: FocusScope(
      autofocus: true,
      skipTraversal: true,
      onKeyEvent: _arrows,
      child: child,
    ),
  );

  /// Depois de soltos os modificadores, quanto esperar até abrir a janela.
  @visibleForTesting
  static const afterRelease = Duration(milliseconds: 30);

  /// Se os modificadores nunca forem vistos soltos (o aviso se perdeu), a
  /// janela abre assim mesmo depois disto.
  @visibleForTesting
  static const releaseCeiling = Duration(seconds: 2);

  /// Fora do macOS a janela nova nasce depois que Ctrl e Shift sobem. Criada
  /// no meio do atalho, ela toma o foco com eles ainda apertados: o KeyUp vai
  /// à janela nova e a principal fica com os modificadores "presos". Na VM do
  /// Windows a criação da janela de Processos dentro do tratamento da tecla
  /// também derrubou o app (a primeira criação pelo ☰ não); esperar a soltura
  /// tira a criação do tratamento do evento.
  VoidCallback? _afterKeyUp(VoidCallback? action) {
    if (action == null || usesCommandKey) return action;
    return () {
      final keyboard = HardwareKeyboard.instance;
      Timer? ceiling;
      late bool Function(KeyEvent) watch;
      var done = false;
      void open() {
        if (done) return;
        done = true;
        ceiling?.cancel();
        keyboard.removeHandler(watch);
        action();
      }

      watch = (event) {
        if (event is KeyUpEvent &&
            !keyboard.isControlPressed &&
            !keyboard.isShiftPressed) {
          Timer(afterRelease, open);
        }
        return false;
      };
      keyboard.addHandler(watch);
      ceiling = Timer(releaseCeiling, open);
    };
  }

  /// Os atalhos ligados, para o teste conferir que as teclas com Ctrl+Shift
  /// são as de `appCtrlShiftKeys`.
  @visibleForTesting
  Map<ShortcutActivator, VoidCallback> get bindings => {
    appActivator(LogicalKeyboardKey.slash): actions.toggleSidebar,
    appActivator(LogicalKeyboardKey.keyK): actions.findBench,
    // ⌥⌘1 e ⌥⌘2 só no macOS: fora dele Ctrl+Shift+1…9 são as abas, e o
    // canvas e o chat ficam no botão da barra de cima e no menu ☰.
    if (usesCommandKey) ...{
      appActivator(LogicalKeyboardKey.digit1, alt: true): () =>
          actions.showView(ViewMode.canvas),
      appActivator(LogicalKeyboardKey.digit2, alt: true): () =>
          actions.showView(ViewMode.chat),
    },
    appActivator(LogicalKeyboardKey.bracketRight): actions.forward,
    appActivator(LogicalKeyboardKey.bracketLeft): actions.back,
    appActivator(LogicalKeyboardKey.keyW): actions.closeTab,
    for (var n = 1; n <= 9; n++)
      appActivator(_digits[n - 1]): () => actions.pickTab(n),
    // ⇧⌘T e não ⌘T: no Swift o ⌘T arma a ferramenta de terminal.
    appActivator(LogicalKeyboardKey.keyT, shift: true): ?actions.copyTargets,
    appActivator(LogicalKeyboardKey.keyP, alt: true, repeats: false):
        ?_afterKeyUp(actions.showProcesses),
    // Zoom por teclado só no macOS: fora dele Ctrl+Shift+- e Ctrl+Shift+=
    // chegam ao terminal, e o zoom fica na Ctrl+roda, no botão e no ☰.
    if (usesCommandKey) ...{
      appActivator(LogicalKeyboardKey.equal): ?actions.zoomIn,
      appActivator(LogicalKeyboardKey.minus): ?actions.zoomOut,
      appActivator(LogicalKeyboardKey.digit0): ?actions.resetZoom,
    } else ...{
      const SingleActivator(LogicalKeyboardKey.tab, control: true):
          actions.nextTab,
      const SingleActivator(LogicalKeyboardKey.tab, control: true, shift: true):
          actions.previousTab,
      const SingleActivator(LogicalKeyboardKey.pageDown, control: true):
          actions.nextTab,
      const SingleActivator(LogicalKeyboardKey.pageUp, control: true):
          actions.previousTab,
    },
  };

  static const _digits = [
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
    LogicalKeyboardKey.digit7,
    LogicalKeyboardKey.digit8,
    LogicalKeyboardKey.digit9,
  ];
}
