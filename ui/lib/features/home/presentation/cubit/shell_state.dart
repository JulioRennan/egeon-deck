part of 'shell_cubit.dart';

/// O que a casca guarda: o que o core mandou e se a barra está recolhida —
/// esta só da UI, é passageira.
final class ShellState {
  const ShellState({
    this.snapshot = const ShellSnapshot(),
    this.collapsed = false,
  });

  final ShellSnapshot snapshot;

  /// A barra lateral recolhida ao trilho (⌘/).
  final bool collapsed;

  ShellState copyWith({ShellSnapshot? snapshot, bool? collapsed}) => ShellState(
    snapshot: snapshot ?? this.snapshot,
    collapsed: collapsed ?? this.collapsed,
  );
}
