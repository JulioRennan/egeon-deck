import '../entities/terminal_frame.dart';
import '../repository/terminal_repository.dart';

class WatchTerminal {
  const WatchTerminal(this._repository);

  final TerminalRepository _repository;

  Stream<TerminalFrame> call(String nodeId) => _repository.watch(nodeId);
}
