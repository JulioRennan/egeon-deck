import 'package:flutter/widgets.dart';

import '../../../../commons/widgets/eg/edge_label.dart';
import '../../../../commons/widgets/eg/eg_icon.dart';
import '../../../../commons/widgets/eg/pressable.dart';
import '../../../../theme/egeon_colors.dart';
import '../../../../theme/egeon_type.dart';
import '../../domain/entities/canvas_viewport.dart';
import '../../domain/entities/edge_curve.dart';
import '../../domain/entities/edge_layout.dart';
import '../../domain/entities/edge_link.dart';

/// Os três controles da ligação sob o cursor: direção, limite e remover. Em
/// pixels da janela, e não no documento — alvo de clique tem o mesmo tamanho em
/// qualquer zoom.
class EdgeControlsLayer extends StatelessWidget {
  const EdgeControlsLayer({
    required this.link,
    required this.frames,
    required this.viewport,
    required this.onCycle,
    required this.onLimit,
    required this.onRemove,
    super.key,
  });

  final EdgeLink link;
  final Map<String, Rect> frames;
  final CanvasViewport viewport;
  final VoidCallback onCycle;
  final VoidCallback onLimit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final a = frames[link.a];
    final b = frames[link.b];
    if (a == null || b == null) return const SizedBox.shrink();
    final c = context.eg;
    final laid = EdgeLayout.lay(link, a, b);
    final rects = EdgeLayout.controls(laid, viewport);
    return Stack(
      children: [
        _round(
          context,
          rects.direction,
          onCycle,
          Text(
            laid.directionGlyph,
            style: EgeonType.label.copyWith(
              color: c.accent,
              fontSize: 17,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.none,
            ),
          ),
        ),
        Positioned.fromRect(
          rect: rects.pill,
          child: Pressable(
            onPressed: onLimit,
            semanticLabel: 'Limite da ligação',
            builder: (context, s) => Center(
              child: EdgeLabel(
                max: link.maxSends,
                state: EdgeLabelState.selected,
              ),
            ),
          ),
        ),
        _round(
          context,
          rects.remove,
          onRemove,
          EgIcon(EgIcons.x, size: 14, color: c.accent),
        ),
      ],
    );
  }

  /// Botão redondo de 32 sobre `carbon`, com o fio e o glifo em `accent`.
  Widget _round(
    BuildContext context,
    Rect rect,
    VoidCallback onTap,
    Widget child,
  ) {
    final c = context.eg;
    return Positioned.fromRect(
      rect: rect,
      child: Pressable(
        onPressed: onTap,
        builder: (context, s) => DecoratedBox(
          decoration: BoxDecoration(
            color: s.hovered ? c.steelActive : c.carbon,
            shape: BoxShape.circle,
            border: Border.all(color: c.accent),
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}

/// Os rótulos de limite no meio de cada ligação (menos a que está sob o
/// cursor, que mostra os controles). Só enfeite: o clique passa.
class EdgeLabelsLayer extends StatelessWidget {
  const EdgeLabelsLayer({
    required this.links,
    required this.frames,
    required this.viewport,
    this.hidden,
    super.key,
  });

  final List<EdgeLink> links;
  final Map<String, Rect> frames;
  final CanvasViewport viewport;
  final EdgeLink? hidden;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        for (final link in links)
          if (link != hidden &&
              frames[link.a] != null &&
              frames[link.b] != null)
            _label(link),
      ],
    ),
  );

  Widget _label(EdgeLink link) {
    final laid = EdgeLayout.lay(link, frames[link.a]!, frames[link.b]!);
    final (mid, _) = EdgeCurve.midpoint(laid.route);
    final point = viewport.toScreen(mid);
    // 22 de altura; o rótulo é uma peça de tela, não cresce com o zoom.
    return Positioned(
      left: point.dx,
      top: point.dy,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: EdgeLabel(max: link.maxSends),
      ),
    );
  }
}
