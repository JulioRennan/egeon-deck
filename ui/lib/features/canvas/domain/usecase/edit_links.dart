import '../entities/edge_link.dart';
import '../repository/canvas_repository.dart';

/// Os gestos sobre as ligações: criar, remover, trocar a direção e o limite.
class EditLinks {
  const EditLinks(this._repository);
  final CanvasRepository _repository;

  Future<void> create(String workbenchId, String from, String to) =>
      _repository.createLink(workbenchId, from, to);

  Future<void> remove(String workbenchId, EdgeLink link) =>
      _repository.removeLink(workbenchId, link);

  Future<void> cycleDirection(String workbenchId, EdgeLink link) =>
      _repository.cycleLink(workbenchId, link);

  Future<void> setLimit(String workbenchId, EdgeLink link, int? maxSends) =>
      _repository.setLinkLimit(workbenchId, link, maxSends);
}
