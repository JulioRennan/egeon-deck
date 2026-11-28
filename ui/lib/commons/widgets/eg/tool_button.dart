import 'package:flutter/widgets.dart';

import 'eg_icon.dart';
import 'square_button.dart';

/// O botão da barra de ferramentas: ligado = fundo `accentSoft` e ícone
/// `accent`. A dica é obrigatória.
class ToolButton extends StatelessWidget {
  const ToolButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
    this.shortcut,
    this.autofocus = false,
    super.key,
  });

  final EgIconData icon;
  final String tooltip;
  final String? shortcut;
  final VoidCallback? onPressed;
  final bool selected;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => SquareButton(
    icon: icon,
    tooltip: tooltip,
    shortcut: shortcut,
    onPressed: onPressed,
    selected: selected,
    autofocus: autofocus,
  );
}
