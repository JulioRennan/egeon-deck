import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../../commons/widgets/eg/button.dart';
import '../../../../commons/widgets/eg/eg_icon.dart';
import '../../../../commons/widgets/eg/menu.dart';
import '../../../../commons/widgets/eg/popover.dart';
import '../../../../theme/egeon_colors.dart';
import '../../../../theme/egeon_tokens.dart';
import '../../../../theme/egeon_type.dart';
import '../../domain/entities/sidebar_filters.dart';
import '../../domain/entities/sidebar_tab.dart';
import '../../domain/entities/sidebar_tree.dart';
import 'bench_actions.dart';
import 'group_actions.dart';
import 'sidebar_active_view.dart';
import 'sidebar_commands.dart';
import 'sidebar_drop.dart';
import 'sidebar_filters_panel.dart';
import 'sidebar_header.dart';
import 'sidebar_tree_view.dart';

/// A barra lateral por inteiro, para dentro da gaveta: cabeçalho (visão, busca
/// e "Novo") e a lista que rola — a árvore ou as ativas, já filtradas pela
/// busca.
class SidebarPanel extends StatefulWidget {
  const SidebarPanel({
    required this.tree,
    required this.tab,
    required this.onTab,
    required this.groups,
    required this.benches,
    required this.commands,
    required this.onDrop,
    required this.onPlan,
    this.findRequests,
    this.takeFindPending,
    this.onCollapse,
    super.key,
  });

  final SidebarTree tree;
  final SidebarTab tab;
  final ValueChanged<SidebarTab> onTab;
  final GroupActions groups;
  final BenchActions benches;
  final SidebarCommands commands;
  final void Function(DragItem item, Drop target) onDrop;
  final PlanDrop onPlan;

  /// ⌘K: cada evento abre a busca e põe o foco nela.
  final Stream<void>? findRequests;

  /// Um ⌘K que chegou com a barra fora da tela: ela o atende ao nascer.
  final bool Function()? takeFindPending;

  /// Recolher a gaveta (o último botão do cabeçalho).
  final VoidCallback? onCollapse;

  @override
  State<SidebarPanel> createState() => _SidebarPanelState();
}

class _SidebarPanelState extends State<SidebarPanel> {
  final _query = TextEditingController();
  final _focus = FocusNode(debugLabel: 'busca da barra lateral');
  bool _searching = false;
  String _text = '';
  final _filters = ValueNotifier(SidebarFilters.none);
  StreamSubscription<void>? _subscription;

  @override
  void initState() {
    super.initState();
    _listen();
    if (widget.takeFindPending?.call() ?? false) _openSearch();
  }

  void _listen() => _subscription = widget.findRequests?.listen((_) {
    if (widget.takeFindPending?.call() ?? true) _openSearch();
  });

  void _openSearch() {
    setState(() => _searching = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        _query.clear();
        _text = '';
      }
    });
  }

  void _clear() {
    _query.clear();
    _filters.value = SidebarFilters.none;
    setState(() => _text = '');
  }

  @override
  void didUpdateWidget(SidebarPanel old) {
    super.didUpdateWidget(old);
    // O popover aberto relê a visão e a árvore: uma cópia nova o reconstrói
    // (fora da construção, que não deixa avisar ouvintes).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _filters.value = SidebarFilters(
        situations: _filters.value.situations,
        workspaceId: _filters.value.workspaceId,
      );
    });
    if (old.findRequests != widget.findRequests) {
      _subscription?.cancel();
      _listen();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _query.dispose();
    _focus.dispose();
    _filters.dispose();
    super.dispose();
  }

  void _filtersPopover(Rect anchor) => showPopover(
    context,
    anchor: anchor,
    placement: PopoverPlacement.bottomEnd,
    width: filtersPanelWidth,
    padding: const EdgeInsets.all(6),
    builder: (_, _) => ListenableBuilder(
      listenable: _filters,
      builder: (_, _) => SidebarFiltersPanel(
        filters: _filters.value,
        onFilters: (f) {
          _filters.value = f;
          setState(() {});
        },
        tab: widget.tab,
        onTab: widget.onTab,
        tree: widget.tree,
      ),
    ),
  );

  void _newMenu(Rect anchor) => showMenu(
    context,
    anchor: anchor,
    placement: PopoverPlacement.bottomEnd,
    width: 260,
    items: [
      MenuItem(
        'Novo workspace…',
        icon: EgIcons.layers,
        onSelected: widget.commands.onCreateWorkspace,
      ),
      const MenuSeparator(),
      MenuItem(
        'Nova bancada…',
        icon: EgIcons.plus,
        onSelected: widget.commands.onCreateBench,
      ),
      MenuItem(
        'Nova bancada a partir de worktree…',
        icon: EgIcons.worktree,
        onSelected: widget.commands.onCreateBenchFromWorktree,
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final filters = _filters.value;
    final searching = _text.trim().isNotEmpty || !filters.isEmpty;
    final shown = widget.tree.filtered(_text).narrowed(filters);
    final active = widget.tab == SidebarTab.active;
    final empty = active ? shown.activeCount == 0 : shown.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SidebarHeader(
          tab: widget.tab,
          onTab: widget.onTab,
          allCount: widget.tree.allCount,
          activeCount: widget.tree.activeCount,
          wantsAttention: widget.tree.wantsAttention,
          searching: _searching,
          onToggleSearch: _toggleSearch,
          query: _query,
          searchFocus: _focus,
          onQuery: (value) => setState(() => _text = value),
          onNew: _newMenu,
          onFilters: _filtersPopover,
          filterCount: filters.count,
          onCollapse: widget.onCollapse,
        ),
        const SizedBox(height: EgeonSpace.s2),
        if (!filters.isEmpty)
          SidebarFilterSummary(
            count: filters.count,
            onClear: () {
              _filters.value = SidebarFilters.none;
              setState(() {});
            },
          ),
        Expanded(
          child: SingleChildScrollView(
            // 10 do painel e 2 da lista (a v3), 4 de ar em cima.
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!active)
                  SidebarTreeView(
                    tree: shown,
                    groups: widget.groups,
                    benches: widget.benches,
                    commands: widget.commands,
                    onDrop: widget.onDrop,
                    onPlan: widget.onPlan,
                  )
                else
                  SidebarActiveView(
                    tree: shown,
                    benches: widget.benches,
                    commands: widget.commands,
                  ),
                if (empty)
                  _Empty(searching: searching, active: active, onClear: _clear),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({
    required this.searching,
    required this.active,
    required this.onClear,
  });

  final bool searching;
  final bool active;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    final message = searching
        ? 'Nenhuma bancada com esses filtros.'
        : active
        ? 'Nenhuma bancada de pé.\nAbra uma na visão Todas.'
        : 'Nenhuma bancada.\nUse + para criar,\nvazia ou de um template.';
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        EgeonSpace.s4,
        EgeonSpace.s6,
        EgeonSpace.s4,
        0,
      ),
      child: Column(
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: EgeonType.small.copyWith(
              color: c.textMuted,
              decoration: TextDecoration.none,
            ),
          ),
          if (searching) ...[
            const SizedBox(height: EgeonSpace.s3),
            Button(
              label: 'Limpar filtros',
              size: ButtonSize.sm,
              kind: ButtonKind.ghost,
              onPressed: onClear,
            ),
          ],
        ],
      ),
    );
  }
}
