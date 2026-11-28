import 'package:flutter/widgets.dart';

import '../../../../commons/utils/bench_identity.dart';
import '../../../../commons/widgets/eg/motion.dart';
import '../../../../theme/egeon_colors.dart';
import '../../../../theme/egeon_glass.dart';
import '../../../../theme/egeon_tokens.dart';

/// A moldura da área de conteúdo: um painel `graphite` de raio 16 com fio de
/// 1px, e a cor da bancada por dentro (borda a 18% e um brilho de 32px a 14%).
/// Trocar de bancada troca a cor, em 200 ms.
class BenchFrame extends StatelessWidget {
  const BenchFrame({
    required this.child,
    this.colorName,
    this.lit = true,
    super.key,
  });

  /// O nome gravado pelo core (`blue`, `sand`…); ver [BenchIdentity].
  final String? colorName;

  /// Sem bancada na tela não há cor a mostrar.
  final bool lit;
  final Widget child;

  static const radius = 16.0;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    final color = BenchIdentity.of(colorName).color(c);
    final shape = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.graphite,
        borderRadius: shape,
        border: Border.all(color: EgeonGlass.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius - 1),
        child: Stack(
          fit: StackFit.expand,
          children: [
            child,
            if (lit)
              IgnorePointer(
                child: TweenAnimationBuilder<Color?>(
                  tween: ColorTween(end: color),
                  duration: egDuration(context, EgeonMotion.base),
                  builder: (context, value, _) =>
                      CustomPaint(painter: GlowPainter(value ?? color)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// O fio e o brilho de dentro da moldura, mais fortes que o v3 (que pede
/// fio a 18% e brilho a 14%): a pedido, a cor da bancada marca bem a borda.
class GlowPainter extends CustomPainter {
  GlowPainter(this.color);

  final Color color;

  static const edgeAlpha = 0.32;
  static const glowAlpha = 0.22;
  static const glowBlur = 32.0;

  @override
  void paint(Canvas canvas, Size size) {
    final shape = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(BenchFrame.radius - 1),
    );
    canvas.save();
    canvas.clipRRect(shape);
    // O brilho: tudo o que está fora da forma, borrado para dentro dela.
    final outside = Path.combine(
      PathOperation.difference,
      Path()..addRect((Offset.zero & size).inflate(glowBlur * 2)),
      Path()..addRRect(shape),
    );
    canvas.drawPath(
      outside,
      Paint()
        ..color = color.withValues(alpha: glowAlpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, glowBlur / 2),
    );
    canvas.restore();
    canvas.drawRRect(
      shape.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = color.withValues(alpha: edgeAlpha),
    );
  }

  @override
  bool shouldRepaint(GlowPainter old) => old.color != color;
}
