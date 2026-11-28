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
  const NodeWorktree({
    required this.node,
    required this.state,
    this.branch,
    this.repo,
    this.path = '',
    this.exists = true,
    this.inside = false,
  });

  factory NodeWorktree.fromMap(Map<String, Object?> map) => NodeWorktree(
    node: map['node']! as String,
    branch: map['branch'] as String?,
    state: NodeWorktreeState.parse(map['state']),
    repo: map['repo'] as String?,
    path: map['path'] as String? ?? '',
    exists: map['exists'] as bool? ?? true,
    inside: map['inside'] as bool? ?? false,
  );

  final String node;

  /// A branch própria dele, quando há.
  final String? branch;
  final NodeWorktreeState state;

  /// O repositório em que abre; nulo, não é git.
  final String? repo;

  /// Onde abre hoje, com `~`.
  final String path;
  final bool exists;

  /// Dentro da pasta da bancada: na mesma branch, vai junto com ela.
  final bool inside;

  /// Só terminal dentro de repositório aceita uma branch diferente.
  bool get editable => state != NodeWorktreeState.noRepo;

  /// A branch [text] desta linha, contra a da bancada: em branco não leva;
  /// igual e dentro da bancada vai junto; o resto ganha worktree própria
  /// (`NodeWorktree.decided` do Swift).
  NodeWorktreeChoice choice(String text, String workbenchBranch) {
    final branch = text.trim();
    if (!editable) return NodeWorktreeChoice.stays;
    if (branch.isEmpty) return NodeWorktreeChoice.leftBehind;
    if (inside && branch == workbenchBranch.trim()) {
      return NodeWorktreeChoice.follows;
    }
    return NodeWorktreeChoice.own;
  }

  /// A linha miúda embaixo do nome (`NodeWorktreeRow.describePlan`).
  String detail(NodeWorktreeChoice choice) => switch (choice) {
    NodeWorktreeChoice.stays =>
      exists
          ? '$path · não é repositório git'
          : '$path · esta pasta não existe',
    NodeWorktreeChoice.leftBehind => '$repo · fica no repositório original',
    NodeWorktreeChoice.follows => '$repo · vai junto com a bancada',
    NodeWorktreeChoice.own => '$repo · worktree própria',
  };
}

/// O que acontece com um terminal na worktree nova.
enum NodeWorktreeChoice {
  /// Fora do git: fica onde está, sem escolha.
  stays,

  /// Em branco: não vai, fica no repositório original.
  leftBehind,

  /// Mesma branch, dentro da bancada: vai junto.
  follows,

  /// Worktree própria no repositório dele.
  own;

  /// Pede um olhar: o terminal não acompanha a bancada nem tem pasta.
  bool get warns => this == leftBehind;
}

/// O formulário de multi-projeto (`MultiWorktreeForm`): o nome do conjunto e
/// um campo por repositório, com o nome do link dele.
class MultiWorktree {
  const MultiWorktree({required this.project, this.repos = const []});

  factory MultiWorktree.fromMap(Map<String, Object?> map) => MultiWorktree(
    project: map['project'] as String? ?? '',
    repos: [
      for (final repo in map['repos'] as List<Object?>? ?? const [])
        repo! as String,
    ],
  );

  final String project;
  final List<String> repos;
}

/// O que o formulário de worktree mostra ao abrir: o resumo do repositório, a
/// branch sugerida e uma linha por terminal. Em multi-projeto só [multi] vale.
class WorktreeInfo {
  const WorktreeInfo({
    required this.summary,
    required this.suggestedBranch,
    this.nodes = const [],
    this.repo = '',
    this.multi,
  });

  factory WorktreeInfo.fromMap(Map<String, Object?> map) => WorktreeInfo(
    summary: map['summary'] as String? ?? '',
    suggestedBranch: map['suggested_branch'] as String? ?? '',
    nodes: [
      for (final raw in map['nodes'] as List<Object?>? ?? const [])
        NodeWorktree.fromMap(raw! as Map<String, Object?>),
    ],
    repo: map['repo'] as String? ?? '',
    multi: map['multi'] == null
        ? null
        : MultiWorktree.fromMap(map['multi']! as Map<String, Object?>),
  );

  final String summary;
  final String suggestedBranch;
  final List<NodeWorktree> nodes;

  /// O nome do repositório, para o título.
  final String repo;
  final MultiWorktree? multi;
}
