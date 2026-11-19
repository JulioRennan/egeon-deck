import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../../theme/app_colors.dart';
import '../../domain/entities/sidebar_bench.dart';
import '../../domain/entities/sidebar_tree.dart';
import '../../domain/repository/sidebar_repository.dart';
import 'bench_actions.dart';
import 'bench_row.dart';
import 'drag_hooks.dart';
import 'drawer_row.dart';
import 'group_actions.dart';
import 'group_row.dart';
import 'sidebar_drop.dart';

/// A aba Todas: workspace → projeto → bancada. Recolhida ao trilho, só sobram
/// as pastilhas da inicial. Arrastar uma linha mostra uma guia de inserção
/// onde ela vai cair; soltar avisa por [onDrop].
/// Pergunta ao core onde o item cairia: `null` se ele recusa.
typedef PlanDrop = Future<MoveLanding?> Function(
  String kind,
  String item, {
  String? parent,
  required int to,
});

class SidebarTreeView extends StatefulWidget {
  const SidebarTreeView({
    required this.tree,
    required this.groups,
    required this.benches,
    required this.onDrop,
    required this.onPlan,
    this.compact = false,
    super.key,
  });

  final SidebarTree tree;
  final GroupActions groups;
  final BenchActions benches;
  final void Function(DragItem item, Drop target) onDrop;
  final PlanDrop onPlan;
  final bool compact;

  @override
  State<SidebarTreeView> createState() => _SidebarTreeViewState();
}

class _SidebarTreeViewState extends State<SidebarTreeView> {
  static const _outer = 8.0;
  static const _inset = 6.0;
  static const _cardGap = 8.0;

  /// Uma chave por elemento medido: é por elas que o arrasto lê onde cada
  /// coisa está na tela.
  final _keys = <String, GlobalKey>{};
  final _root = GlobalKey();

  DragItem? _dragged;
  Rect? _guide;

  GlobalKey _key(String id) => _keys.putIfAbsent(id, GlobalKey.new);

  SidebarTree get _tree => widget.tree;

  // ---- arrasto

  void _begin(DragItem item, Offset global) {
    setState(() => _dragged = item);
    _move(global);
  }

  /// O último alvo que se perguntou ao core, e a pergunta mais nova: resposta
  /// de pergunta velha, que chega depois, não vale.
  Drop? _asked;
  var _question = 0;

  /// O alvo que o core aceitou: soltar fora dele não faz nada.
  Drop? _accepted;

  void _move(Offset global) {
    final item = _dragged;
    if (item == null) return;
    final geometry = _geometry();
    final target = geometry.drop(item, _local(global));
    if (target == _asked) return;
    _asked = target;
    _accepted = null;
    final question = ++_question;
    if (target == null) {
      setState(() => _guide = null);
      return;
    }
    unawaited(_plan(question, geometry, item, target));
  }

  /// A guia só aparece onde o core diz que o item cai.
  Future<void> _plan(
    int question,
    SidebarDropGeometry geometry,
    DragItem item,
    Drop target,
  ) async {
    final request = target.requestFor(item);
    final landing = await widget.onPlan(
      request.kind,
      item.id,
      parent: request.parent,
      to: request.to,
    );
    if (!mounted || question != _question || _dragged == null) return;
    _accepted = landing == null ? null : target;
    setState(
      () => _guide = landing == null
          ? null
          : geometry.guide(
              target.landingAt(parent: landing.parent, to: landing.to),
            ),
    );
  }

  void _end({required bool cancelled}) {
    final item = _dragged;
    final point = _lastPoint;
    final target = _accepted;
    _asked = null;
    _accepted = null;
    _question++;
    setState(() {
      _dragged = null;
      _guide = null;
    });
    if (cancelled || item == null || point == null || target == null) return;
    widget.onDrop(item, target);
  }

  Offset? _lastPoint;

  Offset _local(Offset global) {
    final box = _root.currentContext!.findRenderObject()! as RenderBox;
    return _lastPoint = box.globalToLocal(global);
  }

