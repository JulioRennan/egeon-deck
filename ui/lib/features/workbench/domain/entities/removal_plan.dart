/// O que remover uma bancada leva junto, para a confirmação dizer.
class RemovalPlan {
  const RemovalPlan({this.live = false, this.worktrees = 0});

  /// Há terminais abertos, que serão encerrados.
  final bool live;

  /// Quantas worktrees só esta bancada usa e podem sair do disco junto.
  final int worktrees;

  factory RemovalPlan.fromMap(Map<String, Object?> map) => RemovalPlan(
    live: map['live'] as bool? ?? false,
    worktrees: map['worktrees'] as int? ?? 0,
  );

  Map<String, Object?> toMap() => {'live': live, 'worktrees': worktrees};
}
