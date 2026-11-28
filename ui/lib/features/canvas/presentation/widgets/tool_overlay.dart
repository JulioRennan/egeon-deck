import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../../theme/egeon_colors.dart';
import '../../../../theme/egeon_tokens.dart';

/// Capa transparente ligada enquanto a ferramenta não é o cursor. Existe
/// porque terminal e web consomem o mouse inteiro: sem ela, clicar "dentro" de
/// um nó para criar outro simplesmente digitaria no terminal. Esc a desarma.
class ToolOverlay extends StatefulWidget {
  const ToolOverlay({required this.onPlace, required this.onCancel, super.key});

  /// Início e fim do gesto, em pixels da janela do canvas.
  final void Function(Offset start, Offset end) onPlace;
  final VoidCallback onCancel;

  @override
  State<ToolOverlay> createState() => _ToolOverlayState();
}

class _ToolOverlayState extends State<ToolOverlay> {
  Offset? _start;
  Offset? _current;

  @override
  Widget build(BuildContext context) => Focus(
    autofocus: true,
    onKeyEvent: (_, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.escape) {
        widget.onCancel();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: MouseRegion(
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
          painter: _RubberBand(_start, _current, context.eg),
        ),
      ),
    ),
  );
}

class _RubberBand extends CustomPainter {
  _RubberBand(this.start, this.current, this.colors);

  final Offset? start;
  final Offset? current;
  final EgeonColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final a = start;
    final b = current;
    if (a == null || b == null) return;
    final rect = Rect.fromPoints(a, b);
    if (rect.width <= 2 || rect.height <= 2) return;
    final rounded = RRect.fromRectAndRadius(
      rect,
      const Radius.circular(EgeonRadius.lg),
    );
    canvas
      ..drawRRect(rounded, Paint()..color = colors.accentSoft)
      ..drawRRect(
        rounded,
        Paint()
          ..color = colors.accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
  }

  @override
  bool shouldRepaint(_RubberBand old) =>
      old.start != start || old.current != current;
}
