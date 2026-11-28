import 'package:flutter/widgets.dart';

import '../../theme/egeon_tokens.dart';
import 'eg/toast.dart';

/// O lugar fixo de cada coisa que flutua sobre o canvas e o chat, numa pilha só
/// para nada se cobrir: a barra de ações no topo (centro), o chip de consumo no
/// canto de cima (direita), e embaixo, de cima para baixo, os pedidos de
/// permissão e o composer. Quem monta cada peça é o módulo dela (canvas, usage,
/// chat); aqui só fica o lugar.
/// O que o canto de cima à direita (o chip de consumo) toma da largura, medido
/// por [ShellLayers]: a largura dele, a margem e um respiro. A barra de ações
/// do canvas lê isto para não passar por baixo; sem peça no canto, vale 0.
final ValueNotifier<double> cornerInset = ValueNotifier(0);

class ShellLayers extends StatefulWidget {
  const ShellLayers({
    this.actions,
    this.corner,
    this.permissions,
    this.composer,
    super.key,
  });

  /// A barra de ações do canvas (ferramentas, zoom, enquadrar).
  final Widget? actions;

  /// O chip de consumo.
  final Widget? corner;

  /// Os pedidos de permissão, acima do composer.
  final Widget? permissions;

  final Widget? composer;

  /// O respiro entre as camadas de cima e a borda da moldura.
  static const margin = EgeonSpace.s4;

  /// O do pé (composer e pedidos): 20 na v3, e a barra do topo fica a 16.
  static const bottomMargin = EgeonSpace.s5;

  /// O vão entre as peças da pilha de baixo.
  static const gap = EgeonSpace.s2;

  @override
  State<ShellLayers> createState() => _ShellLayersState();
}

class _ShellLayersState extends State<ShellLayers> {
  final _bottomKey = GlobalKey();
  final _cornerKey = GlobalKey();

  /// Quem publicou o último [cornerInset]: só ele o zera ao sair, para a casca
  /// que nasce no lugar de outra não ter o valor apagado por ela.
  static _ShellLayersState? _cornerOwner;

  /// O respiro entre a barra de ações e o canto.
  static const _cornerGap = EgeonSpace.s2;

  void _measure() {
    if (widget.corner != null) {
      final box = _cornerKey.currentContext?.findRenderObject();
      final width = box is RenderBox && box.hasSize ? box.size.width : 0.0;
      _cornerOwner = this;
      cornerInset.value = width == 0
          ? 0
          : width + ShellLayers.margin + _cornerGap;
    }
    // Só o pé mede o pé: uma camada só de canto não mexe no que o composer
    // mediu.
    if (widget.permissions == null && widget.composer == null) return;
    final box = _bottomKey.currentContext?.findRenderObject();
    final height = box is RenderBox && box.hasSize ? box.size.height : 0.0;
    toastBottomInset.value = height == 0
        ? 0
        : height + ShellLayers.bottomMargin;
  }

  @override
  void dispose() {
    // Fora da desmontagem: quem ouve (a barra de ações) pode estar saindo junto,
    // e a árvore está travada enquanto isso.
    if (widget.corner != null) {
      Future.microtask(() {
        if (identical(_cornerOwner, this)) {
          _cornerOwner = null;
          cornerInset.value = 0;
        }
      });
    }
    if (widget.permissions != null || widget.composer != null) {
      toastBottomInset.value = 0;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    final hasBottom = widget.permissions != null || widget.composer != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ShellLayers.margin,
        ShellLayers.margin,
        ShellLayers.margin,
        ShellLayers.bottomMargin,
      ),
      child: Stack(
        children: [
          if (widget.actions != null)
            Align(alignment: Alignment.topCenter, child: widget.actions),
          if (widget.corner != null)
            Align(
              alignment: Alignment.topRight,
              // O chip muda de largura sozinho (o custo cresce): a medida
              // acompanha, sem esperar a casca reconstruir.
              child: NotificationListener<SizeChangedLayoutNotification>(
                onNotification: (_) {
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => mounted ? _measure() : null,
                  );
                  return false;
                },
                child: SizeChangedLayoutNotifier(
                  key: _cornerKey,
                  child: widget.corner!,
                ),
              ),
            ),
          if (hasBottom)
            Align(
              alignment: Alignment.bottomCenter,
              child: Column(
                key: _bottomKey,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.permissions != null) ...[
                    widget.permissions!,
                    if (widget.composer != null)
                      const SizedBox(height: ShellLayers.gap),
                  ],
                  ?widget.composer,
                ],
              ),
            ),
        ],
      ),
    );
  }
}
