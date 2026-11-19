import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/worktree_info.dart';
import '../../domain/entities/worktree_plan.dart';
import '../../domain/entities/worktree_source.dart';
import '../../domain/errors/workbench_error.dart';
import '../../domain/usecase/bench_creation.dart';

part 'worktree_form_state.dart';

/// Dono do formulário de worktree: pergunta o resumo ao abrir (se já não veio
/// lido) e guarda o destino e as branches de cada terminal. A branch da
/// bancada e o veredito dela são do [WorktreeBranchCubit].
class WorktreeFormCubit extends Cubit<WorktreeFormState> {
  WorktreeFormCubit({
    required this.source,
    required this._actions,
    WorktreeInfo? info,
  }) : super(
         info == null
             ? const WorktreeFormOpening()
             : WorktreeFormReady(info: info),
       ) {
    if (info == null) unawaited(_open());
  }

  final WorktreeSource source;
  final WorktreeActions _actions;

  Future<void> _open() async {
    try {
      final info = await _actions.info(source);
      if (isClosed) return;
      emit(
        WorktreeFormReady(
          info: info,
          destination: state.destination,
          edited: state.edited,
        ),
      );
    } on WorkbenchError {
      // Sem o resumo o formulário segue vazio; o gesto de criar mostra o erro.
    }
  }

  void setDestination(WorktreeDestination destination) =>
      emit(_same(destination: destination));

  void editNode(String node, String text) =>
      emit(_same(edited: {...state.edited, node: text}));

  /// A mesma fase, com a escolha nova.
  WorktreeFormState _same({
    WorktreeDestination? destination,
    Map<String, String>? edited,
  }) {
    final d = destination ?? state.destination;
    final e = edited ?? state.edited;
    return switch (state) {
      WorktreeFormOpening() => WorktreeFormOpening(destination: d, edited: e),
      WorktreeFormReady(:final info) => WorktreeFormReady(
        info: info,
        destination: d,
        edited: e,
      ),
    };
  }
}
