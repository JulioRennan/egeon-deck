import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../../core/domain/entities/view_mode.dart';

/// O que um atalho da casca pode pedir.
class ShellShortcutActions {
  const ShellShortcutActions({
    required this.toggleSidebar,
    required this.showView,
    required this.nextTab,
    required this.previousTab,
    required this.closeTab,
    required this.pickTab,
  });

  final VoidCallback toggleSidebar;
  final ValueChanged<ViewMode> showView;
  final VoidCallback nextTab;
  final VoidCallback previousTab;
  final VoidCallback closeTab;

  /// ⌘1…⌘9: a aba de número n (a primeira é 1).
  final ValueChanged<int> pickTab;
}

/// Os atalhos do app que valem em qualquer lugar da janela, com o terminal
/// focado ou não. Teclas com ⌘ nunca chegam ao terminal — só o colar —, então
/// o evento sobe até aqui.
///
/// - ⌘/ recolhe a barra · ⌥⌘1 canvas · ⌥⌘2 chat
/// - ⌘→ ⌘] aba da direita · ⌘← ⌘[ aba da esquerda · ⌘W fecha a aba
/// - ⌘1…⌘9 vai à aba de número n
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
    if (event is KeyUpEvent || !HardwareKeyboard.instance.isMetaPressed) {
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

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onKeyEvent: _arrows,
    child: _shortcuts(),
  );

  Widget _shortcuts() => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.slash, meta: true):
          actions.toggleSidebar,
      const SingleActivator(
        LogicalKeyboardKey.digit1,
        meta: true,
        alt: true,
      ): () =>
          actions.showView(ViewMode.canvas),
      const SingleActivator(
        LogicalKeyboardKey.digit2,
        meta: true,
        alt: true,
      ): () =>
          actions.showView(ViewMode.chat),
      const SingleActivator(LogicalKeyboardKey.bracketRight, meta: true):
          actions.nextTab,
      const SingleActivator(LogicalKeyboardKey.bracketLeft, meta: true):
          actions.previousTab,
      const SingleActivator(LogicalKeyboardKey.keyW, meta: true):
          actions.closeTab,
      for (var n = 1; n <= 9; n++)
        SingleActivator(_digits[n - 1], meta: true): () => actions.pickTab(n),
    },
    child: child,
  );

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
