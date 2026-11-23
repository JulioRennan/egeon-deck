import 'package:flutter/widgets.dart';

import '../../../theme/egeon_colors.dart';
import '../../../theme/egeon_tokens.dart';
import '../../../theme/egeon_type.dart';
import 'eg_icon.dart';

/// 13/18 do DS para rótulo, dica e erro.
TextStyle fieldText(Color color, {FontWeight? weight}) =>
    EgeonType.small.copyWith(
      color: color,
      fontWeight: weight,
      decoration: TextDecoration.none,
    );

/// A moldura dos campos: rótulo em cima (13/18, 500, `textSecondary`); embaixo,
/// a dica (`textMuted`) ou o erro (alerta + frase em `danger`), a 6px do campo.
class Field extends StatelessWidget {
  const Field({
    required this.child,
    this.label,
    this.hint,
    this.error,
    this.width,
    super.key,
  });

  final Widget child;
  final String? label;
  final String? hint;
  final String? error;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              label!,
              style: fieldText(c.textSecondary, weight: FontWeight.w500),
            ),
          ),
        child,
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                EgIcon(EgIcons.alert, size: EgeonSize.iconSm, color: c.danger),
                const SizedBox(width: 6),
                Expanded(child: Text(error!, style: fieldText(c.danger))),
              ],
            ),
          )
        else if (hint != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(hint!, style: fieldText(c.textMuted)),
          ),
      ],
    );
    return width == null ? column : SizedBox(width: width, child: column);
  }
}

/// O corpo de um campo: fundo `carbon`, raio 8 e uma borda só que muda de cor
/// (`lineStrong` → `lineHover` no hover → `accent` 2px com foco; `danger` no
/// erro). Desabilitado: sem fundo, borda `line`.
class InputShell extends StatelessWidget {
  const InputShell({
    required this.child,
    this.hovered = false,
    this.focused = false,
    this.error = false,
    this.enabled = true,
    this.height = EgeonSize.controlMd,
    this.alignment = Alignment.centerLeft,
    this.padding = const EdgeInsets.symmetric(horizontal: EgeonSpace.s3),
    super.key,
  });

  final Widget child;
  final bool hovered;
  final bool focused;
  final bool error;
  final bool enabled;

  /// Altura mínima: o campo de várias linhas cresce.
  final double height;
  final AlignmentGeometry alignment;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    final color = !enabled
        ? c.line
        : error
        ? c.danger
        : focused
        ? c.accent
        : hovered
        ? c.lineHover
        : c.lineStrong;
    final width = focused && enabled ? EgeonBorder.focus : EgeonBorder.hairline;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: enabled ? c.carbon : null,
        borderRadius: BorderRadius.circular(EgeonRadius.md),
        border: Border.all(color: color, width: width),
      ),
      // DecoratedBox não soma a borda ao tamanho: o campo tem [height] fixa,
      // com a borda pintada por dentro.
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: height),
        child: Padding(
          padding: padding,
          child: Align(alignment: alignment, widthFactor: 1, child: child),
        ),
      ),
    );
  }
}
