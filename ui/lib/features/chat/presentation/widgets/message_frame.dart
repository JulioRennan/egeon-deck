import 'package:flutter/widgets.dart';

/// O vão e a coluna de uma linha da conversa: a coluna de 760 centrada com 32 de
/// respiro, 28 entre mensagens e 10 entre as peças de uma mesma mensagem. A
/// primeira linha de uma mensagem abre o vão; as outras só encostam.
class MessageFrame extends StatelessWidget {
  const MessageFrame({
    required this.child,
    required this.first,
    this.top,
    super.key,
  });

  final Widget child;
  final bool first;

  /// Sobrepõe o vão de cima (o cabeçalho cola nas peças de baixo com 8).
  final double? top;

  static const maxWidth = 760.0;
  static const side = 32.0;
  static const messageGap = 28.0;
  static const pieceGap = 10.0;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: maxWidth),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          side,
          top ?? (first ? messageGap : pieceGap),
          side,
          0,
        ),
        child: child,
      ),
    ),
  );
}
