import 'package:flutter/widgets.dart';

import '../../../theme/egeon_colors.dart';
import '../../../theme/egeon_tokens.dart';
import '../../../theme/egeon_type.dart';
import 'eg_icon.dart';
import 'motion.dart';
import 'pressable.dart';
import 'spinner.dart';

enum ButtonKind {
  primary,
  secondary,
  ghost,
  danger,

  /// A ação destrutiva confirmada (o diálogo de excluir): fundo `danger`.
  dangerSolid,
}

/// As medidas do `Button` do DS: altura, respiro, corpo do texto, raio e vão.
enum ButtonSize {
  sm(EgeonSize.controlSm, 12, 13, 7, 6),
  md(EgeonSize.controlMd, 14, 14, EgeonRadius.md, EgeonSpace.s2),
  lg(EgeonSize.controlLg, 18, 15, 10, EgeonSpace.s2);

  const ButtonSize(
    this.height,
    this.padding,
    this.fontSize,
    this.radius,
    this.gap,
  );

  final double height;
  final double padding;
  final double fontSize;
  final double radius;
  final double gap;
}

/// As cores de um botão num estado: fundo, borda e a cor do texto e do ícone.
class ButtonPaint {
  const ButtonPaint({
    required this.background,
    required this.border,
    required this.foreground,
  });

  final Color background;
  final Color border;
  final Color foreground;
}

/// Como cada tipo de botão pinta em cada estado (DS: `Button`).
ButtonPaint buttonPaint(EgeonColors c, ButtonKind kind, PressState s) {
  const clear = EgeonColors.clear;
  switch (kind) {
    case ButtonKind.primary:
      final bg = s.pressed
          ? c.primaryPressed
          : s.hovered
          ? c.primaryHover
          : c.primary;
      // O anel de foco do primário é claro: o azul-gelo some sobre o azul-aço.
      return ButtonPaint(
        background: bg,
        border: s.focused ? c.textPrimary : bg,
        foreground: c.onPrimary,
      );
    case ButtonKind.secondary:
      return ButtonPaint(
        background: s.pressed
            ? c.steelActive
            : s.hovered
            ? c.steel
            : c.carbon,
        border: s.focused
            ? c.accent
            : (s.hovered || s.pressed ? c.lineStrong : c.line),
        foreground: c.textPrimary,
      );
    case ButtonKind.ghost:
      return ButtonPaint(
        background: s.pressed
            ? c.steelActive
            : s.hovered
            ? c.steel
            : clear,
        border: s.focused ? c.accent : clear,
        foreground: s.hovered || s.pressed ? c.textPrimary : c.textSecondary,
      );
    case ButtonKind.dangerSolid:
      final bg = s.pressed
          ? c.dangerPressed
          : s.hovered
          ? c.dangerHover
          : c.danger;
      return ButtonPaint(
        background: bg,
        border: s.focused ? c.textPrimary : bg,
        foreground: c.onDanger,
      );
    case ButtonKind.danger:
      return ButtonPaint(
        background: s.hovered || s.pressed ? c.dangerSoft : c.carbon,
        border: s.focused
            ? c.accent
            : (s.hovered || s.pressed ? clear : c.line),
        foreground: c.danger,
      );
  }
}

/// Botão do design system: cinco tipos (primário, secundário, fantasma, perigo
/// e perigo sólido) em três tamanhos (30, 36, 42). Um primário por região.
class Button extends StatelessWidget {
  const Button({
    required this.label,
    required this.onPressed,
    this.kind = ButtonKind.secondary,
    this.size = ButtonSize.md,
    this.icon,
    this.iconRight,
    this.kbd,
    this.selected = false,
    this.loading = false,
    this.autofocus = false,
    super.key,
  });

  final String label;

  /// Nulo desabilita (40% de opacidade).
  final VoidCallback? onPressed;
  final ButtonKind kind;
  final ButtonSize size;
  final EgIconData? icon;
  final EgIconData? iconRight;

  /// Atalho em chip, no fim do botão (`⌘↵`).
  final String? kbd;

  /// Ligado: fundo `accentSoft` e texto `accent` (a ferramenta ativa).
  final bool selected;

