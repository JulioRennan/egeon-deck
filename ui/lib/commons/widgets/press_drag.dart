import 'package:flutter/widgets.dart';

/// Separa clique de arrasto: soltou parado é clique, andou mais que o limiar é
/// arrasto. O limiar é a defesa contra a mão trêmula — sem ele, escolher uma
/// bancada com o dedo pesado a mudava de lugar.
///
/// Escuta o ponteiro cru, fora da arena de gestos, para um alvo dentro do alvo
/// (o ✕ da aba) continuar ganhando o toque: [ignoreTrailing] diz quantos
/// pixels da direita ficam para ele.
class PressDrag extends StatefulWidget {
  const PressDrag({
    required this.child,
    required this.onClick,
    this.onBegin,
    this.onMove,
    this.onEnd,
    this.ignoreTrailing = 0,
    super.key,
  });

  /// Passou deste tanto, o gesto deixou de ser clique.
  static const threshold = 4.0;

  final Widget child;
  final VoidCallback onClick;

  /// Sem [onBegin] não há arrasto: qualquer gesto solto é clique.
  final ValueChanged<Offset>? onBegin;
  final ValueChanged<Offset>? onMove;

  /// `true` quando o arrasto foi cancelado em vez de solto.
  final ValueChanged<bool>? onEnd;
  final double ignoreTrailing;

  @override
  State<PressDrag> createState() => _PressDragState();
}

class _PressDragState extends State<PressDrag> {
  Offset? _down;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.opaque,
    onPointerDown: (event) {
      // Só o botão principal: o secundário abre o menu e não arrasta.
      if (event.buttons != 1) return;
      final width = context.size?.width ?? 0;
      final onTrailing =
          widget.ignoreTrailing > 0 &&
          width - event.localPosition.dx < widget.ignoreTrailing;
      _down = onTrailing ? null : event.position;
      _dragging = false;
    },
    onPointerMove: (event) {
      final down = _down;
      if (down == null || widget.onBegin == null) return;
      if (!_dragging) {
        if ((event.position - down).distance <= PressDrag.threshold) return;
        _dragging = true;
        widget.onBegin!(down);
      }
      widget.onMove?.call(event.position);
    },
    onPointerUp: (_) {
      if (_down == null) return;
      _down = null;
      if (_dragging) {
        _dragging = false;
        widget.onEnd?.call(false);
      } else {
        widget.onClick();
      }
    },
    onPointerCancel: (_) {
      if (_dragging) widget.onEnd?.call(true);
      _down = null;
      _dragging = false;
    },
    child: widget.child,
  );
}
