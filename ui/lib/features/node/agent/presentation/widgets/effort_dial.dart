import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../../../../../theme/app_colors.dart';
import '../../domain/entities/effort_dial_view.dart';
import '../../../../../commons/widgets/app_tooltip.dart';

/// O esforço do agente no cabeçalho do card: um slider com uma marca por nível,
/// o nome do nível ao lado e a pílula "auto". Arrastar, clicar na trilha ou
/// rolar em cima dele ajustam.
///
/// Só desenha: as marcas, a posição e o texto vêm do core ([view]), e o gesto
/// volta como intenção ([onMove], [onToggleAuto]). A regra do seletor é do
/// core. O tempo de assentar é da UI: a escolha só vale quando a mão para
/// ([settleDelay], e nunca com o botão ainda apertado) — cada troca reinicia o
/// processo, e passar de `low` a `max` nível a nível mataria o CLI quatro vezes
/// no caminho.
class EffortDial extends StatefulWidget {
  const EffortDial({
    required this.view,
    required this.onMove,
    required this.onToggleAuto,
    required this.onSettle,
    this.tint = const Color(0xFFBF5AF2),
    this.settleDelay = const Duration(seconds: 1),
    super.key,
  });

  final EffortDialView view;
  final Color tint;
  final ValueChanged<int> onMove;
  final VoidCallback onToggleAuto;

  /// A mão parou há [settleDelay] sem botão apertado e ainda há escolha por
  /// assentar.
  final VoidCallback onSettle;
  final Duration settleDelay;

  static const sliderWidth = 96.0;
  static const height = 18.0;

  /// Quanto de rolagem vale um nível. Trackpad manda deltas em pontos, aos
  /// punhados; roda de mouse manda um passo grande por clique.
  static const preciseStep = 14.0;
  static const wheelStep = 40.0;

  @override
  State<EffortDial> createState() => _EffortDialState();
}

class _EffortDialState extends State<EffortDial> {
  Timer? _timer;
  var _pressed = false;
  var _scroll = 0.0;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(widget.settleDelay, _settle);
  }

  void _settle() {
    _timer = null;
    // Parado mas ainda segurando o botão: você está decidindo, não decidiu.
    // Reinício no meio do arrasto mataria o slider junto com o card.
    if (_pressed) {
      _timer = Timer(const Duration(milliseconds: 200), _settle);
      return;
    }
    if (widget.view.pending) widget.onSettle();
  }

  void _move(int index) {
    final view = widget.view;
    if (!view.usable) return;
    widget.onMove(index.clamp(0, view.levels.length - 1));
    _schedule();
  }

  void _dragTo(double dx) {
    final count = widget.view.levels.length;
    if (count == 0) return;
    const inset = 6.0;
    final span = EffortDial.sliderWidth - 2 * inset;
    _move(count == 1 ? 0 : ((dx - inset) / span * (count - 1)).round());
  }

  void _wheel(PointerScrollEvent event) =>
      _roll(event.scrollDelta.dy, mouse: event.kind == PointerDeviceKind.mouse);

  /// [dy] como o da roda: positivo desce. O trackpad (dois dedos) chega como
  /// pan-zoom, com o deslocamento dos dedos, o contrário do da roda.
  void _roll(double dy, {required bool mouse}) {
    final step = mouse ? EffortDial.wheelStep : EffortDial.preciseStep;
    // Rolar para cima sobe o nível.
    _scroll -= dy;
    while (_scroll.abs() >= step) {
      final direction = _scroll > 0 ? 1 : -1;
      _scroll -= direction * step;
      _move(widget.view.markIndex + direction);
    }
  }

  /// A dica do seletor, como no Swift: o nível, como mexer, e que trocar
  /// reinicia o terminal com a conversa.
  static String _tooltip(EffortDialView view) {
    if (!view.usable) return 'Este modelo não aceita nível de esforço';
    return view.auto
        ? 'Esforço: auto (${view.label}) — arraste ou role para fixar um '
              'nível. Trocar reinicia o terminal; a conversa continua'
        : 'Esforço: ${view.label} — arraste ou role para ajustar. Trocar '
              'reinicia o terminal; a conversa continua';
  }

  @override
  Widget build(BuildContext context) {
    final view = widget.view;
    final labelColor = !view.usable
        ? AppColors.white(0.3)
        : view.pending
        ? widget.tint
        : AppColors.white(view.auto ? 0.45 : 0.62);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          view.label,
          key: const ValueKey('effort-label'),
          style: TextStyle(
            color: labelColor,
            fontSize: 10,
            fontWeight: FontWeight.w500,
            fontFamily: 'Menlo',
            decoration: TextDecoration.none,
          ),
        ),
        const SizedBox(width: 5),
        AppTooltip(
          message: _tooltip(view),
          child: MouseRegion(
            cursor: view.usable ? SystemMouseCursors.click : MouseCursor.defer,
            child: Listener(
              key: const ValueKey('effort-slider'),
              behavior: HitTestBehavior.opaque,
              onPointerDown: view.usable
                  ? (e) {
                      _pressed = true;
                      _dragTo(e.localPosition.dx);
                    }
                  : null,
              onPointerMove: view.usable
                  ? (e) => _dragTo(e.localPosition.dx)
                  : null,
              onPointerUp: (_) => _pressed = false,
              onPointerCancel: (_) => _pressed = false,
              onPointerPanZoomUpdate: view.usable
                  ? (e) {
                      if (e.scale == 1) _roll(-e.panDelta.dy, mouse: false);
                    }
                  : null,
              onPointerSignal: view.usable
                  ? (e) {
                      if (e is PointerScrollEvent) {
                        GestureBinding.instance.pointerSignalResolver.register(
                          e,
                          (_) => _wheel(e),
                        );
                      }
                    }
                  : null,
              child: CustomPaint(
                size: const Size(EffortDial.sliderWidth, EffortDial.height),
                painter: EffortSliderPainter(
                  count: view.levels.length,
                  index: view.markIndex,
                  auto: view.auto,
                  enabled: view.usable,
                  tint: widget.tint,
                ),
              ),
            ),
          ),
        ),
        if (view.usable) ...[
          const SizedBox(width: 8),
          AppTooltip(
            message: view.auto
                ? 'Auto ligado: o modelo decide o esforço. Clique para fixar '
                      'um nível'
                : 'Auto desligado: clique para voltar ao padrão do modelo',
            child: _AutoPill(
              on: view.auto,
              tint: widget.tint,
              onTap: () {
                widget.onToggleAuto();
                _schedule();
              },
            ),
          ),
        ],
      ],
    );
  }
}

