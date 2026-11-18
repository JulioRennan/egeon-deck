import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubit/sidebar_cubit.dart';
import '../cubit/sidebar_state.dart';
import '../widgets/bench_actions.dart';
import '../widgets/group_actions.dart';
import '../widgets/sidebar_drop.dart';
import '../widgets/sidebar_panel.dart';

/// A barra lateral. Escolher, recolher e guardar vão ao core; o que abre
/// formulário volta para a casca por [commands].
class SidebarPage extends StatelessWidget {
  const SidebarPage({
    required this.cubit,
    required this.commands,
    this.compact = false,
    super.key,
  });

  /// Criado e fechado por quem monta a casca.
  final SidebarCubit cubit;
  final SidebarCommands commands;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: cubit,
      child: BlocBuilder<SidebarCubit, SidebarState>(
        builder: (context, state) {
          final cubit = context.read<SidebarCubit>();
          return SidebarPanel(
            tree: state.tree,
            tab: state.tab,
            onTab: cubit.showTab,
            compact: compact,
            commands: commands,
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
      ),
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
