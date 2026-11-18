import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// O selo de contagem no canto de um ícone: pastilha escura com anel, e o
/// número no centro ótico.
class CountSeal extends StatelessWidget {
  const CountSeal(this.value, {super.key});

  final int value;

  static const _minSide = 16.0;
  static const _style = TextStyle(
    fontSize: 9.5,
    fontWeight: FontWeight.w700,
    fontFeatures: [FontFeature.tabularFigures()],
    color: Color.fromRGBO(255, 255, 255, 0.78),
    decoration: TextDecoration.none,
  );

  /// A largura que o número pede, com a folga de 10 e o mínimo redondo.
  static Size sizeOf(int value) {
    final painter = TextPainter(
      text: TextSpan(text: '$value', style: _style),
      textDirection: TextDirection.ltr,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return Size(math.max(_minSide, width.ceilToDouble() + 10), _minSide);
  }

  @override
  Widget build(BuildContext context) {
    final size = sizeOf(value);
    return Container(
      width: size.width,
      height: size.height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFF292E38),
        borderRadius: BorderRadius.circular(size.height / 2),
        border: Border.all(color: const Color(0xFF171A21), width: 1.5),
      ),
      child: Text('$value', style: _style),
    );
  }
}
