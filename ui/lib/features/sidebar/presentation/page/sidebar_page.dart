import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubit/sidebar_cubit.dart';
import '../widgets/bench_actions.dart';
import '../widgets/group_actions.dart';
import '../../domain/entities/sidebar_tab.dart';
import '../widgets/sidebar_commands.dart';
import '../widgets/sidebar_drop.dart';
import '../widgets/sidebar_panel.dart';

/// A barra lateral. Escolher, recolher e guardar vão ao core; o que abre
/// formulário volta para a casca por [commands]. Precisa de um [SidebarCubit]
/// acima, que a casca provê: ela também muda a aba quando o core pede de fora.
class SidebarPage extends StatelessWidget {
  const SidebarPage({
    required this.commands,
    this.onCollapse,
    this.onAppMenu,
    super.key,
  });

  final SidebarCommands commands;

  /// Recolher a gaveta: o último botão do cabeçalho.
  final VoidCallback? onCollapse;

  /// O menu ☰ do app, fora do macOS (decisão 55).
  final void Function(BuildContext context, Rect anchor)? onAppMenu;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SidebarCubit, SidebarState>(
      builder: (context, state) {
        final cubit = context.read<SidebarCubit>();
        return SidebarPanel(
          tree: state.tree,
          tab: switch (state) {
            SidebarAll() => SidebarTab.all,
            SidebarActive() => SidebarTab.active,
          },
          onTab: cubit.showTab,
          findRequests: cubit.findRequests,
          takeFindPending: cubit.takeFindPending,
          commands: commands,
          onCollapse: onCollapse,
          onAppMenu: onAppMenu,
          onDrop: (item, target) => _drop(cubit, item, target),
          onPlan: cubit.planMove,
          groups: GroupActions(
            onToggleWorkspace: cubit.toggleWorkspace,
            onToggleProject: cubit.toggleProject,
            onCreateBench: commands.onCreateBenchIn,
            onCreateBenchFromWorktree: commands.onCreateBenchFromWorktreeIn,
            onEditWorkspace: commands.onEditWorkspace,
            onCreateProject: commands.onCreateProject,
            onRemoveWorkspace: commands.onRemoveWorkspace,
            onRemoveProject: commands.onRemoveProject,
            onSetStored: cubit.setStored,
            onToggleDrawer: cubit.toggleDrawer,
          ),
          benches: BenchActions(
            onSelect: cubit.select,
            onRename: commands.onRename,
            onDuplicateAsWorktree: commands.onDuplicateAsWorktree,
            onEditRules: commands.onEditRules,
            onRecolor: commands.onRecolor,
            onClear: commands.onClear,
            onRemove: commands.onRemove,
          ),
        );
      },
    );
  }

  void _drop(SidebarCubit cubit, DragItem item, Drop target) {
    switch ((item, target)) {
      case (DragWorkspace(:final id), DropWorkspace(:final position)):
        cubit.moveWorkspace(id, position);
      case (
        DragProject(:final id),
        DropProject(:final workspaceId, :final position, :final stored),
      ):
        cubit.moveProject(id, workspaceId, position, stored: stored);
      case (DragBench(:final id), DropBench(:final projectId, :final position)):
        cubit.moveBench(id, projectId, position);
      default:
        break;
    }
  }
}
