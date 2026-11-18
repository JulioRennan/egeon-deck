import 'package:flutter/widgets.dart';

import '../../../../../theme/app_colors.dart';
import '../../domain/entities/queue_panel.dart';
import 'queue_body.dart';

/// A conversa com o painel da fila ao lado: a divisória arrasta a largura (duplo
/// clique volta ao padrão) e a conversa nunca é espremida abaixo do mínimo.
/// Quem compõe guarda a largura que você escolheu — [preferredWidth] — e a
/// devolve a cada mudança por [onWidth]; `null` é o padrão.
class QueueSidePanel extends StatefulWidget {
  const QueueSidePanel({
    required this.thread,
    required this.workbenchId,
    required this.queueNodeId,
    required this.onWidth,
    required this.onClose,
    this.preferredWidth,
    super.key,
  });

  static const gap = 16.0;

  final Widget thread;

  /// A bancada da fila: os comandos dela vão por esta bancada.
  final String workbenchId;
  final String queueNodeId;
  final double? preferredWidth;
  final ValueChanged<double?> onWidth;
  final VoidCallback onClose;

  @override
  State<QueueSidePanel> createState() => _QueueSidePanelState();
}

class _QueueSidePanelState extends State<QueueSidePanel> {
  double _dragStartWidth = 0;
  double _dragged = 0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final content = box.maxWidth - QueueSidePanel.gap;
      final width = QueuePanel.width(
        content: content,
        preferred: widget.preferredWidth,
      );
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: widget.thread),
          MouseRegion(
            cursor: SystemMouseCursors.resizeColumn,
            child: GestureDetector(
              key: const ValueKey('queue-split'),
              behavior: HitTestBehavior.opaque,
              onDoubleTap: () => widget.onWidth(null),
              onHorizontalDragStart: (_) {
                _dragStartWidth = width;
                _dragged = 0;
              },
              onHorizontalDragUpdate: (details) {
                // Arrastar para a esquerda alarga o painel.
                _dragged += details.delta.dx;
                widget.onWidth(
                  QueuePanel.width(
                    content: content,
                    preferred: _dragStartWidth - _dragged,
                  ),
                );
              },
              child: const SizedBox(width: QueueSidePanel.gap),
            ),
          ),
          SizedBox(
            width: width,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.white(0.08)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: QueueBody(
                  workbenchId: widget.workbenchId,
                  nodeId: widget.queueNodeId,
                  onClose: widget.onClose,
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}
