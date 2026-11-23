import 'package:flutter/widgets.dart';

import '../../../theme/egeon_colors.dart';
import '../../../theme/egeon_tokens.dart';
import 'icon_data.dart';
import 'svg_path.dart';

export 'icon_data.dart';

/// Ícone de linha do design system: grade de 16, traço 1.5 (escalado com o
/// tamanho, como o SVG), na cor do texto ao redor.
class EgIcon extends StatelessWidget {
  const EgIcon(
    this.icon, {
    this.size = EgeonSize.icon,
    this.color,
    this.strokeWidth,
    super.key,
  });

  final EgIconData icon;

  /// 16 por padrão; 14 em pastilhas e controles sm, 12 em rótulos.
  final double size;

  /// Sem cor, vale a do texto ao redor (`DefaultTextStyle`), e na falta dela o
  /// `textSecondary`.
  final Color? color;

  /// Troca o traço do ícone (o check das caixas usa 2).
  final double? strokeWidth;

  @override
  Widget build(BuildContext context) {
    final fallback = DefaultTextStyle.of(context).style.color;
    return CustomPaint(
      size: Size.square(size),
      painter: _IconPainter(
        icon,
        color ?? fallback ?? context.eg.textSecondary,
        strokeWidth ?? icon.strokeWidth,
      ),
    );
  }
}

class _IconPainter extends CustomPainter {
  _IconPainter(this.icon, this.color, this.strokeWidth);

  final EgIconData icon;
  final Color color;
  final double strokeWidth;

  static final _paths = <String, Path>{};

  static Path _path(String d) => _paths.putIfAbsent(d, () => parseSvgPath(d));

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 16);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = color;
    for (final shape in icon.shapes) {
      switch (shape) {
        case EgPath(:final d):
          final path = _path(d);
          if (icon.filled) canvas.drawPath(path, fill);
          canvas.drawPath(path, stroke);
        case EgCircle(:final cx, :final cy, :final r, :final filled):
          canvas.drawCircle(Offset(cx, cy), r, filled ? fill : stroke);
        case EgRect(:final x, :final y, :final width, :final height, :final rx):
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(x, y, width, height),
              Radius.circular(rx),
            ),
            stroke,
          );
      }
    }
  }

  @override
  bool shouldRepaint(_IconPainter old) =>
      old.icon != icon || old.color != color || old.strokeWidth != strokeWidth;
}
