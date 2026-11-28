part of 'shell_cubit.dart';

/// A casca: o que o core diz dela, com a gaveta de bancadas fechada ou aberta.
/// A gaveta só abre e fecha (sem fixar), é só da UI e passageira: ao abrir o
/// app ela começa fechada.
sealed class ShellState {
  const ShellState(this.snapshot);

  final ShellSnapshot snapshot;

  /// A gaveta está à vista.
  bool get drawerOpen => this is! ShellCollapsed;
}

/// Gaveta fechada: só o trilho de bancadas.
final class ShellCollapsed extends ShellState {
  const ShellCollapsed([super.snapshot = const ShellSnapshot()]);
}

/// Gaveta aberta por cima do conteúdo; fecha com Esc, ao clicar fora ou ao
/// escolher uma bancada.
final class ShellExpanded extends ShellState {
  const ShellExpanded(super.snapshot);
}

/// Gaveta aberta só enquanto o mouse está nela ou no botão do trilho; sair
/// fecha. Clicar no botão (ou ⌘/) a deixa aberta de vez.
final class ShellPeeking extends ShellState {
  const ShellPeeking(super.snapshot);
}
