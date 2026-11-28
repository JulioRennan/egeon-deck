import 'package:flutter/widgets.dart';

import '../../../theme/egeon_colors.dart';
import '../../../theme/egeon_tokens.dart';
import '../../../theme/egeon_type.dart';
import 'eg_icon.dart';
import 'motion.dart';
import 'pressable.dart';

class SegmentOption<T> {
  const SegmentOption(this.value, this.label, {this.icon, this.trailing});

  final T value;
  final String label;
  final EgIconData? icon;

  /// O que vem depois do rótulo (um contador, um ponto de atenção).
  final Widget? trailing;
}

enum SegmentedSize { md, lg }

/// Escolha entre poucas visões (Canvas | Chat; Log | Por agente | Por modelo;
/// Todas | Ativas), como o `.eg-seg` do DS: fundo `obsidian`, borda `line`,
/// respiro de 3 e vão de 2; itens de 28 (lg 32) em `textMuted`; hover
/// `textPrimary`; pressionado `steel`; selecionado `steelActive` com
/// `textPrimary`.
class SegmentedControl<T> extends StatelessWidget {
  const SegmentedControl({
    required this.options,
    required this.value,
    required this.onChanged,
    this.size = SegmentedSize.md,
    this.label,
    super.key,
  });

  final List<SegmentOption<T>> options;
  final T value;

  /// Nulo desabilita.
  final ValueChanged<T>? onChanged;
  final SegmentedSize size;

  /// Para o leitor de tela.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    final enabled = onChanged != null;
    final lg = size == SegmentedSize.lg;
    final itemHeight = lg ? 32.0 : 28.0;
    return Semantics(
      label: label,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.obsidian,
          borderRadius: BorderRadius.circular(EgeonRadius.md),
          border: Border.all(color: c.line),
        ),
        // 3 de respiro mais o fio de 1px (que o DecoratedBox não soma).
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < options.length; i++) ...[
                if (i > 0) const SizedBox(width: 2),
                Pressable(
                  onPressed: enabled
                      ? () => onChanged!(options[i].value)
                      : null,
                  semanticLabel: options[i].label,
                  builder: (context, s) {
                    final selected = options[i].value == value;
                    final foreground = !enabled
                        ? c.textDisabled
                        : selected
                        ? c.textPrimary
                        : s.hovered || s.pressed
                        ? c.textPrimary
                        : c.textMuted;
                    final background = !enabled
                        ? (selected ? c.steel : null)
                        : s.pressed
                        ? c.steel
                        : selected
                        ? c.steelActive
                        : null;
                    return AnimatedContainer(
                      duration: egDuration(context, EgeonMotion.fast),
                      height: itemHeight,
                      padding: EdgeInsets.symmetric(
                        horizontal:
                            (lg ? EgeonSpace.s4 : EgeonSpace.s3) -
                            (s.focused ? EgeonBorder.focus : 0),
                      ),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: background,
                        borderRadius: BorderRadius.circular(EgeonRadius.sm),
                        border: s.focused
                            ? Border.all(
                                color: c.accent,
                                width: EgeonBorder.focus,
                              )
                            : null,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (options[i].icon != null) ...[
                            EgIcon(
                              options[i].icon!,
                              size: EgeonSize.iconSm,
                              color: foreground,
                            ),
                            const SizedBox(width: 6),
                          ],
                          Text(
                            options[i].label,
                            style: (lg ? EgeonType.label : EgeonType.small)
                                .copyWith(
                                  fontWeight: FontWeight.w500,
                                  color: foreground,
                                  decoration: TextDecoration.none,
                                ),
                          ),
                          if (options[i].trailing != null) ...[
                            const SizedBox(width: 6),
                            options[i].trailing!,
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
