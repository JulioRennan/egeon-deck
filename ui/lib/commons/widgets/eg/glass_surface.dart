import 'package:flutter/widgets.dart';

import '../../../theme/egeon_glass.dart';
import '../../../theme/egeon_tokens.dart';

/// O vidro das peças que flutuam (barra de ações, painel de consumo, menus e
/// popovers): desfoque gaussiano 20 com saturação 130%, fundo `glass`, borda
/// de 1px, fio de luz no topo e `EgeonShadow.glass`. Um `BackdropFilter` por
/// peça, só enquanto ela está à vista; nunca em superfície fixa.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    required this.child,
    this.radius = EgeonRadius.xl,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  final Widget child;

  /// 14 na barra e nos painéis; 12 (`EgeonRadius.lg`) nos menus e popovers.
  final double radius;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        boxShadow: EgeonShadow.glass,
      ),
      child: ClipRRect(
        borderRadius: shape,
        child: BackdropFilter(
          filter: EgeonGlass.filter,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: EgeonGlass.background,
              borderRadius: shape,
              border: Border.all(color: EgeonGlass.border),
            ),
            child: Stack(
              children: [
                Padding(padding: padding, child: child),
                // O inset de 1px do CSS: um fio claro no topo.
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 1,
                  child: ColoredBox(color: EgeonGlass.highlight),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
