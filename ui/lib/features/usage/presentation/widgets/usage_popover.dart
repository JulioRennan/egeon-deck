import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../../theme/app_colors.dart';
import '../../domain/entities/usage_view.dart';
import 'usage_panel.dart';

/// Abre o detalhe do consumo ancorado em [anchor] (em coordenadas da janela),
/// como um popover: fecha ao clicar fora ou com Esc. Precisa de um `Overlay`
/// acima de [context].
void showUsagePopover(
  BuildContext context, {
  required Rect anchor,
  required UsagePanelView panel,
  bool pricesOpen = false,
}) {
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => _Popover(
      anchor: anchor,
      panel: panel,
      pricesOpen: pricesOpen,
      onClose: () => entry.remove(),
    ),
  );
  Overlay.of(context).insert(entry);
}

class _Popover extends StatelessWidget {
  const _Popover({
    required this.anchor,
    required this.panel,
    required this.pricesOpen,
    required this.onClose,
  });

  final Rect anchor;
  final UsagePanelView panel;
  final bool pricesOpen;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    // Teto do popover: bancada com muitos agentes, ou a tabela de preços
    // aberta, passava da tela. Daí para cima, rola.
    final maxHeight = math.min(560.0, screen.height * 0.75);
    final left = (anchor.center.dx - UsagePanel.width / 2)
        .clamp(8.0, math.max(8.0, screen.width - UsagePanel.width - 8))
        .toDouble();
    final top = math.min(anchor.bottom + 8, screen.height - 120);
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): onClose},
      child: Focus(
        autofocus: true,
        child: Stack(
          children: [
            // Listener, e não GestureDetector: o fundo não é um botão.
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (_) => onClose(),
              ),
            ),
            Positioned(
              left: left,
              top: top,
              width: UsagePanel.width,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: DecoratedBox(
                  key: const ValueKey('usage-popover'),
                  decoration: BoxDecoration(
                    color: UsagePanel.background,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.white(0.12)),
                    boxShadow: [
                      BoxShadow(color: AppColors.black(0.45), blurRadius: 18),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SingleChildScrollView(
                      child: UsagePanel(panel: panel, pricesOpen: pricesOpen),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
