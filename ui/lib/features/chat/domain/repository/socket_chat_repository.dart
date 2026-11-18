import '../../../../core/adapters/egeon_socket_client.dart';
import '../entities/chat_block.dart';
import '../entities/chat_completion.dart';
import '../entities/chat_thread.dart';
import '../entities/chat_update.dart';
import 'chat_repository.dart';
import '../errors/chat_error.dart';

/// O chat falando com o core Rust pelo cliente único do socket: o tópico
/// `chat/<bancada>` traz o diff de linhas, e os gestos viram `chat_step`,
/// `chat_more` e `chat_send`.
///
/// Os nomes e as chaves são os de `commands.json` (decisão 29 do core).
class SocketChatRepository implements ChatRepository {
  const SocketChatRepository(this._client);

  final EgeonSocketClient _client;

  /// Recusa e queda do socket viram [ChatError].
  Future<EgeonMessage> _request(String cmd, [EgeonMessage args = const {}]) =>
      _client
          .request(cmd, args)
          .failingAs(refused: ChatRefused.new, offline: ChatOffline.new);

  @override
  Stream<ChatUpdate> watch(String workbenchId) =>
      _client.subscribe('chat/$workbenchId').map(ChatUpdate.fromMap);

  @override
  Future<ChatThread> snapshot(String workbenchId) async {
    final reply = await _request('chat_snapshot', {'workbench': workbenchId});
    return ChatThread(
      rev: reply['rev']! as int,
      blocks: [
        for (final b in reply['blocks']! as List<Object?>)
          ChatBlock.fromMap(b! as Map<String, Object?>),
      ],
    );
  }

  /// Passo e capa são o mesmo comando: o core sabe o que cada linha faz ao
  /// clique.
  @override
  Future<String> newQueue(String workbenchId, {String? agent}) async {
    final reply = await _request('chat_new_queue', {
      'workbench': workbenchId,
      'agent': ?agent,
    });
    return reply['node']! as String;
  }

  @override
  Future<void> toggleStep(String workbenchId, String blockId) => _client
      .request('chat_step', {'workbench': workbenchId, 'block': blockId});

  @override
  Future<void> cycleGroup(String workbenchId, String blockId) =>
      toggleStep(workbenchId, blockId);

  @override
  Future<void> loadMore(String workbenchId) =>
      _request('chat_more', {'workbench': workbenchId});

  @override
  Future<ChatCompletion> complete(
    String workbenchId,
    String text,
    int caret, {
    String? to,
    String? search,
  }) async => ChatCompletion.fromMap(
    await _request('chat_complete', {
      'workbench': workbenchId,
      'text': text,
      'caret': caret,
      'to': ?to,
      'search': ?search,
    }),
  );

  @override
  Future<void> clear(String workbenchId) =>
      _request('chat_clear', {'workbench': workbenchId});

  @override
  Future<void> answerPermission(
    String workbenchId,
    String request, {
    String? answer,
    String? choice,
    Map<String, List<String>>? answers,
  }) => _request('permission_answer', {
    'workbench': workbenchId,
    'request': request,
    'answer': ?answer,
    'choice': ?choice,
    'answers': ?answers,
  });

  @override
  Future<void> send(
    String workbenchId, {
    required List<String> to,
    required String text,
    String? quoteKey,
  }) => _request('chat_send', {
    'workbench': workbenchId,
    'to': to,
    'text': text,
    'quote': ?quoteKey,
  });
}
