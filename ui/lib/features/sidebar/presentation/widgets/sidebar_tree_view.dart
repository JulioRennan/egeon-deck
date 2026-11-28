import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../../theme/egeon_colors.dart';
import '../../../../theme/egeon_tokens.dart';
import '../../../../theme/egeon_type.dart';
import '../../domain/entities/sidebar_bench.dart';
import '../../domain/entities/sidebar_tree.dart';
import '../../domain/repository/sidebar_repository.dart';
import 'bench_actions.dart';
import 'sidebar_commands.dart';
import 'sidebar_item.dart';
import 'sidebar_menus.dart';
import '../../../../commons/widgets/eg/menu.dart';
import '../../../../commons/widgets/eg/popover.dart';
import 'drag_hooks.dart';
import 'group_actions.dart';
import 'sidebar_drop.dart';

/// A aba Todas: workspace → projeto → bancada. Arrastar uma linha mostra uma
/// guia de inserção onde ela vai cair; soltar avisa por [onDrop].
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
    required this.commands,
    super.key,
  });

  final SidebarTree tree;
  final GroupActions groups;
  final BenchActions benches;
  final void Function(DragItem item, Drop target) onDrop;
  final PlanDrop onPlan;
  final SidebarCommands commands;

  @override
  State<SidebarTreeView> createState() => _SidebarTreeViewState();
}

class _SidebarTreeViewState extends State<SidebarTreeView> {
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

  void _menu(Rect anchor, List<MenuElement> items) => showMenu(
    context,
    anchor: anchor,
    placement: PopoverPlacement.bottomEnd,
    width: 232,
    items: items,
  );

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    return Stack(
      key: _root,
      children: [
        _expanded(),
        if (_guide != null)
          Positioned.fromRect(
            rect: _guide!,
            child: IgnorePointer(
              child: DecoratedBox(
                key: const ValueKey('drop-guide'),
                decoration: BoxDecoration(
                  color: c.accent,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _expanded() => Padding(
    padding: EdgeInsets.zero,
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
      // O que se mede é o bloco todo, do cabeçalho até a última linha.
      KeyedSubtree(
        key: _key('card:${ws.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SidebarItem.workspace(
              key: ValueKey('ws-${ws.id}'),
              workspace: ws,
              onPressed: () => widget.groups.onToggleWorkspace(ws.id),
              onMenu: (anchor) => _menu(
                anchor,
                workspaceMenu(workspace: ws, actions: widget.groups),
              ),
              drag: _hooks(DragWorkspace(ws.id)),
            ),
            if (!ws.collapsed)
              Padding(
                padding: const EdgeInsets.only(top: 2),
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
                  ],
                ),
              ),
          ],
        ),
      ),
      // 18 entre um workspace e o seguinte (a v3).
      const SizedBox(height: 18),
    ],
  );

  Widget _project(SidebarWorkspace ws, SidebarProject project) {
    final open = !project.collapsed && project.benches.isNotEmpty;
    return Padding(
      key: ValueKey('project-${project.id}'),
      padding: const EdgeInsets.only(bottom: 2),
      child: KeyedSubtree(
        key: _key('project:${project.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            KeyedSubtree(
              key: _key('header:${project.id}'),
              child: SidebarItem.project(
                project: project,
                owner: ws,
                onPressed: () => project.benches.isEmpty
                    ? _createIn(project)
                    : widget.groups.onToggleProject(ws.id, project.id),
                onAdd: () => _createIn(project),
                onMenu: (anchor) => _menu(
                  anchor,
                  projectMenu(
                    workspace: ws,
                    project: project,
                    actions: widget.groups,
                    commands: widget.commands,
                  ),
                ),
                drag: _hooks(
                  DragProject(ws.id, project.id, stored: project.stored),
                ),
              ),
            ),
            if (open)
              Container(
                margin: const EdgeInsets.fromLTRB(18, 6, 0, 14),
                padding: const EdgeInsets.only(left: 10),
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(color: context.eg.lineSubtle),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ..._spaced([
                      for (final bench in project.benches)
                        _bench(bench, project: project),
                    ]),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Projeto vazio: o clique cria; multi-projeto só nasce em worktree, e vai
  /// direto. Os outros abrem o menu de criar.
  void _createIn(SidebarProject project) => project.isMulti
      ? widget.commands.onCreateBenchFromWorktreeIn(project)
      : widget.commands.onCreateBenchIn(project);

  /// Entre uma bancada e outra: um vão de 4, sem fio (a v3).
  List<Widget> _spaced(List<Widget> items) => [
    for (var i = 0; i < items.length; i++) ...[
      if (i > 0) const SizedBox(height: EgeonSpace.s1),
      items[i],
    ],
  ];

  Widget _bench(SidebarBench bench, {SidebarProject? project}) => Padding(
    key: ValueKey('bench-${bench.id}'),
    padding: EdgeInsets.zero,
    child: KeyedSubtree(
      key: _key('bench:${bench.id}'),
      child: SidebarItem.bench(
        bench: bench,
        onPressed: () => widget.benches.onSelect(bench.id),
        onMenu: (anchor) => _menu(
          anchor,
          benchMenu(
            context,
            bench: bench,
            actions: widget.benches,
            commands: widget.commands,
            project: project,
          ),
        ),
        drag: _hooks(DragBench(bench.id)),
      ),
    ),
  );

  Widget _orphans(List<SidebarBench> orphans) {
    final c = context.eg;
    return Container(
      margin: const EdgeInsets.only(bottom: EgeonSpace.s2),
      padding: const EdgeInsets.only(bottom: _inset),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(EgeonRadius.lg),
        border: Border.all(color: c.attention.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              EgeonSpace.s3,
              EgeonSpace.s2,
              EgeonSpace.s3,
              EgeonSpace.s2,
            ),
            child: Text(
              'Sem projeto',
              style: EgeonType.small.copyWith(
                color: c.attention,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.none,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: _inset),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Órfã se arrasta como as outras: soltar num projeto é como ela
                // ganha casa (`Sidebar.swift` liga o arrasto também nela).
                ..._spaced([for (final bench in orphans) _bench(bench)]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
