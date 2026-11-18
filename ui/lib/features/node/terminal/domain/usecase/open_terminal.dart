import '../entities/terminal_info.dart';
import '../repository/terminal_repository.dart';

/// Escolhe o terminal que a tela mostra: o que já está aberto, se ainda vive;
/// senão o primeiro vivo que o core tiver; senão cria um. Reconectar a um core
/// que reiniciou cai no último caso, porque os terminais morrem com ele.
class OpenTerminal {
  const OpenTerminal(this._repository);

  final TerminalRepository _repository;

  Future<TerminalInfo> call({String? current}) async {
    final alive = (await _repository.list()).where((t) => t.alive).toList();
    for (final t in alive) {
      if (t.id == current) return t;
    }
    if (alive.isNotEmpty) return alive.first;
    return _repository.create();
  }
}
