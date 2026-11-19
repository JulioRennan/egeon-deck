part of 'worktree_form_cubit.dart';

/// O formulário de worktree: esperando o resumo do core, ou com ele. O destino
/// e as branches escritas à mão para cada terminal valem nas duas fases — dá
/// para escolher antes de o resumo chegar.
sealed class WorktreeFormState {
  const WorktreeFormState({
    this.destination = WorktreeDestination.newWorkbench,
    this.edited = const {},
  });

  final WorktreeDestination destination;

  /// A branch que a pessoa escreveu à mão para um terminal. Sem entrada, a
  /// linha acompanha a da bancada.
  final Map<String, String> edited;

  /// O que a linha do terminal mostra: o que foi escrito (mesmo vazio, que é
  /// "não levar"), ou a [branch] da bancada — a linha que ninguém tocou
  /// acompanha a bancada (`NodeWorktreeRow.suggest`).
  String rowText(NodeWorktree node, String branch) =>
      edited[node.node] ?? branch;

  /// O mapa que vai ao `worktree`: a branch de quem diverge da [branch] da
  /// bancada, e vazio para quem não vai. Quem acompanha fica de fora: o core
  /// decide igual. Sem o resumo, nenhum.
  Map<String, String> nodes(String branch) => switch (this) {
    WorktreeFormOpening() => const {},
    WorktreeFormReady(:final info) => {
      for (final node in info.nodes)
        if (node.editable && rowText(node, branch).trim() != branch.trim())
          node.node: rowText(node, branch).trim(),
    },
  };
}

/// O core ainda não mandou o resumo do repositório.
final class WorktreeFormOpening extends WorktreeFormState {
  const WorktreeFormOpening({super.destination, super.edited});
}

/// O resumo chegou: os terminais e a branch sugerida.
final class WorktreeFormReady extends WorktreeFormState {
  const WorktreeFormReady({
    required this.info,
    super.destination,
    super.edited,
  });

  final WorktreeInfo info;
}
