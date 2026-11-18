/// Como um terminal da bancada se comporta numa worktree nova. Os nomes são os
/// do core; um estado que a UI não conhece cai em [other] e a linha mostra o
/// texto dele sem interpretar.
enum NodeWorktreeState {
  /// Já tem worktree própria, com a branch dele.
  ownWorktree('own_worktree'),

  /// Acompanha a branch da bancada.
  followsWorkbench('follows_workbench'),

  /// A pasta dele não é repositório: fica onde está.
  noRepo('no_repo'),
  other('');

  const NodeWorktreeState(this.wire);

  final String wire;

  static NodeWorktreeState parse(Object? raw) => values.firstWhere(
    (state) => state.wire.isNotEmpty && state.wire == raw,
    orElse: () => NodeWorktreeState.other,
  );
}

class NodeWorktree {
  const NodeWorktree({required this.node, required this.state, this.branch});

  factory NodeWorktree.fromMap(Map<String, Object?> map) => NodeWorktree(
    node: map['node']! as String,
    branch: map['branch'] as String?,
    state: NodeWorktreeState.parse(map['state']),
  );

  final String node;

  /// A branch própria dele, quando há.
  final String? branch;
  final NodeWorktreeState state;

  /// Só terminal dentro de repositório aceita uma branch diferente.
  bool get editable => state != NodeWorktreeState.noRepo;
}

/// O que o formulário de worktree mostra ao abrir: o resumo do repositório, a
/// branch sugerida e uma linha por terminal.
class WorktreeInfo {
  const WorktreeInfo({
    required this.summary,
    required this.suggestedBranch,
    this.nodes = const [],
  });

  factory WorktreeInfo.fromMap(Map<String, Object?> map) => WorktreeInfo(
    summary: map['summary'] as String? ?? '',
    suggestedBranch: map['suggested_branch'] as String? ?? '',
    nodes: [
      for (final raw in map['nodes'] as List<Object?>? ?? const [])
        NodeWorktree.fromMap(raw! as Map<String, Object?>),
    ],
  );

  final String summary;
  final String suggestedBranch;
  final List<NodeWorktree> nodes;
}
