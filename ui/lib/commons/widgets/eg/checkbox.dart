import 'package:flutter/widgets.dart';

import '../../../theme/egeon_colors.dart';
import '../../../theme/egeon_tokens.dart';
import '../../../theme/egeon_type.dart';
import 'eg_icon.dart';
import 'motion.dart';
import 'pressable.dart';

/// O rótulo ao lado de um controle: 14/20, peso 400, `textPrimary` (ou
/// `textDisabled`).
class ControlLabel extends StatelessWidget {
  const ControlLabel(this.label, {this.enabled = true, super.key});

  final Widget label;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    return DefaultTextStyle(
      style: EgeonType.body.copyWith(
        height: 20 / 14,
        color: enabled ? c.textPrimary : c.textDisabled,
        decoration: TextDecoration.none,
      ),
      child: label,
    );
  }
}

/// O anel de foco de um controle ligado: 2px `textPrimary` por fora da forma
/// (o `outline` com offset 0 do DS). Desligado, o foco engrossa a própria borda.
class OutsideRing extends StatelessWidget {
  const OutsideRing({
    required this.active,
    required this.child,
    this.radius,
    this.circle = false,
    super.key,
  });

  final bool active;
  final Widget child;
  final double? radius;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    if (!active) return child;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          left: -EgeonBorder.focus,
          top: -EgeonBorder.focus,
          right: -EgeonBorder.focus,
          bottom: -EgeonBorder.focus,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: circle ? BoxShape.circle : BoxShape.rectangle,
                borderRadius: circle
                    ? null
                    : BorderRadius.circular((radius ?? 0) + EgeonBorder.focus),
                border: Border.all(
                  color: context.eg.textPrimary,
                  width: EgeonBorder.focus,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A caixa de 16 de checkbox e radio, como o `.eg-check__box` do DS.
///
/// Fundo `carbon`, borda de 1px `controlBorder` (→ hover → `accent` ligada);
/// ligada vira `accent` (hover `accentHover`, pressionada `accentPressed`);
/// pressionada desligada, `steelActive`. O rádio ligado é um anel `accent` de 5px
/// em volta de `carbon`. Foco desligado: a borda vira `accent` de 2px; ligado:
/// anel `textPrimary` por fora. Desabilitada: borda `line`, sem fundo.
class ControlBox extends StatelessWidget {
  const ControlBox({
    required this.on,
    required this.state,
    required this.shape,
    this.error = false,
    this.child,
    super.key,
  });

  final bool on;
  final PressState state;
  final BoxShape shape;
  final bool error;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    final radio = shape == BoxShape.circle;
    final disabled = !state.enabled;
    final Color fill;
    final Color border;
    var width = EgeonBorder.hairline;
    if (disabled) {
      fill = on && !radio ? c.steelActive : EgeonColors.clear;
      border = on ? c.steelActive : c.line;
      if (on && radio) width = 5;
    } else if (on) {
      final accent = state.pressed
          ? c.accentPressed
          : state.hovered
          ? c.accentHover
          : c.accent;
      fill = radio ? c.carbon : accent;
      border = accent;
      if (radio) width = 5;
    } else {
      fill = state.pressed ? c.steelActive : c.carbon;
      border = error
          ? c.danger
          : state.focused
          ? c.accent
          : state.hovered
          ? c.controlBorderHover
          : c.controlBorder;
      if (state.focused) width = EgeonBorder.focus;
    }
    return OutsideRing(
      active: state.focused && on && !disabled,
      radius: radio ? null : EgeonRadius.xs,
      circle: radio,
      child: AnimatedContainer(
        duration: egDuration(context, EgeonMotion.instant),
        width: 16,
        height: 16,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: fill,
          shape: shape,
          borderRadius: radio ? null : BorderRadius.circular(EgeonRadius.xs),
          border: Border.all(
            color: error && !on ? c.danger : border,
            width: width,
          ),
        ),
        child: child,
      ),
    );
  }
}

/// Caixa de marcar: ligada (`accent`, check), indeterminada (traço) ou vazia.
class Checkbox extends StatelessWidget {
  const Checkbox({
    required this.checked,
    required this.onChanged,
    this.indeterminate = false,
    this.label,
    this.error = false,
    this.autofocus = false,
    super.key,
  });

  final bool checked;

  /// Nulo desabilita.
  final ValueChanged<bool>? onChanged;
  final bool indeterminate;
  final Widget? label;
  final bool error;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    final enabled = onChanged != null;
    final on = checked || indeterminate;
    return Semantics(
      checked: checked,
      mixed: indeterminate,
      child: Pressable(
        onPressed: enabled ? () => onChanged!(!checked) : null,
        autofocus: autofocus,
        builder: (context, s) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ControlBox(
              on: on,
              state: s,
              shape: BoxShape.rectangle,
              error: error,
              child: on
                  ? EgIcon(
                      indeterminate ? EgIcons.minus : EgIcons.check,
                      size: 12,
                      strokeWidth: 2,
                      color: enabled ? c.onAccent : c.textDisabled,
                    )
                  : null,
            ),
            if (label != null) ...[
              const SizedBox(width: EgeonSpace.s2),
              Flexible(child: ControlLabel(label!, enabled: enabled)),
            ],
          ],
        ),
      ),
    );
  }
}
