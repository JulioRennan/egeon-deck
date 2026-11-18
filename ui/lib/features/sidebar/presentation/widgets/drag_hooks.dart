import 'dart:ui';

import 'sidebar_drop.dart';

/// Como uma linha da árvore conta o arrasto dela à árvore.
class DragHooks {
  const DragHooks({
    required this.item,
    required this.onBegin,
    required this.onMove,
    required this.onEnd,
    this.dimmed = false,
  });

  final DragItem item;
  final void Function(DragItem item, Offset global) onBegin;
  final void Function(Offset global) onMove;
  final void Function({required bool cancelled}) onEnd;

  /// É esta a linha na mão: fica esmaecida onde estava.
  final bool dimmed;
}
