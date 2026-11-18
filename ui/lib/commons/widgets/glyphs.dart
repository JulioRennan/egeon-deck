import 'package:flutter/widgets.dart';

enum ChevronDirection { right, down, left }

/// A seta de abrir e fechar, desenhada: não há fonte de símbolos no app.
class ChevronGlyph extends StatelessWidget {
  const ChevronGlyph(
    this.direction, {
    required this.color,
    this.size = 12,
    super.key,
  });

  final ChevronDirection direction;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _ChevronPainter(direction, color),
  );
}

class _ChevronPainter extends CustomPainter {
  _ChevronPainter(this.direction, this.color);

  final ChevronDirection direction;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final path = Path();
    switch (direction) {
      case ChevronDirection.right:
        path
          ..moveTo(s * 0.38, s * 0.22)
          ..lineTo(s * 0.64, s * 0.5)
          ..lineTo(s * 0.38, s * 0.78);
      case ChevronDirection.left:
        path
          ..moveTo(s * 0.62, s * 0.22)
          ..lineTo(s * 0.36, s * 0.5)
          ..lineTo(s * 0.62, s * 0.78);
      case ChevronDirection.down:
        path
          ..moveTo(s * 0.22, s * 0.38)
          ..lineTo(s * 0.5, s * 0.64)
          ..lineTo(s * 0.78, s * 0.38);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_ChevronPainter old) =>
      old.direction != direction || old.color != color;
}

enum FolderKind { plain, multi, stored, missing }

/// O ícone de pasta do projeto: simples, de vários, guardado ou "sem projeto".
class FolderGlyph extends StatelessWidget {
  const FolderGlyph(
    this.kind, {
    required this.color,
    this.size = 16,
    super.key,
  });

  final FolderKind kind;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _FolderPainter(kind, color),
  );
}

class _FolderPainter extends CustomPainter {
  _FolderPainter(this.kind, this.color);

  final FolderKind kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final body = RRect.fromLTRBR(
      s * 0.08,
      s * 0.28,
      s * 0.92,
      s * 0.84,
      Radius.circular(s * 0.1),
    );
    final tab = Path()
      ..moveTo(s * 0.08, s * 0.3)
      ..lineTo(s * 0.08, s * 0.2)
      ..quadraticBezierTo(s * 0.08, s * 0.14, s * 0.14, s * 0.14)
      ..lineTo(s * 0.4, s * 0.14)
      ..lineTo(s * 0.48, s * 0.28);
    final fill = Paint()..color = color;
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;
    final hollow = kind == FolderKind.missing;
    if (hollow) {
      canvas.drawRRect(body, line);
      canvas.drawPath(tab, line);
      return;
    }
    canvas.drawRRect(body, fill);
    canvas.drawPath(tab, fill);
    if (kind == FolderKind.multi) {
      canvas.drawLine(
        Offset(s * 0.22, s * 0.1),
        Offset(s * 0.78, s * 0.1),
        line,
      );
    }
    if (kind == FolderKind.stored) {
      canvas.drawLine(
        Offset(s * 0.34, s * 0.52),
        Offset(s * 0.66, s * 0.52),
        Paint()
          ..color = const Color(0xFF171717)
          ..strokeWidth = 1.4,
      );
    }
  }

  @override
  bool shouldRepaint(_FolderPainter old) =>
      old.kind != kind || old.color != color;
}
