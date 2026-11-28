import 'package:flutter/widgets.dart';

import '../../../theme/egeon_tokens.dart';
import 'eg_icon.dart';
import 'square_button.dart';

/// Botão só de ícone (36; 30 no `sm`). A dica é obrigatória: sem rótulo, é ela
/// que diz o que o botão faz.
class IconButton extends StatelessWidget {
  const IconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.compact = false,
    this.shortcut,
    this.autofocus = false,
    super.key,
  });

  final EgIconData icon;
  final String tooltip;
  final String? shortcut;
  final VoidCallback? onPressed;

  /// 30 em vez de 36.
  final bool compact;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => SquareButton(
    icon: icon,
    tooltip: tooltip,
    shortcut: shortcut,
    onPressed: onPressed,
    autofocus: autofocus,
    size: compact ? EgeonSize.controlSm : EgeonSize.controlMd,
  );
}
