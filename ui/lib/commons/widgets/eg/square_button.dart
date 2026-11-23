import 'package:flutter/widgets.dart';

import '../../../theme/egeon_colors.dart';
import '../../../theme/egeon_tokens.dart';
import 'eg_icon.dart';
import 'motion.dart';
import 'pressable.dart';
import 'tooltip.dart';

/// Botão quadrado só com ícone: o corpo de [IconButton] e [ToolButton].
/// Ligado ([selected]) vira `accentSoft` com o ícone em `accent`.
class SquareButton extends StatelessWidget {
  const SquareButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
    this.size = EgeonSize.controlMd,
    this.shortcut,
    this.autofocus = false,
    super.key,
  });

  final EgIconData icon;
  final String tooltip;
  final String? shortcut;
  final VoidCallback? onPressed;
  final bool selected;
  final double size;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    final disabled = onPressed == null;
    const clear = EgeonColors.clear;
    return Tooltip(
      message: tooltip,
      shortcut: shortcut,
      child: Pressable(
        onPressed: onPressed,
        autofocus: autofocus,
        semanticLabel: tooltip,
        builder: (context, s) {
          final background = s.pressed
              ? c.steelActive
              : s.hovered
              ? c.steel
              : selected
              ? c.accentSoft
              : clear;
          final foreground = selected
              ? c.accent
              : s.hovered || s.pressed
              ? c.textPrimary
              : c.textSecondary;
          final border = s.focused ? EgeonBorder.focus : EgeonBorder.hairline;
          return Opacity(
            opacity: disabled ? EgeonOpacity.disabled : 1,
            child: AnimatedScale(
              scale: s.pressed ? 0.98 : 1,
              duration: egDuration(context, EgeonMotion.instant),
              child: AnimatedContainer(
                duration: egDuration(context, EgeonMotion.instant),
                width: size,
                height: size,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(EgeonRadius.md),
                  border: Border.all(
                    color: s.focused ? c.accent : clear,
                    width: border,
                  ),
                ),
                child: EgIcon(
                  icon,
                  size: size < EgeonSize.controlMd
                      ? EgeonSize.iconSm
                      : EgeonSize.icon,
                  color: foreground,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
