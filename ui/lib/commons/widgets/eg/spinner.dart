import 'package:flutter/widgets.dart';

import '../../../theme/egeon_colors.dart';
import 'svg_path.dart';

/// O traço do spinner (DS `Spinner`): 1.75 na grade de 16.
const double spinnerStroke = 1.75;

final _arc = parseSvgPath('M8 2a6 6 0 0 1 6 6');

/// "Trabalhando": arco que gira numa volta de 900 ms sobre um trilho a 22%
/// (DS `Spinner`: grade de 16, círculo r 6, traço 1.75, padrão 14). Com
/// movimento reduzido o DS desacelera para 1800 ms, não para.
class Spinner extends StatefulWidget {
  const Spinner({this.size = 14, this.color, super.key});

  final double size;

  /// Padrão: `running`.
  final Color? color;

  @override
  State<Spinner> createState() => _SpinnerState();
}

class _SpinnerState extends State<Spinner> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.duration = Duration(
      milliseconds: MediaQuery.disableAnimationsOf(context) ? 1800 : 900,
    );
    if (!_controller.isAnimating) _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? context.eg.running;
    return RotationTransition(
      turns: _controller,
      child: CustomPaint(
        size: Size.square(widget.size),
        painter: _SpinnerPainter(color),
      ),
    );
  }
}

class _SpinnerPainter extends CustomPainter {
  _SpinnerPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 16);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = spinnerStroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(
      const Offset(8, 8),
      6,
      paint..color = color.withValues(alpha: 0.22),
    );
    canvas.drawPath(_arc, paint..color = color);
  }

  @override
  bool shouldRepaint(_SpinnerPainter old) => old.color != color;
}
