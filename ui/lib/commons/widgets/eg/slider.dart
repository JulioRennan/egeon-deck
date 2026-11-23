import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../theme/egeon_colors.dart';
import '../../../theme/egeon_tokens.dart';
import '../../../theme/egeon_type.dart';
import 'field.dart';
import 'motion.dart';
import 'pressable.dart';

/// Controle de passos nomeados (o esforço do agente: low · medium · high ·
/// xhigh), como o `.eg-slider` do DS: pista de 20 com trilho e preenchimento de
/// 2px, marcas de 2×6 e bolinha de 16 (borda de 4 em `accent`, miolo
/// `textPrimary`) que encaixa no passo mais perto (clique, arrasto, setas,
/// Home/End). Com [auto] ligado o modelo escolhe e o trilho vai a
/// `textDisabled`.
class Slider extends StatefulWidget {
  const Slider({
    required this.value,
    required this.onChanged,
    this.steps = const ['low', 'medium', 'high', 'xhigh'],
    this.label = 'Esforço',
    this.auto,
    this.onAutoChanged,
    this.showLabels = true,
    this.width = 280,
    super.key,
  });

  /// O índice do passo.
  final int value;

  /// Nulo desabilita.
  final ValueChanged<int>? onChanged;
  final List<String> steps;
  final String label;

  /// Nulo esconde a pílula `auto`.
  final bool? auto;
  final ValueChanged<bool>? onAutoChanged;
  final bool showLabels;
  final double width;

  @override
  State<Slider> createState() => _SliderState();
}

class _SliderState extends State<Slider> {
  static const _thumb = 16.0;
  final _focus = FocusNode(debugLabel: 'slider');
  bool _hovered = false;
  bool _pressed = false;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _pick(double dx, double trackWidth) {
    // O gesto da trilha ganha o clique do Pressable: o foco é pedido aqui.
    _focus.requestFocus();
    final n = widget.steps.length - 1;
    final i = (dx / trackWidth * n).round().clamp(0, n);
    if (i != widget.value) widget.onChanged?.call(i);
  }

