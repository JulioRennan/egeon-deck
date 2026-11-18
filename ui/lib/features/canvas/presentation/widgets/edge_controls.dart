import 'package:flutter/widgets.dart';

import '../../../../commons/widgets/hand_cursor.dart';

import '../../../../theme/app_colors.dart';
import '../../domain/entities/canvas_viewport.dart';
import '../../domain/entities/edge_layout.dart';
import '../../domain/entities/edge_link.dart';

/// Os três controles da ligação sob o cursor: direção, limite e remover. Em
/// pixels da janela, e não no documento — alvo de clique tem o mesmo tamanho em
/// qualquer zoom.
class EdgeControlsLayer extends StatelessWidget {
  const EdgeControlsLayer({
    required this.link,
    required this.frames,
    required this.viewport,
    required this.onCycle,
    required this.onLimit,
    required this.onRemove,
    super.key,
  });

  final EdgeLink link;
  final Map<String, Rect> frames;
  final CanvasViewport viewport;
  final VoidCallback onCycle;
  final VoidCallback onLimit;
  final VoidCallback onRemove;

  static const _fill = Color(0xFF242424);

  @override
  Widget build(BuildContext context) {
    final a = frames[link.a];
    final b = frames[link.b];
    if (a == null || b == null) return const SizedBox.shrink();
    final laid = EdgeLayout.lay(link, a, b);
    final rects = EdgeLayout.controls(laid, viewport);
    return Stack(
      children: [
        _place(
          rects.direction,
          onCycle,
          shape: BoxShape.circle,
          child: Text(
            laid.directionGlyph,
            style: const TextStyle(
              color: AppColors.attention,
              fontSize: 19,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.none,
            ),
          ),
        ),
        _place(
          rects.pill,
          onLimit,
          shape: BoxShape.rectangle,
          child: Text(
            '↻ ${link.maxSends ?? '∞'}',
            style: const TextStyle(
              color: AppColors.attention,
              fontSize: 17,
              fontWeight: FontWeight.w600,
              fontFeatures: [FontFeature.tabularFigures()],
              decoration: TextDecoration.none,
            ),
          ),
        ),
        _place(
          rects.remove,
          onRemove,
          shape: BoxShape.circle,
          child: CustomPaint(
            size: const Size.square(13),
            painter: _CrossPainter(),
          ),
        ),
      ],
    );
  }

  Widget _place(
    Rect rect,
    VoidCallback onTap, {
    required BoxShape shape,
    required Widget child,
  }) => Positioned.fromRect(
    rect: rect,
    child: HandCursor(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _fill,
            shape: shape,
            borderRadius: shape == BoxShape.circle
                ? null
                : BorderRadius.circular(rect.height / 2),
            border: Border.all(color: AppColors.attention),
          ),
          child: Center(child: child),
        ),
      ),
    ),
  );
}

class _CrossPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.attention
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawLine(Offset.zero, Offset(size.width, size.height), paint)
      ..drawLine(Offset(size.width, 0), Offset(0, size.height), paint);
  }

  @override
  bool shouldRepaint(_CrossPainter old) => false;
}
