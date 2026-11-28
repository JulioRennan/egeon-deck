import '../entities/terminal_effect.dart';
import '../repository/terminal_repository.dart';

class WatchTerminalEffects {
  const WatchTerminalEffects(this._repository);

  final TerminalRepository _repository;

  Stream<TerminalEffect> call(String nodeId) => _repository.effects(nodeId);
}