  /// Spinner no lugar do ícone; o botão não muda de tamanho nem aceita clique.
  final bool loading;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    final disabled = onPressed == null;
    return Pressable(
      onPressed: loading ? null : onPressed,
      autofocus: autofocus,
      semanticLabel: label,
      builder: (context, state) {
        var paint = buttonPaint(c, kind, state);
        if (selected && !state.hovered && !state.pressed) {
          paint = ButtonPaint(
            background: c.accentSoft,
            border: paint.border,
            foreground: c.accent,
          );
        }
        final border = state.focused ? EgeonBorder.focus : EgeonBorder.hairline;
        final textStyle = EgeonType.label.copyWith(
          color: paint.foreground,
          fontSize: size.fontSize,
          letterSpacing: -0.005 * size.fontSize,
          decoration: TextDecoration.none,
        );
        final iconSize = size == ButtonSize.sm
            ? EgeonSize.iconSm
            : EgeonSize.icon;
        Widget content = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading && icon != null)
              SizedBox(
                width: iconSize,
                height: iconSize,
                child: Spinner(size: iconSize, color: paint.foreground),
              )
            else if (icon != null)
              EgIcon(icon!, size: iconSize, color: paint.foreground),
            if (icon != null) SizedBox(width: size.gap),
            Text(label, style: textStyle),
            if (iconRight != null) ...[
              SizedBox(width: size.gap),
              EgIcon(iconRight!, size: iconSize, color: paint.foreground),
            ],
            if (kbd != null) ...[
              SizedBox(width: size.gap - 4),
              _ButtonKbd(
                kbd!,
                color:
                    kind == ButtonKind.primary || kind == ButtonKind.dangerSolid
                    ? paint.foreground
                    : c.textMuted,
                chip:
                    kind == ButtonKind.primary || kind == ButtonKind.dangerSolid
                    ? c.textPrimary.withValues(alpha: 0.14)
                    : c.textPrimary.withValues(alpha: 0.06),
              ),
            ],
          ],
        );
        if (loading && icon == null) {
          content = Stack(
            alignment: Alignment.center,
            children: [
              Opacity(opacity: 0, child: content),
              Spinner(size: iconSize, color: paint.foreground),
            ],
          );
        }
        final raised = kind == ButtonKind.secondary && !state.pressed;
        // O `inset 0 1px 0` do DS: branco puro a 10% no primário e a 4% nos
        // outros (os mesmos valores do `EgeonGlass.highlight`).
        final highlight = switch (kind) {
          ButtonKind.primary => EgeonColors.overlay10,
          ButtonKind.secondary ||
          ButtonKind.danger => state.pressed ? null : EgeonColors.overlay4,
          _ => null,
        };
        return Opacity(
          opacity: disabled ? EgeonOpacity.disabled : 1,
          child: AnimatedScale(
            scale: state.pressed ? 0.98 : 1,
            duration: egDuration(context, EgeonMotion.instant),
            child: Stack(
              children: [
                AnimatedContainer(
                  duration: egDuration(context, EgeonMotion.instant),
                  height: size.height,
                  padding: EdgeInsets.symmetric(
                    horizontal: size.padding - border + 1,
                  ),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: paint.background,
                    borderRadius: BorderRadius.circular(size.radius),
                    border: Border.all(color: paint.border, width: border),
                    boxShadow: raised ? EgeonShadow.raised : null,
                  ),
                  child: content,
                ),
                // O `inset 0 1px 0` do DS: um fio de luz no topo, por dentro do raio.
                if (highlight != null)
                  Positioned(
                    left: size.radius * 0.6,
                    right: size.radius * 0.6,
                    top: 1,
                    height: 1,
                    child: IgnorePointer(child: ColoredBox(color: highlight)),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// O atalho dentro do botão (DS `.eg-btn__kbd`): chip de 20, raio 5, mono 11.
class _ButtonKbd extends StatelessWidget {
  const _ButtonKbd(this.text, {required this.color, required this.chip});

  final String text;
  final Color color;
  final Color chip;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: chip,
      borderRadius: BorderRadius.circular(5),
    ),
    child: SizedBox(
      height: 20,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Center(
          widthFactor: 1,
          child: Text(
            text,
            style: EgeonType.monoMeta.copyWith(
              fontSize: 11,
              height: 1,
              fontWeight: FontWeight.w500,
              color: color,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    ),
  );
}
