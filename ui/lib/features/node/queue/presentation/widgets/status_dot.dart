import 'package:flutter/widgets.dart';

import '../../../../../commons/widgets/hand_cursor.dart';
import '../../../../../theme/app_colors.dart';
import '../../domain/entities/queue_item.dart';

/// A bolinha de estado da tarefa, que também é o checkbox: vazia é pendente,
/// cheia com anel é entregue ao agente, verde com marca é feita, laranja é
/// pergunta esperando você. Clicar marca e desmarca à mão.
class StatusDot extends StatelessWidget {
  const StatusDot({required this.item, required this.onTap, super.key});

  final QueueItem item;
  final VoidCallback onTap;

  static const size = 18.0;

  @override
  Widget build(BuildContext context) => HandCursor(
    child: GestureDetector(
      key: const ValueKey('status-dot'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: size + 8,
        height: size + 8,
        child: CustomPaint(painter: _DotPainter(item.status, item.awaiting)),
      ),
    ),
  );
}

class _DotPainter extends CustomPainter {
  _DotPainter(this.status, this.awaiting);

  final ItemStatus status;
  final bool awaiting;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    const r = StatusDot.size / 2 - 1.5;
    final color = awaiting
        ? AppColors.attention
        : switch (status) {
            ItemStatus.pending => AppColors.white(0.4),
            ItemStatus.sent => AppColors.accent,
            ItemStatus.done => AppColors.done,
          };
    final ring = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    canvas.drawCircle(center, r, ring);
    if (status == ItemStatus.sent && !awaiting) {
      canvas.drawCircle(center, r - 3.5, Paint()..color = color);
    }
    if (status == ItemStatus.done) {
      canvas.drawCircle(center, r, Paint()..color = color);
      canvas.drawPath(
        Path()
          ..moveTo(center.dx - 3.5, center.dy)
          ..lineTo(center.dx - 1, center.dy + 3)
          ..lineTo(center.dx + 4, center.dy - 3),
        Paint()
          ..color = const Color(0xFF101010)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
    if (awaiting) {
      final tp = TextPainter(
        text: TextSpan(
          text: '?',
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            decoration: TextDecoration.none,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_DotPainter old) =>
      old.status != status || old.awaiting != awaiting;
}
