import 'dart:async';

import 'package:egeon_deck/features/node/queue/domain/entities/prompt_queue.dart';
import 'package:egeon_deck/features/node/queue/domain/entities/queue_effect.dart';
import 'package:egeon_deck/features/node/queue/domain/entities/queue_item.dart';
import 'package:egeon_deck/features/node/queue/domain/errors/queue_error.dart';
import 'package:egeon_deck/features/node/queue/domain/repository/queue_repository.dart';

/// Fila em memória, com dados falsos e as regras que o core vai ter (mandar
/// exige ligação; mandar por cima de uma em andamento a fecha), até o contrato.
class InMemoryQueueRepository implements QueueRepository {
  InMemoryQueueRepository({PromptQueue? queue})
    : _queue = _derive(queue ?? const PromptQueue());

  PromptQueue _queue;
  final _changes = StreamController<void>.broadcast();
  var _serial = 0;
  final attached = <String, List<PastedImage>>{};

  PromptQueue get queue => _queue;

  void _set(PromptQueue queue) {
    _queue = queue;
    _changes.add(null);
  }

  PromptQueue _copy({List<QueueItem>? items, bool? auto, String? target}) =>
      _derive(
        PromptQueue(
          items: items ?? _queue.items,
          auto: auto ?? _queue.auto,
          target: target ?? _queue.target,
          targets: _queue.targets,
          blocker: _queue.blocker,
        ),
      );

  /// O que o core escreve no estado e a UI só lê: destino, contagem, resumo e,
  /// por tarefa, `locked` e `empty`.
  static PromptQueue _derive(PromptQueue q) {
    final items = [for (final i in q.items) _normalized(i)];
    final linked = q.targets.map((t) => t.id);
    final destination = q.target != null && linked.contains(q.target)
        ? q.target
        : linked.firstOrNull;
    final pending = items
        .where((i) => i.status == ItemStatus.pending && !i.empty)
        .length;
    final asking = items.any((i) => i.awaiting);
    final with_ = items
        .where((i) => i.status == ItemStatus.sent)
        .firstOrNull
        ?.sentTo;
    final count = pending == 1 ? '1 pendente' : '$pending pendentes';
    final summary = asking
        ? '? pergunta'
        : with_ != null
        ? (pending == 0 ? 'com $with_' : '$count · com $with_')
        : (pending == 0 ? 'nada pendente' : count);
    return PromptQueue(
      items: items,
      auto: q.auto,
      target: q.target,
      targets: q.targets,
      blocker: q.blocker,
      destination: destination,
      pending: pending,
      asking: asking,
      summary: summary,
      subtitle: pending == 0 ? 'nada pendente' : count,
      imageExtensions: const [
        'png', 'jpg', 'jpeg', 'gif', 'webp', 'heic', 'tiff', 'bmp', //
      ],
    );
  }

  static QueueItem _normalized(QueueItem i) => QueueItem(
    id: i.id,
    text: i.text,
    images: i.images,
    status: i.status,
    sentTo: i.sentTo,
    sentAt: i.sentAt,
    thread: i.thread,
    awaiting: i.awaiting,
    locked: i.sentAt != null,
    empty: i.text.trim().isEmpty && i.images.isEmpty,
  );

  final effectsController = StreamController<QueueEffect>.broadcast();

  @override
  Stream<QueueEffect> effects(String nodeId) => effectsController.stream;

  @override
  Stream<PromptQueue> watch(String nodeId) {
    late final StreamController<PromptQueue> controller;
    StreamSubscription<void>? changes;
    controller = StreamController<PromptQueue>(
      onListen: () {
        controller.add(_queue);
        changes = _changes.stream.listen((_) => controller.add(_queue));
      },
      onCancel: () => changes?.cancel(),
    );
    return controller.stream;
  }

  QueueItem _item(String id) => _queue.items.firstWhere((i) => i.id == id);

  void _replace(QueueItem item) => _set(
    _copy(items: [for (final i in _queue.items) i.id == item.id ? item : i]),
  );

