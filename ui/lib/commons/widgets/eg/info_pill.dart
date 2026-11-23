import 'package:flutter/widgets.dart';

import '../../../theme/egeon_colors.dart';
import '../../../theme/egeon_tokens.dart';
import '../../../theme/egeon_type.dart';
import 'eg_icon.dart';
import 'tooltip.dart';

/// `normal` é a pastilha em `carbon` com fio; `ghost` some o fundo e o fio;
/// `attention` chama (laranja, em sans w500).
enum InfoPillTone { normal, ghost, attention }

/// A pastilha de informação do cartão (modelo · esforço · contexto), como o
/// `.eg-pill` do DS: 30 de altura, respiro de 12, raio 8, vão de 6, mono
/// 12/16 w450 em `textSecondary`, ícone de 14 em `textMuted`.
class InfoPill extends StatelessWidget {
  const InfoPill(
    this.text, {
    this.icon,
    this.tone = InfoPillTone.normal,
    this.title,
    super.key,
  });

  final String text;
  final EgIconData? icon;
  final InfoPillTone tone;

  /// A dica ao passar o cursor.
  final String? title;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    final attention = tone == InfoPillTone.attention;
    final ghost = tone == InfoPillTone.ghost;
    const clear = EgeonColors.clear;
    final foreground = attention ? c.attention : c.textSecondary;
    final pill = DecoratedBox(
      decoration: BoxDecoration(
        color: ghost ? null : c.carbon,
        borderRadius: BorderRadius.circular(EgeonRadius.md),
        border: Border.all(
          color: ghost
              ? clear
              : attention
              ? c.attentionSoft
              : c.line,
        ),
      ),
      child: SizedBox(
        height: EgeonSize.controlSm,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: EgeonSpace.s3 - 1),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                EgIcon(
                  icon!,
                  size: EgeonSize.iconSm,
                  color: attention ? c.attention : c.textMuted,
                ),
                const SizedBox(width: 6),
              ],
              Text(
                text,
                style: (attention ? EgeonType.label : EgeonType.monoMeta)
                    .copyWith(
                      fontSize: 12,
                      height: 16 / 12,
                      color: foreground,
                      decoration: TextDecoration.none,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
    return title == null ? pill : Tooltip(message: title!, child: pill);
  }
}