  void _step(int delta) {
    final n = widget.steps.length - 1;
    final i = (widget.value + delta).clamp(0, n);
    if (i != widget.value) widget.onChanged?.call(i);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    final enabled = widget.onChanged != null;
    final n = widget.steps.length - 1;
    final auto = widget.auto == true;
    final quiet = auto || !enabled;
    final on = quiet ? c.textDisabled : c.accent;
    TextStyle mono(Color color, double size, double line, FontWeight weight) =>
        EgeonType.monoMeta.copyWith(
          fontSize: size,
          height: line / size,
          fontWeight: weight,
          color: color,
          decoration: TextDecoration.none,
        );

    Widget track(PressState s) => LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        double x(int i) => w * i / n;
        final ring = s.focused
            ? c.textPrimary
            : quiet
            ? c.textDisabled
            : (_hovered || _pressed)
            ? c.accentHover
            : c.accent;
        return MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: enabled
                ? (d) {
                    setState(() => _pressed = true);
                    _pick(d.localPosition.dx, w);
                  }
                : null,
            onTapUp: (_) => setState(() => _pressed = false),
            onTapCancel: () => setState(() => _pressed = false),
            onHorizontalDragStart: enabled
                ? (_) => setState(() => _pressed = true)
                : null,
            onHorizontalDragEnd: (_) => setState(() => _pressed = false),
            onHorizontalDragUpdate: enabled
                ? (d) => _pick(d.localPosition.dx, w)
                : null,
            child: SizedBox(
              height: 20,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 9,
                    height: 2,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: c.steelActive,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    width: x(widget.value),
                    top: 9,
                    height: 2,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: on,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                  for (var i = 0; i <= n; i++)
                    Positioned(
                      left: x(i) - 1,
                      top: 7,
                      width: 2,
                      height: 6,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: i <= widget.value ? on : c.lineStrong,
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ),
                  AnimatedPositioned(
                    duration: egDuration(context, EgeonMotion.fast),
                    curve: EgeonMotion.easeStandard,
                    left: x(widget.value) - _thumb / 2,
                    top: 2,
                    width: _thumb,
                    height: _thumb,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: !enabled
                            ? c.carbon
                            : auto
                            ? c.textSecondary
                            : c.textPrimary,
                        shape: BoxShape.circle,
                        border: Border.all(color: ring, width: 4),
                        boxShadow: enabled && !quiet && (_hovered || _pressed)
                            ? [
                                BoxShadow(
                                  color: c.accentSoft,
                                  spreadRadius: _pressed ? 6 : 4,
                                ),
                              ]
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    return SizedBox(
      width: widget.width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                widget.label,
                style: fieldText(
                  enabled ? c.textSecondary : c.textDisabled,
                  weight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Text(
                widget.steps[widget.value],
                style: mono(
                  !enabled
                      ? c.textDisabled
                      : auto
                      ? c.textMuted
                      : c.textPrimary,
                  12,
                  18,
                  FontWeight.w500,
                ),
              ),
              if (widget.auto != null) ...[
                const SizedBox(width: EgeonSpace.s2),
                _AutoPill(on: auto, onChanged: widget.onAutoChanged),
              ],
            ],
          ),
          const SizedBox(height: EgeonSpace.s2),
          // O Focus fica acima do Pressable: a tecla sobe do foco, que está no
          // Pressable, até aqui.
          Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onKeyEvent: (_, e) {
              if (e is KeyUpEvent || !enabled) return KeyEventResult.ignored;
              final key = e.logicalKey;
              if (key == LogicalKeyboardKey.arrowLeft ||
                  key == LogicalKeyboardKey.arrowDown) {
                _step(-1);
              } else if (key == LogicalKeyboardKey.arrowRight ||
                  key == LogicalKeyboardKey.arrowUp) {
                _step(1);
              } else if (key == LogicalKeyboardKey.home) {
                widget.onChanged?.call(0);
              } else if (key == LogicalKeyboardKey.end) {
                widget.onChanged?.call(n);
              } else {
                return KeyEventResult.ignored;
              }
              return KeyEventResult.handled;
            },
            child: Pressable(
              focusNode: _focus,
              onPressed: enabled ? () {} : null,
              builder: (context, s) => track(s),
            ),
          ),
          if (widget.showLabels) ...[
            const SizedBox(height: EgeonSpace.s2),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var i = 0; i <= n; i++)
                  Text(
                    widget.steps[i],
                    style: EgeonType.caption.copyWith(
                      fontWeight: FontWeight.w400,
                      color: !enabled
                          ? c.textDisabled
                          : i == widget.value
                          ? c.textSecondary
                          : c.textMuted,
                      decoration: TextDecoration.none,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// A pílula liga/desliga (DS `.eg-pill-toggle`): mono 12/16, 24 de altura,
/// 10 de respiro, raio 6, borda `lineStrong`; ligada, `accentSoft` com
/// `accent`.
class _AutoPill extends StatelessWidget {
  const _AutoPill({required this.on, required this.onChanged});

  final bool on;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    return Pressable(
      onPressed: onChanged == null ? null : () => onChanged!(!on),
      semanticLabel: 'O modelo escolhe o esforço',
      builder: (context, s) => AnimatedContainer(
        duration: egDuration(context, EgeonMotion.instant),
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 10 - 1),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? c.accentSoft : null,
          borderRadius: BorderRadius.circular(EgeonRadius.sm),
          border: Border.all(
            color: s.focused
                ? c.accent
                : on
                ? c.accent
                : s.hovered
                ? c.controlBorder
                : c.lineStrong,
            width: s.focused ? EgeonBorder.focus : EgeonBorder.hairline,
          ),
        ),
        child: Text(
          'auto',
          style: EgeonType.monoMeta.copyWith(
            fontWeight: FontWeight.w400,
            color: on
                ? c.accent
                : s.hovered
                ? c.textPrimary
                : c.textMuted,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
}
