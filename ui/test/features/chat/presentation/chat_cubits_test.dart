import 'dart:async';

import 'package:egeon_deck/features/chat/domain/entities/chat_participant.dart';
import 'package:egeon_deck/features/chat/domain/entities/chat_queue.dart';
import 'package:egeon_deck/features/chat/domain/entities/chat_thread.dart';
import 'package:egeon_deck/features/chat/domain/errors/chat_error.dart';
import 'package:egeon_deck/features/chat/domain/usecase/chat_actions.dart';
import 'package:egeon_deck/features/chat/domain/usecase/watch_chat.dart';
import 'package:egeon_deck/features/chat/presentation/cubit/chat_composer_cubit.dart';
import 'package:egeon_deck/features/chat/presentation/cubit/chat_conversation_cubit.dart';
import 'package:egeon_deck/features/chat/presentation/cubit/chat_queue_panel_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_chat_repository.dart';
import '../../../support/pump.dart';

/// Os três cubits do chat: a conversa assina o core; composer e painel seguem
/// a thread dela, e o que passa (mandou, a fila foi recusada) sai como evento.
void main() {
  const front = ChatParticipantInfo(
    id: 'front',
    address: 'deck/front',
    isAgent: true,
  );
  const back = ChatParticipantInfo(
    id: 'back',
    address: 'deck/back',
    isAgent: true,
  );
  const sh = ChatParticipantInfo(
    id: 'sh',
    address: 'deck/sh',
    isAgent: false,
    screen: 'wb.sh',
  );
  const deadBack = ChatParticipantInfo(
    id: 'back',
    address: 'deck/back',
    isAgent: true,
    activity: 'dead',
  );

  late FakeChatRepository repository;
  late StreamController<ChatThread> threads;

  setUp(() {
    repository = FakeChatRepository();
    threads = StreamController<ChatThread>.broadcast();
  });
  tearDown(() => threads.close());

  ChatComposerCubit composer() {
    final cubit = ChatComposerCubit(
      workbenchId: 'wb',
      threads: threads.stream,
      actions: ChatActions(repository),
    );
    addTearDown(cubit.close);
    return cubit;
  }

  ChatQueuePanelCubit panel() {
    final cubit = ChatQueuePanelCubit(
      workbenchId: 'wb',
      threads: threads.stream,
      actions: ChatActions(repository),
    );
    addTearDown(cubit.close);
    return cubit;
  }

  Future<void> people(List<ChatParticipantInfo> list) async {
    threads.add(ChatThread(participants: list));
    await pump();
  }

  group('o composer', () {
    test('sem ninguém vivo não manda para ninguém', () async {
      final cubit = composer();
      await people(const [deadBack]);
      expect(cubit.state, isA<ComposerNobody>());
      cubit.send('oi');
      expect(repository.sent, isEmpty);
    });

    test('vai ao primeiro agente vivo; o Tab passa pelos agentes', () async {
      final cubit = composer();
      await people(const [sh, front, back]);
      expect(cubit.state, isA<ComposerToAgent>());
      expect(cubit.state.target?.id, 'front');
      cubit.focusNext();
      expect(cubit.state.target?.id, 'back');
      cubit.focusNext();
      expect(cubit.state.target?.id, 'front', reason: 'o shell fica fora');
    });

    test('shell em foco é o terminal no lugar da thread', () async {
      final cubit = composer();
      await people(const [front, sh]);
      cubit.focusOn('sh');
      expect(
        cubit.state,
        isA<ComposerToShell>().having((s) => s.target?.screen, 'tela', 'wb.sh'),
      );
      expect(cubit.state.queueAgent, 'front', reason: 'fila só liga a agente');
    });

    test('o foco que morre cai no primeiro agente vivo', () async {
      final cubit = composer();
      await people(const [front, back]);
      cubit.focusOn('back');
      expect(cubit.state.target?.id, 'back');
      await people(const [front, deadBack]);
      expect(cubit.state.target?.id, 'front');
    });

    test('mandar avisa a thread e leva a citação junto, uma vez', () async {
      final cubit = composer();
      final sent = <void>[];
      final listening = cubit.sent.listen(sent.add);
      await people(const [front]);
      cubit.send('  ');
      expect(sent, isEmpty, reason: 'texto vazio não vai');
      cubit.send('oi');
      await pump();
      expect(sent, hasLength(1));
      expect(repository.sent.single.to, ['front']);
      await listening.cancel();
    });
  });

  group('o painel das filas', () {
    const q1 = ChatQueueInfo(id: 'q1', summary: '1 pendente');

    test('abre, fecha no mesmo clique e fecha se a fila sai', () async {
      final cubit = panel();
      threads.add(const ChatThread(queues: [q1]));
      await pump();
      expect(cubit.state, isA<QueuePanelClosed>());
      cubit.toggle('q1');
      expect(cubit.state, isA<QueuePanelOpen>());
      cubit.toggle('q1');
      expect(cubit.state, isA<QueuePanelClosed>());
      cubit.toggle('q1');
      threads.add(const ChatThread());
      await pump();
      expect(cubit.state, isA<QueuePanelClosed>());
    });

    test('a fila nova abre; a recusa sai como evento', () async {
      final cubit = panel();
      final refusals = <ChatError>[];
      final listening = cubit.refusals.listen(refusals.add);
      repository.refuseNewQueue = 'sem agente';
      await cubit.newQueue(agent: 'front');
      await pump();
      expect(refusals.single, isA<ChatRefused>());
      expect(repository.newQueueAgents, ['front']);

      repository.refuseNewQueue = null;
      await cubit.newQueue(agent: 'front');
      threads.add(
        const ChatThread(
          queues: [ChatQueueInfo(id: 'fila-nova', summary: '')],
        ),
      );
      await pump();
      expect(
        cubit.state,
        isA<QueuePanelOpen>().having((s) => s.queue.id, 'id', 'fila-nova'),
      );
      await listening.cancel();
    });
  });

  test('quem segue a conversa começa pela thread de agora', () async {
    final conversation = ChatConversationCubit(
      workbenchId: 'wb',
      watch: WatchChat(repository),
      actions: ChatActions(repository),
    );
    addTearDown(conversation.close);
    expect(conversation.state, isA<ChatOpening>());
    final first = await conversation.threads.first;
    expect(first.blocks, isEmpty);
  });
}
