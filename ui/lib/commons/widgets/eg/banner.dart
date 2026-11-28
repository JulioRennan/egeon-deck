import 'package:flutter/widgets.dart';

import '../../../theme/egeon_colors.dart';
import '../../../theme/egeon_tokens.dart';
import '../../../theme/egeon_type.dart';
import 'eg_icon.dart';
import 'icon_button.dart';

enum BannerTone { info, attention, danger, success }

/// O `Banner` do DS (com outro nome: o `Banner` do Flutter é a faixa de debug).
/// Faixa de aviso fixa (não some sozinha, ao contrário do Toast): ícone do tom,
/// texto, uma ação opcional e "Fechar". `danger` e `attention` ganham o fundo
/// suave da cor.
class NoticeBanner extends StatelessWidget {
  const NoticeBanner({
    required this.child,
    this.tone = BannerTone.info,
    this.action,
    this.onDismiss,
    super.key,
  });

  final Widget child;
  final BannerTone tone;
  final Widget? action;

  /// Nulo esconde o "Fechar".
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    final (icon, color, background, border) = switch (tone) {
      BannerTone.info => (EgIcons.info, c.textSecondary, c.carbon, c.line),
      BannerTone.attention => (
        EgIcons.hand,
        c.attention,
        c.attentionSoft,
        EgeonColors.clear,
      ),
      BannerTone.danger => (
        EgIcons.octagon,
        c.danger,
        c.dangerSoft,
        EgeonColors.clear,
      ),
      BannerTone.success => (EgIcons.check, c.success, c.carbon, c.line),
    };
    return Semantics(
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(EgeonRadius.md),
          border: Border.all(color: border),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              EgeonSpace.s4,
              EgeonSpace.s2,
              EgeonSpace.s2,
              EgeonSpace.s2,
            ),
            child: Row(
              children: [
                EgIcon(icon, color: color),
                const SizedBox(width: EgeonSpace.s3),
                Expanded(
                  child: DefaultTextStyle(
                    style: EgeonType.small.copyWith(
                      color: c.textPrimary,
                      decoration: TextDecoration.none,
                    ),
                    child: child,
                  ),
                ),
                if (action != null) ...[
                  const SizedBox(width: EgeonSpace.s3),
                  action!,
                ],
                if (onDismiss != null) ...[
                  const SizedBox(width: EgeonSpace.s2),
                  IconButton(
                    icon: EgIcons.x,
                    tooltip: 'Fechar',
                    compact: true,
                    onPressed: onDismiss,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
