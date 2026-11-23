import 'package:flutter/painting.dart';

import '../../../../../theme/egeon_type.dart';

/// Tamanho de uma célula da grade, medido a partir da fonte do terminal.
class TerminalMetrics {
  const TerminalMetrics({required this.cellWidth, required this.cellHeight});

  factory TerminalMetrics.measure() {
    final painter = TextPainter(
      text: TextSpan(text: 'M' * 20, style: baseStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    final metrics = TerminalMetrics(
      cellWidth: painter.width / 20,
      cellHeight: painter.height.ceilToDouble(),
    );
    painter.dispose();
    return metrics;
  }

  static const baseStyle = TextStyle(
    fontFamily: EgeonType.mono,
    fontFamilyFallback: EgeonType.monoFallback,
    fontSize: 14,
    height: 20 / 14,
    decoration: TextDecoration.none,
  );

  final double cellWidth;
  final double cellHeight;
}
