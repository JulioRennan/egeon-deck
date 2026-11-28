import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/worktree_plan.dart';
import '../../domain/entities/worktree_source.dart';
import '../../domain/errors/workbench_error.dart';
import '../../domain/usecase/bench_creation.dart';

part 'worktree_branch_state.dart';

/// A branch do formulário de worktree. Pergunta o veredito a cada mudança,
/// esperando a pessoa parar de digitar e descartando a resposta de uma branch
/// que já não é a escrita.
class WorktreeBranchCubit extends Cubit<WorktreeBranchState> {
  WorktreeBranchCubit({
    required this.source,
    required this._actions,
    String? suggested,
    this.debounce = const Duration(milliseconds: 250),
  }) : super(const BranchEmpty()) {
    if (suggested != null) suggest(suggested);
  }

  final WorktreeSource source;
  final WorktreeActions _actions;
  final Duration debounce;
  Timer? _timer;

  /// A branch escrita agora, sem espaço nas pontas.
  String get branch => switch (state) {
    BranchEmpty() => '',
    BranchAsking(:final branch) || BranchJudged(:final branch) => branch,
  };

  /// A branch que o core sugere: pergunta já, sem esperar digitação.
  void suggest(String branch) {
    _timer?.cancel();
    final typed = branch.trim();
    if (typed.isEmpty) return emit(const BranchEmpty());
    emit(BranchAsking(typed));
    unawaited(_ask(typed));
  }

  void setBranch(String text) {
    _timer?.cancel();
    final typed = text.trim();
    if (typed.isEmpty) return emit(const BranchEmpty());
    emit(BranchAsking(typed));
    _timer = Timer(debounce, () => unawaited(_ask(typed)));
  }

  Future<void> _ask(String branch) async {
    try {
      final plan = await _actions.plan(source, branch);
      if (isClosed || this.branch != branch) return;
      emit(BranchJudged(branch, plan));
    } on WorkbenchError {
      // O veredito é só aviso: sem ele, o botão continua valendo.
    }
  }

  @override
  Future<void> close() {
    _timer?.cancel();
    return super.close();
  }
}
