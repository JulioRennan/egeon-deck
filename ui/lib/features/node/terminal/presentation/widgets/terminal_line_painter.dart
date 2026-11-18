import 'package:flutter/rendering.dart';

import '../../../../../theme/app_colors.dart';
import '../../../../../theme/terminal_palette.dart';
import '../../domain/entities/terminal_color.dart';
import '../../domain/entities/terminal_line.dart';
import '../../domain/entities/terminal_style.dart';
import 'terminal_metrics.dart';

class TerminalLinePainter extends CustomPainter {
  TerminalLinePainter({required this.line, required this.metrics});

  final TerminalLine line;
  final TerminalMetrics metrics;

  /// A seleção: o destaque do app com transparência, por cima do texto.
  static const selectionColor = Color(0x660A84FF);

  @override
  void paint(Canvas canvas, Size size) {
    _paintRuns(canvas);
    final selection = line.selection;
    if (selection != null) {
      final cells = selection.end - selection.start + 1;
      canvas.drawRect(
        Rect.fromLTWH(
          selection.start * metrics.cellWidth,
          0,
          cells * metrics.cellWidth,
          metrics.cellHeight,
        ),
        Paint()..color = selectionColor,
      );
    }
  }

  void _paintRuns(Canvas canvas) {
    for (final run in line.runs) {
      final style = run.style;
      var fg = _resolve(style.foreground) ?? AppColors.terminalForeground;
      Color? bg = _resolve(style.background);
      if (style.inverse) {
        final swapped = bg ?? AppColors.terminalBackground;
        bg = fg;
        fg = swapped;
      }
      if (style.dim) fg = fg.withValues(alpha: fg.a * 0.6);

      final x = run.column * metrics.cellWidth;
      if (bg != null) {
        canvas.drawRect(
          Rect.fromLTWH(
            x,
            0,
            run.cells * metrics.cellWidth,
            metrics.cellHeight,
          ),
          Paint()..color = bg,
        );
      }
      if (run.text.trim().isEmpty && !style.underline) continue;
      final painter = TextPainter(
        text: TextSpan(text: run.text, style: _textStyle(style, fg)),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(canvas, Offset(x, 0));
      painter.dispose();
    }
  }

  static Color? _resolve(TerminalColor? color) {
    if (color == null) return null;
    final index = color.index;
    return index != null
        ? TerminalPalette.indexed(index)
        : TerminalPalette.rgb(color.rgb!);
  }

  static TextStyle _textStyle(TerminalStyle style, Color color) {
    final decorations = <TextDecoration>[
      if (style.underline) TextDecoration.underline,
      if (style.strike) TextDecoration.lineThrough,
    ];
    return TerminalMetrics.baseStyle.copyWith(
      color: color,
      fontWeight: style.bold ? FontWeight.w700 : FontWeight.w400,
      fontStyle: style.italic ? FontStyle.italic : FontStyle.normal,
      decoration: TextDecoration.combine(decorations),
      decorationColor: color,
    );
  }

  @override
  bool shouldRepaint(TerminalLinePainter old) =>
      !identical(old.line, line) || old.metrics != metrics;
}
