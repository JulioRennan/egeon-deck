import 'package:flutter/painting.dart';

import '../../../../../theme/app_theme.dart';

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
    fontFamily: AppTheme.terminalFontFamily,
    fontFamilyFallback: AppTheme.terminalFontFamilyFallback,
    fontSize: AppTheme.terminalFontSize,
    height: 1.2,
    decoration: TextDecoration.none,
  );

  final double cellWidth;
  final double cellHeight;
}
