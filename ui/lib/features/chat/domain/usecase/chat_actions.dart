import '../entities/chat_completion.dart';
import '../repository/chat_repository.dart';

/// Os gestos do chat: abrir passo, aprofundar capa, carregar histórico e
/// mandar a mensagem do composer.
class ChatActions {
  const ChatActions(this._repository);

  final ChatRepository _repository;

  Future<void> toggleStep(String workbenchId, String blockId) =>
      _repository.toggleStep(workbenchId, blockId);

  Future<void> cycleGroup(String workbenchId, String blockId) =>
      _repository.cycleGroup(workbenchId, blockId);

  Future<void> loadMore(String workbenchId) =>
      _repository.loadMore(workbenchId);

  Future<void> answerPermission(
    String workbenchId,
    String request, {
    String? answer,
    String? choice,
    Map<String, List<String>>? answers,
  }) => _repository.answerPermission(
    workbenchId,
    request,
    answer: answer,
    choice: choice,
    answers: answers,
  );

  Future<ChatCompletion> complete(
    String workbenchId,
    String text,
    int caret, {
    String? to,
    String? search,
  }) => _repository.complete(workbenchId, text, caret, to: to, search: search);

  Future<void> clear(String workbenchId) => _repository.clear(workbenchId);

  Future<String> newQueue(String workbenchId, {String? agent}) =>
      _repository.newQueue(workbenchId, agent: agent);

  Future<void> send(
    String workbenchId, {
    required List<String> to,
    required String text,
    String? quoteKey,
  }) => _repository.send(workbenchId, to: to, text: text, quoteKey: quoteKey);
}