  Rect? _rect(String id) {
    final box = _keys[id]?.currentContext?.findRenderObject() as RenderBox?;
    final root = _root.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || root == null || !box.attached) return null;
    return box.localToGlobal(Offset.zero, ancestor: root) & box.size;
  }

  SidebarDropGeometry _geometry() {
    TileFrame? tile(SidebarProject project) {
      final frame = _rect('project:${project.id}');
      final header = _rect('header:${project.id}');
      if (frame == null || header == null) return null;
      final open = !project.collapsed;
      return TileFrame(
        projectId: project.id,
        frame: frame,
        header: header,
        rows: open
            ? [
                for (final bench in project.benches)
                  if (_rect('bench:${bench.id}') case final r?)
                    RowFrame(bench.id, r),
              ]
            : const [],
      );
    }

    final cards = <CardFrame>[];
    for (final ws in _tree.workspaces) {
      final frame = _rect('card:${ws.id}');
      if (frame == null) continue;
      final drawer = _rect('drawer:${ws.id}');
      cards.add(
        CardFrame(
          workspaceId: ws.id,
          frame: frame,
          drawer:
              drawer ?? Rect.fromLTWH(frame.left, frame.bottom, frame.width, 0),
          projects: ws.collapsed
              ? const []
              : [for (final p in ws.activeProjects) ?tile(p)],
          stored: ws.collapsed || !ws.storedOpen
              ? const []
              : [for (final p in ws.storedProjects) ?tile(p)],
        ),
      );
    }
    final width =
        (_root.currentContext?.findRenderObject() as RenderBox?)?.size.width;
    return SidebarDropGeometry(
      cards,
      cardGap: _cardGap,
      cardInset: _inset,
      listWidth: width ?? 0,
    );
  }

  DragHooks _hooks(DragItem item) => DragHooks(
    item: item,
    onBegin: _begin,
    onMove: _move,
    onEnd: _end,
    dimmed: _dragged == item,
  );

  // ---- construção

  @override
  Widget build(BuildContext context) => Stack(
    key: _root,
    children: [
      widget.compact ? _rail() : _expanded(),
      if (_guide != null)
        Positioned.fromRect(
          rect: _guide!,
          child: IgnorePointer(
            child: DecoratedBox(
              key: const ValueKey('drop-guide'),
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        ),
    ],
  );

  Widget _rail() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 2),
    child: Column(
      children: [
        for (final ws in _tree.workspaces) ...[
          SidebarGroupRow.workspace(
            workspace: ws,
            actions: widget.groups,
            compact: true,
            key: ValueKey('ws-${ws.id}'),
          ),
          if (!ws.collapsed)
            for (final project in ws.projects)
              for (final bench in project.benches) ...[
                SidebarBenchRow(
                  key: ValueKey('rail-${bench.id}'),
                  bench: bench,
                  actions: widget.benches,
                  compact: true,
                ),
                const SizedBox(height: 2),
              ],
          const SizedBox(height: 6),
        ],
        for (final bench in _tree.orphans) ...[
          SidebarBenchRow(
            key: ValueKey('rail-${bench.id}'),
            bench: bench,
            actions: widget.benches,
            compact: true,
          ),
          const SizedBox(height: 2),
        ],
      ],
    ),
  );

  Widget _expanded() => Padding(
    padding: const EdgeInsets.fromLTRB(_outer, 2, _outer, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final ws in _tree.workspaces) _workspace(ws),
        if (_tree.orphans.isNotEmpty) _orphans(_tree.orphans),
      ],
    ),
  );

  Widget _workspace(SidebarWorkspace ws) => Column(
    key: ValueKey('card-${ws.id}'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      // O que se mede é o bloco todo, do cabeçalho até o fio de baixo.
      KeyedSubtree(
        key: _key('card:${ws.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SidebarGroupRow.workspace(
              key: ValueKey('ws-${ws.id}'),
              workspace: ws,
              actions: widget.groups,
              drag: _hooks(DragWorkspace(ws.id)),
            ),
            if (!ws.collapsed)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: _inset),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final project in ws.activeProjects)
                      _project(ws, project),
                    KeyedSubtree(
                      key: _key('drawer:${ws.id}'),
                      child: DrawerRow(
                        count: ws.storedProjects.length,
                        open: ws.storedOpen,
                        onToggle: () => widget.groups.onToggleDrawer(ws.id),
                      ),
                    ),
                    if (ws.storedOpen)
                      for (final project in ws.storedProjects) ...[
                        const SizedBox(height: 2),
                        _project(ws, project),
                      ],
                    const SizedBox(height: _inset),
                  ],
                ),
              ),
            Container(
              height: 1,
              margin: const EdgeInsets.fromLTRB(4, 6, 4, 0),
              color: AppColors.white(0.10),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
    ],
  );

  Widget _project(SidebarWorkspace ws, SidebarProject project) {
    final open = !project.collapsed && project.benches.isNotEmpty;
    return Padding(
      key: ValueKey('project-${project.id}'),
      padding: const EdgeInsets.only(bottom: 6),
      child: KeyedSubtree(
        key: _key('project:${project.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            KeyedSubtree(
              key: _key('header:${project.id}'),
              child: SidebarGroupRow.project(
                owner: ws,
                project: project,
                actions: widget.groups,
                drag: _hooks(
                  DragProject(ws.id, project.id, stored: project.stored),
                ),
              ),
            ),
            if (open) ...[
              const SizedBox(height: 4),
              Container(
                height: 1,
                margin: const EdgeInsets.symmetric(horizontal: _inset),
                color: AppColors.white(0.07),
              ),
              const SizedBox(height: 9),
              Padding(
                padding: const EdgeInsets.only(
                  left: _inset,
                  right: _inset,
                  bottom: _inset - 6,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final bench in project.benches) _bench(bench),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _bench(SidebarBench bench) => Padding(
    key: ValueKey('bench-${bench.id}'),
    padding: const EdgeInsets.only(bottom: 6),
    child: KeyedSubtree(
      key: _key('bench:${bench.id}'),
      child: SidebarBenchRow(
        bench: bench,
        actions: widget.benches,
        drag: _hooks(DragBench(bench.id)),
      ),
    ),
  );

  Widget _orphans(List<SidebarBench> orphans) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.only(bottom: _inset),
    decoration: BoxDecoration(
      color: AppColors.white(0.03),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.attention.withValues(alpha: 0.35)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SidebarGroupRow.orphans(orphanCount: orphans.length),
        Container(
          height: 1,
          margin: const EdgeInsets.fromLTRB(_inset, 4, _inset, 9),
          color: AppColors.white(0.07),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: _inset),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Órfã se arrasta como as outras: soltar num projeto é como ela
              // ganha casa (`Sidebar.swift` liga o arrasto também nela).
              for (final bench in orphans) _bench(bench),
            ],
          ),
        ),
      ],
    ),
  );
}
