import '../repository/workbench_repository.dart';

/// Limpar a bancada: pergunta quantos agentes serão atingidos e, confirmado,
/// manda limpar.
class ClearWorkbench {
  const ClearWorkbench(this._repository);

  final WorkbenchRepository _repository;

  Future<int> agents(String id) => _repository.agentCount(id);

  Future<void> call(String id) => _repository.clear(id);
}
