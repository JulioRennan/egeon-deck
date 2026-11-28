import 'package:flutter/widgets.dart';

import '../../../theme/egeon_colors.dart';
import '../../../theme/egeon_tokens.dart';

/// Os quadros do pulso (`.pulse` e `.pulse-g` da v3): 0% sem folga a 40% de
/// opacidade (`0x66`) → 70% 5px já transparente → 100% sem folga. A curva
/// `cubic-bezier(.4,0,.6,1)` vale em cada trecho.
({double spread, Color color}) haloAt(double t, Color base) {
  final solid = base.withAlpha(0x66);
  final clear = base.withAlpha(0);
  if (t < 0.7) {
    final e = EgeonMotion.easePulse.transform((t / 0.7).clamp(0.0, 1.0));
    return (spread: 5 * e, color: Color.lerp(solid, clear, e)!);
  }
  final e = EgeonMotion.easePulse.transform(((t - 0.7) / 0.3).clamp(0.0, 1.0));
  return (spread: 5 * (1 - e), color: clear);
}

/// O pulso de "precisa de você": a única animação que chama. Um halo nasce
/// colado na forma, cresce até 5px e se dissolve, a cada 1600 ms. Com
/// movimento reduzido o DS desacelera (3200 ms), não para. Com [ring], o
/// filho leva um anel de 1.5px em `attention` (o `AttentionRing` do DS); sem
/// ele, só o halo (o ponto de estado).
class AttentionRing extends StatefulWidget {
  const AttentionRing({
    required this.child,
    this.round = false,
    this.ring = true,
    this.radius = EgeonRadius.sm,
    this.color,
    super.key,
  });

  final Widget child;

  /// Halo circular (dot, contador); senão segue [radius].
  final bool round;
  final bool ring;
  final double radius;

  /// A cor do pulso; sem ela, `attention`. O ponto de "terminou" pulsa em
  /// `success` (o `.pulse-g` da v3).
  final Color? color;

  @override
  State<AttentionRing> createState() => _AttentionRingState();
}

class _AttentionRingState extends State<AttentionRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: EgeonMotion.attention,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.duration = MediaQuery.disableAnimationsOf(context)
        ? EgeonMotion.attention * 2
        : EgeonMotion.attention;
    if (!_controller.isAnimating) _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final tint = widget.color;
        final halo = haloAt(_controller.value, tint ?? c.attention);
        return DecoratedBox(
          decoration: BoxDecoration(
            shape: widget.round ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: widget.round
                ? null
                : BorderRadius.circular(widget.radius),
            boxShadow: [
              BoxShadow(color: halo.color, spreadRadius: halo.spread),
              if (widget.ring)
                BoxShadow(color: tint ?? c.attention, spreadRadius: 1.5),
            ],
          ),
          child: child,
        );
      },
    );
  }
}
