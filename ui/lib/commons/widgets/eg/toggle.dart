import 'package:flutter/widgets.dart';

import '../../../theme/egeon_colors.dart';
import '../../../theme/egeon_tokens.dart';
import 'checkbox.dart';
import 'motion.dart';
import 'pressable.dart';

/// Interruptor, como o `.eg-toggle` do DS: trilho 30×18 em `steelActive` com
/// borda `lineStrong` (hover `controlBorder`); ligado, `accent` (hover
/// `accentHover`). A bolinha de 12 desliza 12px em 140 ms e alarga para 14 ao
/// pressionar. Foco desligado: borda `accent` de 2px; ligado: anel `textPrimary`
/// por fora. Desabilitado: trilho sem fundo, borda `line`, bolinha `textDisabled`.
class Toggle extends StatelessWidget {
  const Toggle({
    required this.on,
    required this.onChanged,
    this.label,
    this.autofocus = false,
    super.key,
  });

  final bool on;

  /// Nulo desabilita.
  final ValueChanged<bool>? onChanged;
  final Widget? label;
  final bool autofocus;

  static const trackWidth = 30.0;
  static const trackHeight = 18.0;
  static const thumb = 12.0;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    final enabled = onChanged != null;
    return Semantics(
      toggled: on,
      child: Pressable(
        onPressed: enabled ? () => onChanged!(!on) : null,
        autofocus: autofocus,
        builder: (context, s) {
          final Color fill;
          final Color border;
          var width = EgeonBorder.hairline;
          if (!enabled) {
            fill = EgeonColors.clear;
            border = c.line;
          } else if (on) {
            fill = s.hovered ? c.accentHover : c.accent;
            border = fill;
          } else {
            fill = c.steelActive;
            border = s.focused
                ? c.accent
                : s.hovered
                ? c.controlBorder
                : c.lineStrong;
            if (s.focused) width = EgeonBorder.focus;
          }
          final thumbColor = !enabled
              ? c.textDisabled
              : on
              ? c.onAccent
              : c.textSecondary;
          final duration = egDuration(context, EgeonMotion.fast);
          final track = SizedBox(
            width: trackWidth,
            height: trackHeight,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: AnimatedContainer(
                    duration: duration,
                    curve: EgeonMotion.easeStandard,
                    decoration: BoxDecoration(
                      color: fill,
                      borderRadius: BorderRadius.circular(EgeonRadius.full),
                      border: Border.all(color: border, width: width),
                    ),
                  ),
                ),
                // 1px da borda + 2px de respiro; ligado, 12px adiante.
                AnimatedPositioned(
                  duration: duration,
                  curve: EgeonMotion.easeStandard,
                  left: 3.0 + (on ? 12 : 0),
                  top: 3,
                  width: s.pressed ? 14 : thumb,
                  height: thumb,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: thumbColor,
                      borderRadius: BorderRadius.circular(EgeonRadius.full),
                    ),
                  ),
                ),
              ],
            ),
          );
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutsideRing(
                active: s.focused && on && enabled,
                radius: trackHeight / 2,
                child: track,
              ),
              if (label != null) ...[
                const SizedBox(width: EgeonSpace.s2),
                ControlLabel(label!, enabled: enabled),
              ],
            ],
          );
        },
      ),
    );
  }
}
