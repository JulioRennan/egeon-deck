import 'package:flutter/widgets.dart';

import '../../../../theme/app_colors.dart';

/// Capa transparente ligada enquanto a ferramenta não é o cursor. Existe
/// porque terminal e web consomem o mouse inteiro: sem ela, clicar "dentro" de
/// um nó para criar outro simplesmente digitaria no terminal.
class ToolOverlay extends StatefulWidget {
  const ToolOverlay({required this.onPlace, super.key});

  /// Início e fim do gesto, em pixels da janela do canvas.
  final void Function(Offset start, Offset end) onPlace;

  @override
  State<ToolOverlay> createState() => _ToolOverlayState();
}

class _ToolOverlayState extends State<ToolOverlay> {
  Offset? _start;
  Offset? _current;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.precise,
    child: Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) => setState(() {
        _start = e.localPosition;
        _current = e.localPosition;
      }),
      onPointerMove: (e) => setState(() => _current = e.localPosition),
      onPointerUp: (e) {
        final start = _start;
        setState(() {
          _start = null;
          _current = null;
        });
        if (start != null) widget.onPlace(start, e.localPosition);
      },
      onPointerCancel: (_) => setState(() {
        _start = null;
        _current = null;
      }),
      child: CustomPaint(
        size: Size.infinite,
        painter: _RubberBand(_start, _current),
      ),
    ),
  );
}

class _RubberBand extends CustomPainter {
  _RubberBand(this.start, this.current);

  final Offset? start;
  final Offset? current;

  @override
  void paint(Canvas canvas, Size size) {
    final a = start;
    final b = current;
    if (a == null || b == null) return;
    final rect = Rect.fromPoints(a, b);
    if (rect.width <= 2 || rect.height <= 2) return;
    final rounded = RRect.fromRectAndRadius(rect, const Radius.circular(10));
    canvas
      ..drawRRect(
        rounded,
        Paint()..color = AppColors.accent.withValues(alpha: 0.12),
      )
      ..drawRRect(
        rounded,
        Paint()
          ..color = AppColors.accent.withValues(alpha: 0.8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
  }

  @override
  bool shouldRepaint(_RubberBand old) =>
      old.start != start || old.current != current;
}
