import '../repository/core_repository.dart';

/// Liga o canal com o core que a janela principal já subiu, sem lançar
/// nada: é o que as janelas secundárias fazem (decisão 51). Subir, relançar e
/// derrubar o core ficam só com a principal.
class JoinCore {
  const JoinCore(this._repository);

  final CoreRepository _repository;

  void call() => _repository.connect();
}
