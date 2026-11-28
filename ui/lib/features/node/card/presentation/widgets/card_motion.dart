import 'package:flutter/widgets.dart';

/// O que o canvas diz ao corpo de um card sobre o movimento: um corpo nativo
/// (a página web) só pode viver na tela quando o canvas está parado e sem zoom;
/// senão mostra a última captura, que acompanha a transformação.
class CardMotion extends InheritedWidget {
  const CardMotion({required this.live, required super.child, super.key});

  /// Zoom em 100% e canvas parado.
  final bool live;

  /// Sem canvas por perto (um card solto), vale ao vivo.
  static bool liveOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CardMotion>()?.live ?? true;

  @override
  bool updateShouldNotify(CardMotion old) => old.live != live;
}
