import 'package:flutter/widgets.dart';

import '../../theme/app_colors.dart';

/// A chapa flutuante da barra lateral e dos avisos: fundo quase opaco, fio
/// claro e uma sombra que a descola do que passa por baixo.
class GlassPanel extends StatelessWidget {
  const GlassPanel({required this.child, this.radius = 14, super.key});

  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xFF212121).withValues(alpha: 0.95),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: AppColors.white(0.10)),
      boxShadow: [
        BoxShadow(
          color: AppColors.black(0.4),
          blurRadius: 16,
          offset: const Offset(0, 3),
        ),
      ],
    ),
    child: ClipRRect(borderRadius: BorderRadius.circular(radius), child: child),
  );
}
