import 'dart:async';

import 'package:egeon_deck/features/chat/domain/errors/chat_error.dart';
import 'package:egeon_deck/features/chat/domain/entities/chat_block.dart';
import 'package:egeon_deck/features/chat/domain/entities/chat_completion.dart';
import 'package:egeon_deck/features/chat/domain/entities/chat_participant.dart';
import 'package:egeon_deck/features/chat/domain/entities/chat_queue.dart';
import 'package:egeon_deck/features/chat/domain/entities/permission_request.dart';
import 'package:egeon_deck/features/chat/domain/entities/chat_thread.dart';
import 'package:egeon_deck/features/chat/domain/entities/chat_update.dart';
import 'package:egeon_deck/features/chat/domain/repository/chat_repository.dart';

/// O chat falso: o teste empurra eventos e lê os gestos da UI.
class FakeChatRepository implements ChatRepository {
  final _updates = StreamController<ChatUpdate>.broadcast();
  final steps = <String>[];
  final groups = <String>[];
  final sent = <({List<String> to, String text, String? quote})>[];
  var more = 0;

  /// Faz `chat_more` falhar, para provar que o pedido se repete.
  var failMore = false;
  var snapshots = 0;
  var watchers = 0;

  /// O que o "core" devolve ao pedir o instantâneo.
  ChatThread thread = const ChatThread();

  void push(ChatUpdate update) => _updates.add(update);

  /// Entrega a thread inteira, como o core na assinatura.
  void reset(
    int rev,
    List<ChatBlock> blocks, {
    List<ChatParticipantInfo>? participants,
    List<ChatQueueInfo>? queues,
    PermissionRequest? permission,
  }) => push(
    ChatUpdate(
      workbench: 'b1',
      rev: rev,
      ops: [
        ResetOp(blocks),
        if (participants != null) ParticipantsOp(participants),
        if (queues != null) QueuesOp(queues),
        PermissionOp(permission),
      ],
    ),
  );

  @override
  Stream<ChatUpdate> watch(String workbenchId) {
    late StreamController<ChatUpdate> controller;
    StreamSubscription<ChatUpdate>? inner;
    controller = StreamController<ChatUpdate>(
      onListen: () {
        watchers++;
        inner = _updates.stream.listen(controller.add);
      },
      onCancel: () {
        watchers--;
        return inner?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  Future<ChatThread> snapshot(String workbenchId) async {
    snapshots++;
    return thread;
  }

  @override
  Future<void> toggleStep(String workbenchId, String blockId) async =>
      steps.add(blockId);

  @override
  Future<void> cycleGroup(String workbenchId, String blockId) async =>
      groups.add(blockId);

  @override
  Future<void> loadMore(String workbenchId) async {
    more++;
    if (failMore) throw StateError('falhou');
  }

  var clears = 0;
  var newQueues = 0;
  final newQueueAgents = <String?>[];

  /// Se preenchido, o core recusa criar a fila com este texto.
  String? refuseNewQueue;

  /// O id que o "core" dá à fila nova.
  var newQueueId = 'fila-nova';
  final completions = <({String text, int caret, String? to})>[];

  /// O que o "core" sugere; por padrão, nada.
  ChatCompletion Function(String text, int caret) completer = (text, caret) =>
      ChatCompletion.none(caret);
  final answers = <Map<String, Object?>>[];

  @override
  Future<void> answerPermission(
    String workbenchId,
    String request, {
    String? answer,
    String? choice,
    Map<String, List<String>>? answers,
  }) async => this.answers.add({
    'request': request,
    'answer': ?answer,
    'choice': ?choice,
    'answers': ?answers,
  });

  @override
  Future<ChatCompletion> complete(
    String workbenchId,
    String text,
    int caret, {
    String? to,
    String? search,
  }) async {
    completions.add((text: text, caret: caret, to: to));
    return completer(text, caret);
  }

  @override
  Future<String> newQueue(String workbenchId, {String? agent}) async {
    newQueues++;
    newQueueAgents.add(agent);
    final reason = refuseNewQueue;
    if (reason != null) throw ChatRefused(reason);
    return newQueueId;
  }

  @override
  Future<void> clear(String workbenchId) async => clears++;

  @override
  Future<void> send(
    String workbenchId, {
    required List<String> to,
    required String text,
    String? quoteKey,
  }) async => sent.add((to: to, text: text, quote: quoteKey));
}
