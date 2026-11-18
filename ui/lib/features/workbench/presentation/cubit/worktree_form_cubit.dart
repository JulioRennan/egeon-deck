import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/worktree_info.dart';
import '../../domain/entities/worktree_plan.dart';
import '../../domain/usecase/bench_creation.dart';

/// O formulário de worktree: o que o core respondeu e o que a pessoa escolheu.
class WorktreeFormState {
  const WorktreeFormState({
    this.info,
    this.branch = '',
    this.plan,
    this.destination = WorktreeDestination.newWorkbench,
    this.edited = const {},
  });

  /// Nulo até o core responder ao abrir.
  final WorktreeInfo? info;
  final String branch;

  /// O veredito para [branch]; nulo enquanto pergunta ou sem branch.
  final WorktreePlan? plan;
  final WorktreeDestination destination;

  /// A branch que a pessoa escreveu à mão para um terminal. Sem entrada, a
  /// linha acompanha a da bancada.
  final Map<String, String> edited;

  WorktreeFormState copyWith({
    WorktreeInfo? info,
    String? branch,
    WorktreePlan? plan,
    bool clearPlan = false,
    WorktreeDestination? destination,
    Map<String, String>? edited,
  }) => WorktreeFormState(
    info: info ?? this.info,
    branch: branch ?? this.branch,
    plan: clearPlan ? null : plan ?? this.plan,
    destination: destination ?? this.destination,
    edited: edited ?? this.edited,
  );

  /// O que a linha do terminal mostra: o que foi escrito, ou a branch dele.
  String rowText(NodeWorktree node) => edited[node.node] ?? node.branch ?? '';

  /// O mapa que vai ao `worktree`: só terminais em repositório, com a branch
  /// que difere da da bancada.
  Map<String, String> get nodes => {
    for (final node in info?.nodes ?? const <NodeWorktree>[])
      if (node.editable && rowText(node).trim().isNotEmpty)
        node.node: rowText(node).trim(),
  };
}

/// Dono do formulário de worktree. Pergunta o resumo ao abrir e o veredito a
/// cada mudança de branch, esperando a pessoa parar de digitar e descartando a
/// resposta de uma branch que já não é a escrita.
class WorktreeFormCubit extends Cubit<WorktreeFormState> {
  WorktreeFormCubit({
    required this.benchId,
    required this._actions,
    this.debounce = const Duration(milliseconds: 250),
  }) : super(const WorktreeFormState()) {
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
      emit(state.copyWith(info: info, branch: info.suggestedBranch));
      await _ask(info.suggestedBranch);
    } on Object {
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
    } on Object {
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
