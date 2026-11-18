import 'package:flutter/widgets.dart';

import '../../../../commons/widgets/context_menu.dart';
import '../../../../commons/widgets/glyphs.dart';
import '../../../../commons/widgets/toolbar_button.dart';
import '../../../../theme/app_colors.dart';
import '../../domain/entities/sidebar_bench.dart';
import '../../domain/entities/sidebar_tree.dart';
import 'bench_actions.dart';
import 'group_actions.dart';
import 'sidebar_active_view.dart';
import 'sidebar_drop.dart';
import 'sidebar_segments.dart';
import 'sidebar_tree_view.dart';

/// O que o painel pede à casca e que não é da barra: abrir formulários.
class SidebarCommands {
  const SidebarCommands({
    required this.onToggleCollapse,
    required this.onCreateWorkspace,
    required this.onCreateBench,
    required this.onCreateBenchFromWorktree,
    required this.onCreateBenchIn,
    required this.onCreateBenchFromWorktreeIn,
    required this.onEditWorkspace,
    required this.onCreateProject,
    required this.onRemoveWorkspace,
    required this.onRemoveProject,
    required this.onRename,
    required this.onDuplicateAsWorktree,
    required this.onEditRules,
    required this.onRecolor,
    required this.onClear,
    required this.onRemove,
  });

  final VoidCallback onToggleCollapse;
  final VoidCallback onCreateWorkspace;
  final VoidCallback onCreateBench;
  final VoidCallback onCreateBenchFromWorktree;
  final void Function(SidebarProject project) onCreateBenchIn;
  final void Function(SidebarProject project) onCreateBenchFromWorktreeIn;
  final void Function(SidebarWorkspace workspace) onEditWorkspace;
  final void Function(SidebarWorkspace workspace) onCreateProject;
  final void Function(SidebarWorkspace workspace) onRemoveWorkspace;
  final void Function(SidebarWorkspace workspace, SidebarProject project)
  onRemoveProject;
  final void Function(SidebarBench bench) onRename;
  final void Function(SidebarBench bench) onDuplicateAsWorktree;
  final void Function(SidebarBench bench) onEditRules;
  final void Function(SidebarBench bench) onRecolor;
  final void Function(SidebarBench bench) onClear;
  final void Function(SidebarBench bench) onRemove;
}

/// A barra lateral por inteiro: cabeçalho com as duas abas e a lista que rola.
class SidebarPanel extends StatelessWidget {
  const SidebarPanel({
    required this.tree,
    required this.tab,
    required this.onTab,
    required this.groups,
    required this.benches,
    required this.commands,
    required this.onDrop,
    required this.onPlan,
    this.compact = false,
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

  /// Recolhida ao trilho.
  final bool compact;

  static const expandedWidth = 308.0;
  static const railWidth = 52.0;

  void _createMenu(BuildContext context) {
    final box = context.findRenderObject()! as RenderBox;
    final origin = box.localToGlobal(Offset(box.size.width - 60, 40));
    showContextMenu(
      context,
      position: origin,
      entries: [
        MenuEntry('Novo workspace…', commands.onCreateWorkspace),
        const MenuEntry.separator(),
        MenuEntry('Nova bancada…', commands.onCreateBench),
        MenuEntry(
          'Nova bancada a partir de worktree…',
          commands.onCreateBenchFromWorktree,
        ),
      ],
    );
  }

  String? get _emptyMessage {
    if (compact) return null;
    return switch (tab) {
      SidebarTab.all =>
        tree.isEmpty
            ? 'Nenhuma bancada.\nUse + para criar,\nvazia ou de um template.'
            : null,
      SidebarTab.active =>
        tree.activeCount == 0
            ? 'Nenhuma bancada de pé.\nAbra uma na aba Todas.'
            : null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final message = _emptyMessage;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(context),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (tab == SidebarTab.all)
                  SidebarTreeView(
                    tree: tree,
                    groups: groups,
                    benches: benches,
                    onDrop: onDrop,
                    onPlan: onPlan,
                    compact: compact,
                  )
                else
                  SidebarActiveView(
                    tree: tree,
                    benches: benches,
                    compact: compact,
                  ),
                if (message != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Text(
                      message,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.white(0.45),
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _header(BuildContext context) {
    final collapse = ToolbarButton(
      onTap: commands.onToggleCollapse,
      child: ChevronGlyph(
        compact ? ChevronDirection.right : ChevronDirection.left,
        color: AppColors.white(0.6),
      ),
    );
    if (compact) {
      return SizedBox(height: 34, child: Center(child: collapse));
    }
    return SizedBox(
      height: 48,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 2, 10, 0),
        child: Row(
          children: [
            Expanded(
              child: SidebarSegments(
                selected: tab,
                allCount: tree.allCount,
                activeCount: tree.activeCount,
                onSelect: onTab,
              ),
            ),
            const SizedBox(width: 8),
            ToolbarButton(
              onTap: () => _createMenu(context),
              child: Text(
                '+',
                style: TextStyle(
                  fontSize: 17,
                  color: AppColors.white(0.6),
                  decoration: TextDecoration.none,
                ),
              ),
            ),
            const SizedBox(width: 6),
            collapse,
          ],
        ),
      ),
    );
  }
}
