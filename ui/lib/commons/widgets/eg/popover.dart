import 'package:flutter/widgets.dart';

import '../../../theme/egeon_tokens.dart';
import 'glass_surface.dart';
import 'layer.dart';

enum PopoverPlacement { bottomStart, bottomEnd }

/// Abre um popover ancorado em [anchor] (retângulo em coordenadas globais, ou
/// um ponto de largura zero, como no menu de contexto). Desce da âncora e, sem
/// espaço, sobe; nas bordas da janela encosta com 8px de margem. Vidro, raio
/// 12 ([radius]), vão de 6 da âncora ([gap]) e respiro de 20 por padrão.
Layer showPopover(
  BuildContext context, {
  required Rect anchor,
  required Widget Function(BuildContext context, VoidCallback close) builder,
  PopoverPlacement placement = PopoverPlacement.bottomStart,
  EdgeInsetsGeometry padding = const EdgeInsets.all(EgeonSpace.s5),
  double? width,
  double radius = EgeonRadius.lg,
  double gap = 6,
  VoidCallback? onClosed,
}) {
  final overlayBox =
      Overlay.of(context).context.findRenderObject()! as RenderBox;
  final local = Rect.fromPoints(
    overlayBox.globalToLocal(anchor.topLeft),
    overlayBox.globalToLocal(anchor.bottomRight),
  );
  return showLayer(
    context,
    onClosed: onClosed,
    builder: (context, layer) => CustomSingleChildLayout(
      delegate: _PopoverLayout(local, placement, gap),
      child: LayerEntrance(
        offset: const Offset(0, -4),
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          child: GlassSurface(
            radius: radius,
            padding: padding,
            child: builder(context, layer.close),
          ),
        ),
      ),
    ),
  );
}

class _PopoverLayout extends SingleChildLayoutDelegate {
  _PopoverLayout(this.anchor, this.placement, this.gap);

  final Rect anchor;
  final PopoverPlacement placement;
  final double gap;
  static const margin = 8.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(
        maxWidth: constraints.maxWidth - 2 * margin,
        maxHeight: constraints.maxHeight - 2 * margin,
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    var x = placement == PopoverPlacement.bottomStart
        ? anchor.left
        : anchor.right - childSize.width;
    x = x.clamp(
      margin,
      (size.width - childSize.width - margin).clamp(margin, double.infinity),
    );
    final below = anchor.bottom + gap;
    final above = anchor.top - gap - childSize.height;
    final fitsBelow = below + childSize.height <= size.height - margin;
    var y = fitsBelow || above < margin ? below : above;
    y = y.clamp(
      margin,
      (size.height - childSize.height - margin).clamp(margin, double.infinity),
    );
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_PopoverLayout old) =>
      old.anchor != anchor || old.placement != placement || old.gap != gap;
}
