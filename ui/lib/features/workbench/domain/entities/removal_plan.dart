/// Uma worktree que a bancada usa, como o core a levanta para a remoção.
class RemovalWorktree {
  const RemovalWorktree({
    required this.path,
    required this.repo,
    this.branch,
    this.owners = const [],
    this.usedBy,
  });

  factory RemovalWorktree.fromMap(Map<String, Object?> map) => RemovalWorktree(
    path: map['path'] as String? ?? '',
    repo: map['repo'] as String? ?? '',
    branch: map['branch'] as String?,
    owners: [
      for (final owner in map['owners'] as List<Object?>? ?? const [])
        owner! as String,
    ],
    usedBy: map['used_by'] as String?,
  );

  final String path;
  final String repo;
  final String? branch;

  /// Os terminais (ou a bancada) que abrem nela.
  final List<String> owners;

  /// Outra bancada mora nesta pasta: ela fica.
  final String? usedBy;

  /// Só a worktree que nenhuma outra bancada usa pode sair do disco.
  bool get deletable => usedBy == null;

  Map<String, Object?> toMap() => {
    'path': path,
    'repo': repo,
    'branch': branch,
    'owners': owners,
    'used_by': usedBy,
  };
}

/// O que remover uma bancada leva junto, para a confirmação dizer. O que se
/// perde vem depois, só com a caixa de apagar marcada (`removal_losses`).
class RemovalPlan {
  const RemovalPlan({this.live = false, this.worktrees = const []});

  factory RemovalPlan.fromMap(Map<String, Object?> map) => RemovalPlan(
    live: map['live'] as bool? ?? false,
    worktrees: [
      for (final raw in map['worktrees'] as List<Object?>? ?? const [])
        RemovalWorktree.fromMap(raw! as Map<String, Object?>),
    ],
  );

  /// Há terminais abertos, que serão encerrados.
  final bool live;

  /// Todas as worktrees que a bancada usa, inclusive as de outras bancadas.
  final List<RemovalWorktree> worktrees;

  List<RemovalWorktree> get deletable => [
    for (final worktree in worktrees)
      if (worktree.deletable) worktree,
  ];

  Map<String, Object?> toMap() => {
    'live': live,
    'worktrees': [for (final w in worktrees) w.toMap()],
  };
}
