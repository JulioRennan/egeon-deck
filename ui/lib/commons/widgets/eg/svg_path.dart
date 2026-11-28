import 'dart:ui';

final _number = RegExp(r'-?(?:\d+\.?\d*|\.\d+)(?:e-?\d+)?');
final _token = RegExp(r'[MmLlHhVvCcSsQqAaZz]|-?(?:\d+\.?\d*|\.\d+)(?:e-?\d+)?');

/// Lê o atributo `d` de um `<path>` SVG (os ícones do design system estão
/// escritos assim, na grade de 16). Cobre M L H V C S Q A Z, absolutos e
/// relativos, que é o que os ícones usam.
Path parseSvgPath(String d) {
  if (d.replaceAll(_token, '').replaceAll(RegExp(r'[\s,]'), '').isNotEmpty) {
    throw FormatException('caractere SVG sem suporte', d);
  }
  final tokens = _token.allMatches(d).map((m) => m.group(0)!).toList();
  final path = Path();
  var i = 0;
  var x = 0.0, y = 0.0, startX = 0.0, startY = 0.0;
  var lastCtrlX = 0.0, lastCtrlY = 0.0;
  String? previous;
  String command = 'M';

  double num() => double.parse(tokens[i++]);
  bool hasNumber() => i < tokens.length && _number.hasMatch(tokens[i]);

  while (i < tokens.length) {
    if (!hasNumber()) command = tokens[i++];
    final relative = command == command.toLowerCase();
    final upper = command.toUpperCase();
    if (upper == 'Z') {
      path.close();
      x = startX;
      y = startY;
      previous = upper;
      continue;
    }
    do {
      final ox = relative ? x : 0.0, oy = relative ? y : 0.0;
      switch (upper) {
        case 'M':
          x = ox + num();
          y = oy + num();
          path.moveTo(x, y);
          startX = x;
          startY = y;
          command = relative ? 'l' : 'L';
        case 'L':
          x = ox + num();
          y = oy + num();
          path.lineTo(x, y);
        case 'H':
          x = ox + num();
          path.lineTo(x, y);
        case 'V':
          y = oy + num();
          path.lineTo(x, y);
        case 'C':
          final x1 = ox + num(), y1 = oy + num();
          final x2 = ox + num(), y2 = oy + num();
          x = ox + num();
          y = oy + num();
          path.cubicTo(x1, y1, x2, y2, x, y);
          lastCtrlX = x2;
          lastCtrlY = y2;
        case 'S':
          final reflect = previous == 'C' || previous == 'S';
          final x1 = reflect ? 2 * x - lastCtrlX : x;
          final y1 = reflect ? 2 * y - lastCtrlY : y;
          final x2 = ox + num(), y2 = oy + num();
          x = ox + num();
          y = oy + num();
          path.cubicTo(x1, y1, x2, y2, x, y);
          lastCtrlX = x2;
          lastCtrlY = y2;
        case 'Q':
          final x1 = ox + num(), y1 = oy + num();
          x = ox + num();
          y = oy + num();
          path.quadraticBezierTo(x1, y1, x, y);
        case 'A':
          final rx = num(), ry = num(), rotation = num();
          final large = num() != 0, sweep = num() != 0;
          x = ox + num();
          y = oy + num();
          path.arcToPoint(
            Offset(x, y),
            radius: Radius.elliptical(rx, ry),
            rotation: rotation,
            largeArc: large,
            clockwise: sweep,
          );
        default:
          throw FormatException('comando SVG sem suporte: $command');
      }
      previous = upper;
    } while (hasNumber());
  }
  return path;
}
