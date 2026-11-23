import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../../commons/widgets/eg/layer.dart';

/// Abre a gaveta com o mouse no botão do trilho e fecha quando ele sai dela e
/// do botão. Sair espera um pouco: o ponteiro atravessa o vão entre o trilho e
/// a gaveta sem ela piscar. Com menu ou diálogo aberto a gaveta fica; a
/// barreira deles cobre a gaveta e o ponteiro "sai" dela sem ter saído.
class DrawerHover {
  DrawerHover({required this.onOpen, required this.onClose});

  final VoidCallback onOpen;
  final VoidCallback onClose;

  static const linger = Duration(milliseconds: 250);

  Timer? _timer;

  void enter() {
    _stopWaiting();
    onOpen();
  }

  /// Só o que está dentro da gaveta mantém ela aberta; o botão abre.
  void stay() => _stopWaiting();

  void leave() {
    _stopWaiting();
    _timer = Timer(linger, _closeUnlessLayer);
  }

  void _closeUnlessLayer() {
    if (Layer.openCount.value > 0) {
      Layer.openCount.addListener(_layerClosed);
      return;
    }
    onClose();
  }

  void _layerClosed() {
    if (Layer.openCount.value > 0) return;
    Layer.openCount.removeListener(_layerClosed);
    // O ponteiro ainda pode estar na gaveta: a volta dele cancela a espera.
    _timer = Timer(linger, _closeUnlessLayer);
  }

  void _stopWaiting() {
    _timer?.cancel();
    _timer = null;
    Layer.openCount.removeListener(_layerClosed);
  }

  void dispose() => _stopWaiting();
}

/// A área que conta como "o mouse está na gaveta".
class DrawerHoverRegion extends StatelessWidget {
  const DrawerHoverRegion({
    required this.hover,
    required this.child,
    this.opens = false,
    super.key,
  });

  final DrawerHover? hover;

  /// Entrar aqui abre a gaveta (o botão do trilho); senão só a mantém aberta.
  final bool opens;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final hover = this.hover;
    if (hover == null) return child;
    return MouseRegion(
      opaque: false,
      onEnter: (_) => opens ? hover.enter() : hover.stay(),
      onExit: (_) => hover.leave(),
      child: child,
    );
  }
}
