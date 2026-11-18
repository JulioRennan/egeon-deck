import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../../theme/app_colors.dart';
import '../../domain/entities/workbench_tab.dart';
import '../../../../commons/widgets/press_drag.dart';
import 'tab_drag_layout.dart';
import 'workbench_tab_pill.dart';

/// A faixa das bancadas abertas. Quem manda na ordem é o core Rust: o que vem
/// de fora reordena as pastilhas que já existem (sem recriá-las), e o arrasto
/// só avisa a ordem final.
class WorkbenchTabsBar extends StatefulWidget {
  const WorkbenchTabsBar({
    required this.tabs,
    required this.onPick,
    required this.onClose,
    required this.onReorder,
    this.leftInset = 0,
    super.key,
  });

  final List<WorkbenchTab> tabs;
  final ValueChanged<String> onPick;
  final ValueChanged<String> onClose;
  final ValueChanged<List<String>> onReorder;

  /// Quanto a barra lateral cobre da borda esquerda.
  final double leftInset;

  static const height = 34.0;
  static const gap = 4.0;

  /// Abaixo disto uma pastilha deixa de mostrar o nome.
  static const minWidth = 52.0;

  @override
  State<WorkbenchTabsBar> createState() => _WorkbenchTabsBarState();
}

class _Drag {
  _Drag({required this.id, required this.grab, required this.index});

  final String id;
  final double grab;
  int index;
  double x = 0;
}

class _WorkbenchTabsBarState extends State<WorkbenchTabsBar> {
  late List<String> _order = [for (final tab in widget.tabs) tab.id];
  _Drag? _drag;
  List<double> _frozen = const [];

  @override
  void didUpdateWidget(WorkbenchTabsBar old) {
    super.didUpdateWidget(old);
    // Com o arrasto em curso a ordem na tela é a da mão, não a do app: só o
    // estado das pastilhas acompanha.
    if (_drag == null && !identical(old.tabs, widget.tabs)) {
      _order = [for (final tab in widget.tabs) tab.id];
    }
  }

  WorkbenchTab? _tab(String id) {
    for (final tab in widget.tabs) {
      if (tab.id == id) return tab;
    }
    return null;
  }

  List<double> _widths(double available) {
    final wanted = [
      for (final id in _order) WorkbenchTabPill.fittingWidth(_tab(id)!),
    ];
    final total =
        wanted.fold<double>(0, (a, b) => a + b) +
        (wanted.length - 1) * WorkbenchTabsBar.gap;
    final scale = total > available && total > 0 ? available / total : 1.0;
    return [
      for (final w in wanted)
        math.max(WorkbenchTabsBar.minWidth, (w * scale).roundToDouble()),
    ];
  }

  double get _start => widget.leftInset + WorkbenchTabsBar.gap;

  /// O ponteiro chega em coordenada global; a conta é na faixa.
  double _local(double globalX) => (context.findRenderObject()! as RenderBox)
      .globalToLocal(Offset(globalX, 0))
      .dx;

  void _begin(String id, double globalX, List<double> widths) {
    final pointerX = _local(globalX);
    final index = _order.indexOf(id);
    final xs = TabDragLayout.offsets(
      widths: widths,
      start: _start,
      gap: WorkbenchTabsBar.gap,
    );
    setState(() {
      _frozen = widths;
      _drag = _Drag(id: id, grab: pointerX - xs[index], index: index)
        ..x = xs[index];
    });
  }

  void _move(double globalX) {
    final drag = _drag;
    if (drag == null) return;
    final x = _local(globalX) - drag.grab;
    final target = TabDragLayout.destination(
      center: x + _frozen[drag.index] / 2,
      dragging: drag.index,
      widths: _frozen,
      start: _start,
      gap: WorkbenchTabsBar.gap,
    );
    setState(() {
      drag.x = x;
      if (target != drag.index) {
        _order = TabDragLayout.moved(_order, drag.index, target);
        _frozen = TabDragLayout.moved(_frozen, drag.index, target);
        drag.index = target;
      }
    });
  }

  void _end({required bool commit}) {
    if (_drag == null) return;
    setState(() => _drag = null);
    if (commit) widget.onReorder(List.of(_order));
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.tabsBar,
      child: SizedBox(
        height: WorkbenchTabsBar.height,
        child: LayoutBuilder(
          builder: (context, box) {
            final live = _drag == null;
            final widths = live
                ? _widths(math.max(0, box.maxWidth - widget.leftInset - 8))
                : _frozen;
            final xs = TabDragLayout.offsets(
              widths: widths,
              start: _start,
              gap: WorkbenchTabsBar.gap,
            );
            final y = (WorkbenchTabsBar.height - WorkbenchTabPill.height) / 2;
            final dragged = _drag?.id;
            // A arrastada por último: sobe para o topo da pilha.
            final ids = [..._order.where((id) => id != dragged), ?dragged];
            return Stack(
              clipBehavior: Clip.none,
              children: [
                for (final id in ids)
                  _placed(
                    id: id,
                    x: id == dragged ? _drag!.x : xs[_order.indexOf(id)],
                    y: y,
                    width: widths[_order.indexOf(id)],
                    followHand: id == dragged,
                    widths: widths,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _placed({
    required String id,
    required double x,
    required double y,
    required double width,
    required bool followHand,
    required List<double> widths,
  }) {
    final tab = _tab(id)!;
    final pill = PressDrag(
      key: ValueKey('tab-$id'),
      ignoreTrailing: 24,
      onClick: () => widget.onPick(id),
      onBegin: (point) => _begin(id, point.dx, widths),
      onMove: (point) => _move(point.dx),
      onEnd: (cancelled) => _end(commit: !cancelled),
      child: WorkbenchTabPill(
        tab: tab,
        lifted: followHand,
        onClose: () => widget.onClose(id),
      ),
    );
    // A da mão segue o cursor sem atraso; as vizinhas deslizam.
    if (followHand) {
      return Positioned(
        key: ValueKey(id),
        left: x,
        top: y,
        width: width,
        height: WorkbenchTabPill.height,
        child: pill,
      );
    }
    return AnimatedPositioned(
      key: ValueKey(id),
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      left: x,
      top: y,
      width: width,
      height: WorkbenchTabPill.height,
      child: pill,
    );
  }
}
