import '../repository/sidebar_repository.dart';

/// Pergunta ao core onde o item arrastado cairia. É o core que decide se o
/// lugar vale; a tela só aponta com o ponteiro.
class PlanMove {
  const PlanMove(this._repository);

  final SidebarRepository _repository;

  Future<MoveLanding?> call(
    String kind,
    String item, {
    String? parent,
    required int to,
  }) => _repository.planMove(kind, item, parent: parent, to: to);
}
