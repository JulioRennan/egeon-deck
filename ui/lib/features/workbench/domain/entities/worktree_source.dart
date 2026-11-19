/// De onde a worktree parte: a bancada que se duplica ou, sem bancada de
/// origem, a pasta escolhida ou o projeto da barra lateral. O core resolve o
/// repositório (e se é multi-projeto).
class WorktreeSource {
  const WorktreeSource.bench(String this.benchId)
    : path = null,
      project = null,
      nodeId = null;

  const WorktreeSource.folder({this.path, this.project})
    : benchId = null,
      nodeId = null;

  /// Um terminal só da bancada (o `NodeWorktreePlanner` do Swift): o
  /// repositório é o da pasta em que ele abre, e só ele é reapontado.
  const WorktreeSource.node(String this.benchId, String this.nodeId)
    : path = null,
      project = null;

  final String? benchId;
  final String? path;
  final String? project;
  final String? nodeId;

  /// Sem bancada de origem, a bancada nova escolhe template e não há o que
  /// mover.
  bool get hasOrigin => benchId != null;

  Map<String, Object?> toMap() => {
    'workbench': ?benchId,
    'path': ?path,
    'project': ?project,
    'node': ?nodeId,
  };
}

/// A resposta de criar: a bancada que tem a worktree e, em multi-projeto, os
/// repositórios que recusaram (com o motivo de cada um).
class WorktreeCreated {
  const WorktreeCreated({required this.workbench, this.failed = const []});

  factory WorktreeCreated.fromMap(Map<String, Object?> map) => WorktreeCreated(
    workbench: map['workbench'] as String? ?? '',
    failed: [
      for (final line in map['failed'] as List<Object?>? ?? const [])
        line! as String,
    ],
  );

  final String workbench;
  final List<String> failed;
}
