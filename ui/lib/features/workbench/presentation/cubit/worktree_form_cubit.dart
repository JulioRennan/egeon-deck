import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/worktree_info.dart';
import '../../domain/entities/worktree_plan.dart';
import '../../domain/errors/workbench_error.dart';
import '../../domain/usecase/bench_creation.dart';

part 'worktree_form_state.dart';

/// Dono do formulário de worktree. Pergunta o resumo ao abrir e o veredito a
/// cada mudança de branch, esperando a pessoa parar de digitar e descartando a
/// resposta de uma branch que já não é a escrita.
class WorktreeFormCubit extends Cubit<WorktreeFormState> {
  WorktreeFormCubit({
    required this.benchId,
    required this._actions,
    this.debounce = const Duration(milliseconds: 250),
  }) : super(const WorktreeFormOpening()) {
    unawaited(_open());
  }

  final String benchId;
  final WorktreeActions _actions;
  final Duration debounce;
  Timer? _timer;

  Future<void> _open() async {
    try {
      final info = await _actions.info(benchId);
      if (isClosed) return;
      emit(
        WorktreeFormReady(
          info: info,
          branch: info.suggestedBranch,
          plan: state.plan,
          destination: state.destination,
          edited: state.edited,
        ),
      );
      await _ask(info.suggestedBranch);
    } on WorkbenchError {
      // Sem o resumo o formulário segue vazio; o gesto de criar mostra o erro.
    }
  }

  void setBranch(String branch) {
    final typed = branch.trim();
    emit(state.copyWith(branch: branch, clearPlan: true));
    _timer?.cancel();
    if (typed.isEmpty) return;
    _timer = Timer(debounce, () => unawaited(_ask(typed)));
  }

  Future<void> _ask(String branch) async {
    if (branch.trim().isEmpty) return;
    try {
      final plan = await _actions.plan(benchId, branch.trim());
      if (isClosed || state.branch.trim() != branch.trim()) return;
      emit(state.copyWith(plan: plan));
    } on WorkbenchError {
      // O veredito é só aviso: sem ele, o botão continua valendo.
    }
  }

  void setDestination(WorktreeDestination destination) =>
      emit(state.copyWith(destination: destination));

  void editNode(String node, String text) =>
      emit(state.copyWith(edited: {...state.edited, node: text}));

  @override
  Future<void> close() {
    _timer?.cancel();
    return super.close();
  }
}
