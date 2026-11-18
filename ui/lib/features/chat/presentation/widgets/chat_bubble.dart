import 'package:flutter/widgets.dart';

import 'chat_palette.dart';

/// A bolha de uma mensagem, uma linha de cada vez: a primeira arredonda em
/// cima, a última embaixo e as do meio só têm as bordas laterais.
class ChatBubble extends StatelessWidget {
  const ChatBubble({
    required this.child,
    required this.first,
    required this.last,
    this.you = false,
    this.accent,
    this.maxWidth = agentMaxWidth,
    this.dimmed = false,
    super.key,
  });

  static const radius = 14.0;
  static const sideInset = 18.0;
  static const textInset = 16.0;
  static const topPad = 12.0;
  static const bottomPad = 14.0;

  /// O vão entre uma bolha e a próxima.
  static const gap = 18.0;
  static const agentMaxWidth = 660.0;
  static const promptMaxWidth = 560.0;

  final Widget child;
  final bool first;
  final bool last;

  /// Bolha sua: à direita e azul.
  final bool you;

  /// A cor do agente, no fio da bolha dele.
  final Color? accent;
  final double maxWidth;

  /// Eco que o transcript ainda não confirmou.
  final bool dimmed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(sideInset, 0, sideInset, last ? gap : 0),
    child: Align(
      alignment: you ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Opacity(
          opacity: dimmed ? 0.6 : 1,
          child: ClipRect(
            child: CustomPaint(
              painter: _BubblePainter(
                first: first,
                last: last,
                you: you,
                accent: accent,
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  textInset,
                  first ? topPad : 0,
                  textInset,
                  last ? bottomPad : 0,
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _BubblePainter extends CustomPainter {
  _BubblePainter({
    required this.first,
    required this.last,
    required this.you,
    required this.accent,
  });

  final bool first;
  final bool last;
  final bool you;
  final Color? accent;

  @override
  void paint(Canvas canvas, Size size) {
    // Linha do meio: o retângulo sai da linha por cima e por baixo, e o clipe
    // corta — só as bordas laterais aparecem.
    final top = first ? 0.0 : -ChatBubble.radius;
    final bottom = size.height + (last ? 0 : ChatBubble.radius);
    final rect = Rect.fromLTRB(0.5, top + 0.5, size.width - 0.5, bottom - 0.5);
    final shape = RRect.fromRectAndRadius(
      rect,
      const Radius.circular(ChatBubble.radius),
    );
    canvas.drawRRect(
      shape,
      Paint()..color = you ? ChatPalette.youFill : ChatPalette.agentFill,
    );
    canvas.drawRRect(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = you
            ? ChatPalette.youBorder
            : (accent ?? const Color(0xFFFFFFFF)).withValues(alpha: 0.38),
    );
  }

  @override
  bool shouldRepaint(_BubblePainter old) =>
      old.first != first ||
      old.last != last ||
      old.you != you ||
      old.accent != accent;
}
