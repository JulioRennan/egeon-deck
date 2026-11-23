import 'package:flutter/widgets.dart';

import '../../../../commons/widgets/eg/banner.dart';
import '../../../../commons/widgets/eg/button.dart';
import '../../../../commons/widgets/eg/glass_surface.dart';
import '../../../../commons/widgets/eg/spinner.dart';
import '../../../../theme/egeon_colors.dart';
import '../../../../theme/egeon_type.dart';
import '../../domain/entities/shell_snapshot.dart';

/// "Um instante": cobre o conteúdo enquanto o core faz algo demorado.
class BusyCurtain extends StatelessWidget {
  const BusyCurtain(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: context.eg.scrim,
    child: Center(
      child: GlassSurface(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Spinner(size: 16),
            const SizedBox(width: 12),
            Text(
              text,
              style: EgeonType.label.copyWith(
                color: context.eg.textPrimary,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// A faixa de aviso do shell (`showBanner`): avisa sem travar nada. No canvas
/// desce para debaixo da barra de ações e da informativa (cronômetro e
/// custo); no chat fica encostada no topo.
class ShellBanner extends StatelessWidget {
  const ShellBanner(this.text, {required this.top, super.key});

  /// `topInset + 110` do `WorkbenchShell.layout()`, medido do topo do conteúdo.
  static const belowCanvasBars = 110.0;
  static const chatTop = 12.0;

  final String text;
  final double top;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: EdgeInsets.only(top: top, left: 16, right: 16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: NoticeBanner(
            key: const ValueKey('shell-banner'),
            tone: BannerTone.attention,
            child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
      ),
    ),
  );
}

/// "Sem acesso à pasta": o macOS negou ou está perguntando.
class AccessCurtain extends StatelessWidget {
  const AccessCurtain({
    required this.lock,
    required this.onOpenSettings,
    required this.onAskAgain,
    super.key,
  });

  final AccessLock lock;
  final VoidCallback onOpenSettings;
  final VoidCallback onAskAgain;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    return ColoredBox(
      color: c.scrim,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: GlassSurface(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sem acesso à pasta',
                  style: EgeonType.heading.copyWith(
                    color: c.textPrimary,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  lock.asking
                      ? 'O macOS está perguntando — responda o aviso dele.'
                      : lock.text,
                  style: EgeonType.body.copyWith(
                    color: c.textSecondary,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 20),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Button(
                      label: 'Pedir de novo',
                      kind: ButtonKind.ghost,
                      size: ButtonSize.lg,
                      onPressed: lock.asking ? null : onAskAgain,
                    ),
                    Button(
                      label: 'Abrir Ajustes',
                      kind: ButtonKind.primary,
                      size: ButtonSize.lg,
                      onPressed: onOpenSettings,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
