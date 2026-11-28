import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../theme/egeon_tokens.dart';
import 'motion.dart';
import '../../../theme/egeon_colors.dart';

/// Uma camada aberta sobre a tela (popover, menu, diálogo). Fecha por [close].
class Layer {
  Layer._(this._entry, this._onClosed, {required this.counted});

  final OverlayEntry _entry;
  final VoidCallback? _onClosed;
  final bool counted;
  bool _open = true;

  /// Quantas camadas com barreira estão abertas agora. A gaveta aberta pelo
  /// mouse não fecha enquanto um menu dela está aberto: a barreira cobre a
  /// gaveta e o ponteiro "sai" dela sem o usuário ter saído.
  static final ValueNotifier<int> openCount = ValueNotifier(0);

  bool get isOpen => _open;

  void close() {
    if (!_open) return;
    _open = false;
    if (counted) openCount.value--;
    _entry.remove();
    _entry.dispose();
    _onClosed?.call();
  }
}

/// A camada de overlay única do design system: tudo que flutua entra por aqui.
/// Precisa de um `Overlay` acima de [context]. Esc e o clique fora fecham; o
/// foco fica preso dentro da camada enquanto ela está aberta.
///
/// [barrierColor] pinta o véu atrás (o `scrim` do diálogo); sem ele a barreira
/// é invisível mas ainda captura o clique fora. Com [passThrough] (o aviso
/// passageiro) a camada não tem barreira, não prende o foco e deixa o clique
/// passar para o que está por baixo.
Layer showLayer(
  BuildContext context, {
  required Widget Function(BuildContext context, Layer layer) builder,
  Color? barrierColor,
  bool dismissOnOutside = true,
  bool dismissOnEscape = true,
  bool passThrough = false,
  VoidCallback? onClosed,
}) {
  final overlay = Overlay.of(context);
  late final Layer layer;
  final entry = OverlayEntry(
    builder: (context) => _LayerHost(
      layer: layer,
      barrierColor: barrierColor,
      dismissOnOutside: dismissOnOutside,
      dismissOnEscape: dismissOnEscape,
      passThrough: passThrough,
      child: builder(context, layer),
    ),
  );
  layer = Layer._(entry, onClosed, counted: !passThrough);
  if (!passThrough) Layer.openCount.value++;
  overlay.insert(entry);
  return layer;
}

class _LayerHost extends StatefulWidget {
  const _LayerHost({
    required this.layer,
    required this.barrierColor,
    required this.dismissOnOutside,
    required this.dismissOnEscape,
    required this.passThrough,
    required this.child,
  });

  final Layer layer;
  final Color? barrierColor;
  final bool dismissOnOutside;
  final bool dismissOnEscape;
  final bool passThrough;
  final Widget child;

  @override
  State<_LayerHost> createState() => _LayerHostState();
}

class _LayerHostState extends State<_LayerHost> {
  final _scope = FocusScopeNode(debugLabel: 'camada');

  /// Quem tinha o foco antes da camada abrir: ele volta ao fechar.
  FocusNode? _previous;

  @override
  void initState() {
    super.initState();
    if (widget.passThrough) return;
    _previous = FocusManager.instance.primaryFocus;
    // O foco tem de entrar no escopo, senão o Tab ainda anda pela tela de
    // baixo; só depois do primeiro quadro o escopo está na árvore.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_scope.hasFocus) _scope.requestFocus();
    });
  }

  @override
  void dispose() {
    final previous = _previous;
    _scope.dispose();
    if (previous != null && previous.context?.mounted == true) {
      previous.requestFocus();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.passThrough) return widget.child;
    // Shortcuts fica acima do FocusScope: o evento de tecla sobe do foco, e o
    // foco pode estar no próprio escopo (nada focável dentro).
    return Shortcuts(
      // O WidgetsApp já liga Esc a DismissIntent; sem fechar por Esc, a camada
      // engole a tecla para o atalho de fora não fechá-la.
      shortcuts: {
        const SingleActivator(LogicalKeyboardKey.escape): widget.dismissOnEscape
            ? const DismissIntent()
            : const DoNothingIntent(),
      },
      child: Actions(
        actions: {
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) {
              widget.layer.close();
              return null;
            },
          ),
        },
        child: FocusScope(
          node: _scope,
          child: FocusTraversalGroup(
            child: Stack(
              children: [
                Positioned.fill(
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: widget.dismissOnOutside
                        ? (_) => widget.layer.close()
                        : null,
                    child: ColoredBox(
                      color: widget.barrierColor ?? EgeonColors.clear,
                    ),
                  ),
                ),
                widget.child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A entrada de uma camada: some do transparente ao opaco com um leve
/// deslocamento e escala. Movimento reduzido corta a transição.
class LayerEntrance extends StatelessWidget {
  const LayerEntrance({
    required this.child,
    this.duration = EgeonMotion.fast,
    this.offset = Offset.zero,
    this.scaleFrom = 1,
    this.alignment = Alignment.center,
    super.key,
  });

  final Widget child;
  final Duration duration;

  /// De onde a camada sobe até o lugar, em pixels.
  final Offset offset;
  final double scaleFrom;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: egDuration(context, duration),
      curve: EgeonMotion.easeStandard,
      builder: (_, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: offset * (1 - t),
          child: Transform.scale(
            scale: scaleFrom + (1 - scaleFrom) * t,
            alignment: alignment,
            child: child,
          ),
        ),
      ),
      child: child,
    );
  }
}

/// O retângulo de [target] em coordenadas globais, para ancorar uma camada.
Rect globalRectOf(BuildContext target) {
  final box = target.findRenderObject()! as RenderBox;
  return box.localToGlobal(Offset.zero) & box.size;
}
