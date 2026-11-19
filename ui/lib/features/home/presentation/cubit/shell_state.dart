part of 'shell_cubit.dart';

/// A casca: o que o core diz dela, com a barra lateral aberta ou recolhida
/// ao trilho (⌘/) — esta só da UI, é passageira.
sealed class ShellState {
  const ShellState(this.snapshot);

  final ShellSnapshot snapshot;
}

final class ShellExpanded extends ShellState {
  const ShellExpanded([super.snapshot = const ShellSnapshot()]);
}

final class ShellCollapsed extends ShellState {
  const ShellCollapsed(super.snapshot);
}