  QueueItem _with(
    QueueItem i, {
    String? text,
    List<String>? images,
    ItemStatus? status,
    DateTime? sentAt,
    String? sentTo,
    List<QueueMessage>? thread,
    bool? awaiting,
  }) => QueueItem(
    id: i.id,
    text: text ?? i.text,
    images: images ?? i.images,
    status: status ?? i.status,
    sentTo: sentTo ?? i.sentTo,
    sentAt: sentAt ?? i.sentAt,
    thread: thread ?? i.thread,
    awaiting: awaiting ?? i.awaiting,
  );

  @override
  Future<String> add(String nodeId, {String text = '', String? after}) async {
    final id = 'q${(++_serial).toString().padLeft(5, '0')}ab';
    final item = QueueItem(id: id, text: text);
    final items = [..._queue.items];
    final at = after == null ? null : _queue.indexOf(after);
    items.insert(at == null ? items.length : at + 1, item);
    _set(_copy(items: items));
    return id;
  }

  @override
  Future<void> update(String nodeId, String id, String text) async =>
      _replace(_with(_item(id), text: text));

  @override
  Future<void> remove(String nodeId, String id) async => _set(
    _copy(
      items: [
        for (final i in _queue.items)
          if (i.id != id) i,
      ],
    ),
  );

  @override
  Future<void> move(String nodeId, String id, {required int to}) async =>
      _set(_queue.moved(id, to: to));

  @override
  Future<void> toggleDone(String nodeId, String id) async {
    final item = _item(id);
    _replace(
      _with(
        item,
        status: item.status == ItemStatus.done
            ? ItemStatus.pending
            : ItemStatus.done,
      ),
    );
  }

  @override
  Future<void> reopen(String nodeId, String id) async =>
      _replace(_with(_item(id), status: ItemStatus.pending, awaiting: false));

  @override
  Future<void> send(String nodeId, {String? id}) async {
    final destination = _queue.destination;
    if (destination == null) {
      throw const QueueRefused('Ligue a fila a um agente para mandar');
    }
    final item = id != null
        ? _item(id)
        : _queue.items
              .where((i) => i.status == ItemStatus.pending && !i.empty)
              .firstOrNull;
    if (item == null) throw const QueueRefused('Nada pendente para mandar');
    if (item.empty) throw const QueueRefused('Tarefa em branco');
    // Mandar por cima de uma em andamento fecha a anterior.
    final items = [
      for (final i in _queue.items)
        if (i.status == ItemStatus.sent && i.id != item.id)
          _with(i, status: ItemStatus.done)
        else
          i,
    ];
    _set(_copy(items: items));
    _replace(
      _with(
        _item(item.id),
        status: ItemStatus.sent,
        sentTo: destination,
        sentAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> reply(String nodeId, String id, String text) async {
    final item = _item(id);
    if (_queue.destination == null) {
      throw const QueueRefused('Ligue a fila a um agente para responder');
    }
    _replace(
      _with(
        item,
        awaiting: false,
        thread: [
          ...item.thread,
          QueueMessage(kind: MessageKind.reply, text: text, at: DateTime.now()),
        ],
      ),
    );
  }

  @override
  Future<void> setAuto(String nodeId, {required bool on}) async =>
      _set(_copy(auto: on));

  @override
  Future<void> setTarget(String nodeId, String target) async =>
      _set(_copy(target: target));

  @override
  Future<void> clearDone(String nodeId) async => _set(
    _copy(
      items: [
        for (final i in _queue.items)
          if (i.status != ItemStatus.done) i,
      ],
    ),
  );

  @override
  Future<void> attach(
    String nodeId,
    String id,
    List<PastedImage> images,
  ) async {
    attached.putIfAbsent(id, () => []).addAll(images);
    final item = _item(id);
    _replace(
      _with(item, images: [...item.images, for (final i in images) i.name]),
    );
  }

  @override
  Future<String> attachLoose(
    String nodeId,
    List<PastedImage> images, {
    String? open,
  }) async {
    final target = open == null
        ? null
        : _queue.items.where((i) => i.id == open && !i.locked).firstOrNull;
    final id = target?.id ?? await add(nodeId);
    await attach(nodeId, id, images);
    return id;
  }

  @override
  Future<void> detach(String nodeId, String id, String image) async {
    final item = _item(id);
    _replace(
      _with(
        item,
        images: [
          for (final i in item.images)
            if (i != image) i,
        ],
      ),
    );
  }
}
