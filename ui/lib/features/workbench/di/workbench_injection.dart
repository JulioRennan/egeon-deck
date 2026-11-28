import '../../../core/adapters/injector.dart';
import '../domain/repository/socket_workbench_repository.dart';
import '../domain/repository/workbench_repository.dart';
import '../domain/usecase/bench_creation.dart';
import '../domain/usecase/change_bench_color.dart';
import '../domain/usecase/clear_workbench.dart';
import '../domain/usecase/reset_clock.dart';
import '../domain/usecase/edit_workbench_rules.dart';
import '../domain/usecase/remove_workbench.dart';
import '../domain/usecase/rename_workbench.dart';
import '../domain/usecase/save_bench_template.dart';
import '../domain/entities/worktree_info.dart';
import '../domain/entities/worktree_source.dart';
import '../presentation/cubit/multi_worktree_form_cubit.dart';
import '../presentation/cubit/worktree_branch_cubit.dart';
import '../presentation/cubit/worktree_form_cubit.dart';

void registerWorkbenchRepositories() {
  Injector.factory<WorkbenchRepository>(
    () => SocketWorkbenchRepository(inject()),
  );
}

void registerWorkbenchDomain() {
  Injector.factory(() => ListTemplates(inject()));
  Injector.factory(() => CreateWorkbench(inject()));
  Injector.factory(() => WorktreeActions(inject()));
  Injector.factory(() => ChangeBenchColor(inject()));
  Injector.factory(() => RenameWorkbench(inject()));
  Injector.factory(() => ClearWorkbench(inject()));
  Injector.factory(() => ResetClock(inject()));
  Injector.factory(() => RemoveWorkbench(inject()));
  Injector.factory(() => EditWorkbenchRules(inject()));
  Injector.factory(() => SaveBenchTemplate(inject()));
  Injector.factoryParam<
    WorktreeFormCubit,
    ({WorktreeSource source, WorktreeInfo? info})
  >(
    (args) => WorktreeFormCubit(
      source: args.source,
      info: args.info,
      actions: inject(),
    ),
  );
  Injector.factoryParam<
    WorktreeBranchCubit,
    ({WorktreeSource source, String? suggested})
  >(
    (args) => WorktreeBranchCubit(
      source: args.source,
      suggested: args.suggested,
      actions: inject(),
    ),
  );
  Injector.factoryParam<MultiWorktreeFormCubit, List<String>>(
    (repos) => MultiWorktreeFormCubit(repos: repos),
  );
}