/// O traço do slider. Público só para o teste ler o que foi desenhado (marca, auto,
/// ligado) sem depender de nome privado.
@visibleForTesting
class EffortSliderPainter extends CustomPainter {
  EffortSliderPainter({
    required this.count,
    required this.index,
    required this.auto,
    required this.enabled,
    required this.tint,
  });

  final int count;
  final int index;
  final bool auto;
  final bool enabled;
  final Color tint;

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 6.0;
    final y = size.height / 2;
    final span = size.width - 2 * inset;
    // Em auto a barra mostra, apagada, o nível que o modelo usa.
    final opacity = !enabled ? 0.3 : (auto ? 0.5 : 1.0);
    final fill = auto ? AppColors.white(0.5) : tint;
    final track = Paint()
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = AppColors.white(0.14 * opacity + 0.04);
    canvas.drawLine(Offset(inset, y), Offset(inset + span, y), track);
    if (!enabled) return;
    final x = count <= 1 ? inset : inset + span * index / (count - 1);
    canvas.drawLine(
      Offset(inset, y),
      Offset(x, y),
      track..color = fill.withValues(alpha: opacity),
    );
    final tick = Paint()..color = AppColors.white(0.3 * opacity);
    for (var i = 0; i < count; i++) {
      final tx = count <= 1 ? inset : inset + span * i / (count - 1);
      canvas.drawLine(
        Offset(tx, y + 5),
        Offset(tx, y + 8),
        tick..strokeWidth = 1,
      );
    }
    canvas.drawCircle(
      Offset(x, y),
      5,
      Paint()..color = const Color(0xFFE6E6E6).withValues(alpha: opacity),
    );
  }

  @override
  bool shouldRepaint(EffortSliderPainter old) =>
      old.count != count ||
      old.index != index ||
      old.auto != auto ||
      old.enabled != enabled ||
      old.tint != tint;
}

/// Interruptor em forma de pílula: o texto é o rótulo, e ligado ganha o fundo.
class _AutoPill extends StatelessWidget {
  const _AutoPill({required this.on, required this.tint, required this.onTap});

  final bool on;
  final Color tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      key: const ValueKey('effort-auto'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 14,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: on ? tint.withValues(alpha: 0.18) : null,
          borderRadius: BorderRadius.circular(4),
        ),
        alignment: Alignment.center,
        child: Text(
          'auto',
          style: TextStyle(
            color: on ? tint : AppColors.white(0.62),
            fontSize: 9,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    ),
  );
}
