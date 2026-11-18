import 'dart:async';
import 'dart:convert';

import '../../../../../core/adapters/egeon_socket_client.dart';
import '../entities/prompt_queue.dart';
import '../entities/queue_effect.dart';
import 'queue_repository.dart';
import '../errors/queue_error.dart';

/// A fila de uma bancada falando com o core Rust. O tópico é
/// `node/<bancada>/<nó>`: o estado inteiro a cada mudança, mais os efeitos
/// `draft` e `open_item`. Um repositório por bancada: ela vai em todo comando.
class SocketQueueRepository implements QueueRepository {
  SocketQueueRepository(this._client, this.workbenchId);

  final EgeonSocketClient _client;

  /// Recusa e queda do socket viram [QueueError].
  Future<EgeonMessage> _request(String cmd, [EgeonMessage args = const {}]) =>
      _client
          .request(cmd, args)
          .failingAs(refused: QueueRefused.new, offline: QueueOffline.new);
  final String workbenchId;

  String _topic(String nodeId) => 'node/$workbenchId/$nodeId';

  Future<EgeonMessage> _send(
    String cmd,
    String nodeId, [
    EgeonMessage args = const {},
  ]) => _request(cmd, {'workbench': workbenchId, 'node': nodeId, ...args});

  @override
  Stream<PromptQueue> watch(String nodeId) => _client
      .subscribe(_topic(nodeId))
      .where((event) => event['kind'] == 'queue')
      .map(
        (event) => PromptQueue.fromMap(event['queue']! as Map<String, Object?>),
      );

  @override
  Stream<QueueEffect> effects(String nodeId) => _client
      .subscribe(_topic(nodeId))
      .map(QueueEffect.tryParse)
      .where((effect) => effect != null)
      .cast<QueueEffect>();

  /// O id da tarefa nova vem na resposta (`item`). Sem ele, vazio: o estado
  /// que o core manda a seguir mostra a tarefa de qualquer jeito.
  @override
  Future<String> add(String nodeId, {String text = '', String? after}) async {
    final reply = await _send('queue_add', nodeId, {
      'text': text,
      'after': ?after,
    });
    return reply['item'] as String? ?? '';
  }

  @override
  Future<void> update(String nodeId, String id, String text) =>
      _send('queue_update', nodeId, {'item': id, 'text': text});

  @override
  Future<void> remove(String nodeId, String id) =>
      _send('queue_remove', nodeId, {'item': id});

  @override
  Future<void> move(String nodeId, String id, {required int to}) =>
      _send('queue_move', nodeId, {'item': id, 'to': to});

  @override
  Future<void> toggleDone(String nodeId, String id) =>
      _send('queue_toggle_done', nodeId, {'item': id});

  @override
  Future<void> reopen(String nodeId, String id) =>
      _send('queue_reopen', nodeId, {'item': id});

  @override
  Future<void> send(String nodeId, {String? id}) =>
      _send('queue_send', nodeId, {'item': ?id});

  @override
  Future<void> reply(String nodeId, String id, String text) =>
      _send('queue_reply', nodeId, {'item': id, 'text': text});

  @override
  Future<void> setAuto(String nodeId, {required bool on}) =>
      _send('queue_set', nodeId, {'auto': on});

  @override
  Future<void> setTarget(String nodeId, String target) =>
      _send('queue_set', nodeId, {'target': target});

  @override
  Future<void> clearDone(String nodeId) => _send('queue_clear_done', nodeId);

  /// Arquivo vai por caminho (`path`); print colado, sem arquivo, vai em `png`
  /// (base64) e o core grava a imagem.
  @override
  Future<void> attach(
    String nodeId,
    String id,
    List<PastedImage> images,
  ) async {
    for (final image in images) {
      final path = image.path;
      await _send('queue_attach', nodeId, {
        'item': id,
        if (path != null) 'path': path else 'png': base64Encode(image.bytes),
      });
    }
  }

  /// A primeira imagem decide a tarefa (a aberta ou uma nova, na resposta); as
  /// seguintes vão para a mesma.
  @override
  Future<String> attachLoose(
    String nodeId,
    List<PastedImage> images, {
    String? open,
  }) async {
    String? item;
    for (final image in images) {
      final path = image.path;
      final reply = await _send('queue_attach', nodeId, {
        if (item == null) 'open': ?open else 'item': item,
        if (path != null) 'path': path else 'png': base64Encode(image.bytes),
      });
      item ??= reply['item'] as String?;
    }
    return item ?? '';
  }

  @override
  Future<void> detach(String nodeId, String id, String image) =>
      _send('queue_detach', nodeId, {'item': id, 'image': image});
}
