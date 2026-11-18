/// O que vai acontecer com o nome de branch escrito (ADR-018), sem criar nada.
/// Quem decide é o core; a UI mostra.
enum WorktreeVerdict {
  create('create'),
  openExisting('open_existing'),
  followRemote('follow_remote'),
  alreadyOpen('already_open'),

  /// Um veredito que a UI não conhece: o texto do core basta.
  other('');

  const WorktreeVerdict(this.wire);

  final String wire;

  static WorktreeVerdict parse(Object? raw) => values.firstWhere(
    (verdict) => verdict.wire.isNotEmpty && verdict.wire == raw,
    orElse: () => WorktreeVerdict.other,
  );
}

class WorktreePlan {
  const WorktreePlan({
    required this.verdict,
    required this.folder,
    this.message,
  });

  factory WorktreePlan.fromMap(Map<String, Object?> map) => WorktreePlan(
    verdict: WorktreeVerdict.parse(map['verdict']),
    folder: map['folder'] as String? ?? '',
    message: map['message'] as String?,
  );

  final WorktreeVerdict verdict;

  /// Onde a worktree nasce (ou já está), para conferir e não para editar.
  final String folder;
  final String? message;

  /// Só criar do zero é o caminho neutro; o resto pede um olhar.
  bool get isFresh => verdict == WorktreeVerdict.create;
}

/// Para onde vai a worktree: uma bancada nova, ou a atual muda de pasta (e os
/// terminais reiniciam).
enum WorktreeDestination {
  newWorkbench('new_workbench'),
  moveCurrent('move_current');

  const WorktreeDestination(this.wire);

  final String wire;
}
