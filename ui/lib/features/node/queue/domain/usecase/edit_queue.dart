import '../repository/queue_repository.dart';

/// Os gestos sobre a fila de um nó: anotar, editar, mandar, reordenar.
class EditQueue {
  const EditQueue(this._repository);
  final QueueRepository _repository;

  Future<String> add(String nodeId, {String text = '', String? after}) =>
      _repository.add(nodeId, text: text, after: after);
  Future<void> update(String nodeId, String id, String text) =>
      _repository.update(nodeId, id, text);
  Future<void> remove(String nodeId, String id) =>
      _repository.remove(nodeId, id);
  Future<void> move(String nodeId, String id, {required int to}) =>
      _repository.move(nodeId, id, to: to);
  Future<void> toggleDone(String nodeId, String id) =>
      _repository.toggleDone(nodeId, id);
  Future<void> reopen(String nodeId, String id) =>
      _repository.reopen(nodeId, id);
  Future<String?> send(String nodeId, {String? id}) =>
      _repository.send(nodeId, id: id);
  Future<String?> reply(String nodeId, String id, String text) =>
      _repository.reply(nodeId, id, text);
  Future<void> setAuto(String nodeId, {required bool on}) =>
      _repository.setAuto(nodeId, on: on);
  Future<void> setTarget(String nodeId, String target) =>
      _repository.setTarget(nodeId, target);
  Future<void> clearDone(String nodeId) => _repository.clearDone(nodeId);
  Future<void> attach(String nodeId, String id, List<PastedImage> images) =>
      _repository.attach(nodeId, id, images);
  Future<String> attachLoose(
    String nodeId,
    List<PastedImage> images, {
    String? open,
  }) => _repository.attachLoose(nodeId, images, open: open);
  Future<void> detach(String nodeId, String id, String image) =>
      _repository.detach(nodeId, id, image);
}
