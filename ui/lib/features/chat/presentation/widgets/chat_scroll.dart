import 'package:flutter/widgets.dart';

/// A rolagem da thread: ela desce sozinha quando você está no fim — e continua
/// descendo. Os três jeitos de isso quebrar: a lista ainda não cresceu quando se
/// mede o fim, uma descida animada em curso parecer "subiu para ler", e você
/// mandar mensagem de um ponto um pouco acima do fim.
class ChatScroll {
  ChatScroll([ScrollController? controller])
    : controller = controller ?? ScrollController();

  final ScrollController controller;

  /// Uma descida animada em curso conta como "no fim".
  bool scrollingToBottom = false;

  /// A folga que ainda conta como o fim: um pouco acima dele é ler o que
  /// acabou de chegar.
  static const tolerance = 40.0;

  /// O fim de verdade, sem a folga.
  bool get isAtVeryBottom {
    if (!controller.hasClients) return true;
    final position = controller.position;
    return position.pixels >= position.maxScrollExtent - 1;
  }

  /// No fim, ou a caminho dele.
  bool get isAtBottom {
    if (scrollingToBottom) return true;
    if (!controller.hasClients) return true;
    final position = controller.position;
    return position.pixels >= position.maxScrollExtent - tolerance;
  }

  /// Desce até o fim. A lista pode crescer enquanto se mede — as linhas abaixo
  /// do que está montado só ganham altura quando entram na tela —, então o
  /// salto repete até o fim parar de se mover.
  void scrollToBottom({bool animated = false}) {
    if (!controller.hasClients) return;
    if (animated) {
      scrollingToBottom = true;
      controller
          .animateTo(
            controller.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          )
          .whenComplete(() {
            scrollingToBottom = false;
            _settle(3);
          });
      return;
    }
    scrollingToBottom = false;
    controller.jumpTo(controller.position.maxScrollExtent);
  }

  /// Linhas que estavam longe só ganham altura ao entrar: depois da descida o
  /// fim pode ter andado, e o salto repete até ele parar.
  void _settle(int rounds) {
    if (rounds == 0 || !controller.hasClients || isAtVeryBottom) return;
    controller.jumpTo(controller.position.maxScrollExtent);
    WidgetsBinding.instance.addPostFrameCallback((_) => _settle(rounds - 1));
  }

  /// Pegar a thread na mão no meio da descida cancela a descida: quem parou
  /// no meio fica onde parou.
  void stopScrolling() {
    if (!scrollingToBottom || !controller.hasClients) return;
    scrollingToBottom = false;
    controller.jumpTo(controller.position.pixels);
  }

  void dispose() => controller.dispose();
}
