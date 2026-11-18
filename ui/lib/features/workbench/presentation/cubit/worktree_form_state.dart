part of 'worktree_form_cubit.dart';

/// O formulário de worktree: esperando o resumo do core, ou com ele. O que a
/// pessoa escolhe (branch, destino, branches por terminal) vale nas duas fases
/// — dá para digitar antes de o resumo chegar.
sealed class WorktreeFormState {
  const WorktreeFormState({
    this.branch = '',
    this.plan,
    this.destination = WorktreeDestination.newWorkbench,
    this.edited = const {},
  });

  final String branch;

  /// O veredito para [branch]; nulo enquanto pergunta ou sem branch.
  final WorktreePlan? plan;
  final WorktreeDestination destination;

  /// A branch que a pessoa escreveu à mão para um terminal. Sem entrada, a
  /// linha acompanha a da bancada.
  final Map<String, String> edited;

  WorktreeFormState copyWith({
    String? branch,
    WorktreePlan? plan,
    bool clearPlan = false,
    WorktreeDestination? destination,
    Map<String, String>? edited,
  });

  /// O que a linha do terminal mostra: o que foi escrito, ou a branch dele.
  String rowText(NodeWorktree node) => edited[node.node] ?? node.branch ?? '';

  /// O mapa que vai ao `worktree`: só terminais em repositório, com a branch
  /// que difere da da bancada. Sem o resumo, nenhum.
  Map<String, String> get nodes => switch (this) {
    WorktreeFormOpening() => const {},
    WorktreeFormReady(:final info) => {
      for (final node in info.nodes)
        if (node.editable && rowText(node).trim().isNotEmpty)
          node.node: rowText(node).trim(),
    },
  };
}

/// O core ainda não mandou o resumo do repositório.
final class WorktreeFormOpening extends WorktreeFormState {
  const WorktreeFormOpening({
    super.branch,
    super.plan,
    super.destination,
    super.edited,
  });

  @override
  WorktreeFormOpening copyWith({
    String? branch,
    WorktreePlan? plan,
    bool clearPlan = false,
    WorktreeDestination? destination,
    Map<String, String>? edited,
  }) => WorktreeFormOpening(
    branch: branch ?? this.branch,
    plan: clearPlan ? null : plan ?? this.plan,
    destination: destination ?? this.destination,
    edited: edited ?? this.edited,
  );
}

/// O resumo chegou: os terminais e a branch sugerida.
final class WorktreeFormReady extends WorktreeFormState {
  const WorktreeFormReady({
    required this.info,
    super.branch,
    super.plan,
    super.destination,
    super.edited,
  });

  final WorktreeInfo info;

  @override
  WorktreeFormReady copyWith({
    String? branch,
    WorktreePlan? plan,
    bool clearPlan = false,
    WorktreeDestination? destination,
    Map<String, String>? edited,
  }) => WorktreeFormReady(
    info: info,
    branch: branch ?? this.branch,
    plan: clearPlan ? null : plan ?? this.plan,
    destination: destination ?? this.destination,
    edited: edited ?? this.edited,
  );
}
