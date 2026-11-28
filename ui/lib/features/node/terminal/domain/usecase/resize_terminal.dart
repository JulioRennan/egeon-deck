import '../repository/terminal_repository.dart';

class ResizeTerminal {
  const ResizeTerminal(this._repository);

  final TerminalRepository _repository;

  Future<void> call(String nodeId, int columns, int rows) =>
      _repository.resize(nodeId, columns, rows);
}
