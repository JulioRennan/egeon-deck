import '../entities/template_plan.dart';
import '../repository/workbench_repository.dart';

/// "Salvar este canvas como um template novo" e "Atualizar o template de
/// origem": o plano para o diálogo e a gravação. Sem nome, o de origem.
class SaveBenchTemplate {
  const SaveBenchTemplate(this._repository);

  final WorkbenchRepository _repository;

  Future<TemplatePlan> plan(String id, {String? name}) =>
      _repository.planTemplate(id, name: name);

  Future<String> call(String id, {String? name}) =>
      _repository.saveTemplate(id, name: name);
}
