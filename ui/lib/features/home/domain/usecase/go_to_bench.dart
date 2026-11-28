import '../repository/shell_repository.dart';

/// Põe uma bancada na tela: o voltar e o avançar da faixa de cima.
class GoToBench {
  const GoToBench(this._repository);

  final ShellRepository _repository;

  Future<void> call(String benchId) => _repository.activate(benchId);
}
