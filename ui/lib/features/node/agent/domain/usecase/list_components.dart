import '../repository/node_form_repository.dart';

/// Os nomes dos componentes salvos, na ordem do core: o menu de segurar o
/// botão Terminal.
class ListComponents {
  const ListComponents(this._repository);

  final NodeFormRepository _repository;

  Future<List<String>> call() async => [
    for (final component in await _repository.components()) component.name,
  ];
}
