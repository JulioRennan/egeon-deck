import 'package:egeon_deck/features/node/queue/domain/entities/prompt_queue.dart';
import 'package:egeon_deck/features/node/queue/domain/entities/queue_effect.dart';
import 'package:egeon_deck/features/node/queue/domain/entities/queue_item.dart';

import '../../../support/in_memory_queue_repository.dart';

import 'package:egeon_deck/features/node/queue/domain/usecase/edit_queue.dart';
import 'package:egeon_deck/features/node/queue/domain/usecase/watch_queue.dart';
import 'package:egeon_deck/features/node/queue/domain/usecase/watch_queue_effects.dart';
import 'package:egeon_deck/features/node/queue/presentation/cubit/queue_cubit.dart';
import 'package:egeon_deck/features/node/queue/presentation/cubit/queue_notice_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/pasted_image_fake.dart';
import '../../../support/pump.dart';

import 'package:egeon_deck/features/node/queue/domain/errors/queue_error.dart';

/// A tarefa aberta, ou nula.
String? openOf(QueueCubit cubit) => switch (cubit.state) {
  QueueEditing(:final open) => open,
  QueueWaiting() || QueueBrowsing() => null,
};

void main() {
  Future<(QueueCubit, InMemoryQueueRepository)> make({
    PromptQueue? queue,
  }) async {
    final repo = InMemoryQueueRepository(queue: queue);
    final cubit = QueueCubit(
      nodeId: 'fila',
      watch: WatchQueue(repo),
      edit: EditQueue(repo),
    );
    await pump();
    return (cubit, repo);
  }

  const linked = [QueueTarget(id: 'dev', label: 'Dev')];

  test('anotar uma tarefa com texto não a abre; em branco, abre', () async {
    final (cubit, _) = await make();
    await cubit.create(text: 'primeira');
    await pump();
    expect(cubit.state.queue.items.single.text, 'primeira');
    expect(openOf(cubit), isNull);

    await cubit.create();
    await pump();
    expect(openOf(cubit), cubit.state.queue.items.last.id);
    await cubit.close();
  });

  test('Enter numa tarefa aberta abre outra logo abaixo dela', () async {
    final (cubit, _) = await make();
    await cubit.create(text: 'a');
    await cubit.create(text: 'c');
    await pump();
    await cubit.create(after: cubit.state.queue.items.first.id);
    await pump();
    expect(cubit.state.queue.items.map((i) => i.text), ['a', '', 'c']);
    await cubit.close();
  });

  test('abrir outra tarefa larga a anterior se ficou em branco', () async {
    final (cubit, _) = await make();
    await cubit.create();
    await pump();
    final blank = cubit.state.queue.items.single.id;
    await cubit.create(text: 'real');
    await pump();
    cubit.expand(cubit.state.queue.items.last.id);
    await pump();
    expect(cubit.state.queue.indexOf(blank), isNull);
    await cubit.close();
  });

  test('fechar a aberta em branco também a larga', () async {
    final (cubit, _) = await make();
    await cubit.create();
    await pump();
    cubit.collapse();
    await pump();
    expect(cubit.state.queue.items, isEmpty);
    expect(openOf(cubit), isNull);
    await cubit.close();
  });

  test('sem ligação, mandar mostra o aviso e ele some sozinho', () async {
    final (cubit, _) = await make();
    final notice = QueueNoticeCubit(
      cubit.notices,
      failureTime: const Duration(milliseconds: 30),
    );
    await cubit.create(text: 'a');
    await pump();
    await cubit.send(id: cubit.state.queue.items.single.id);
    await pump();
    expect(
      notice.state,
      isA<QueueSendFailed>().having(
        (s) => s.failure.error,
        'erro',
        isA<QueueRefused>().having(
          (e) => e.message,
          'message',
          contains('Ligue a fila'),
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(notice.state, isNot(isA<QueueSendFailed>()));
    await notice.close();
    await cubit.close();
  });

  test(
    'o aviso mostra por que a fila não anda, e o erro passa na frente',
    () async {
      final (cubit, _) = await make(
        queue: const PromptQueue(blocker: 'Esperando o agente'),
      );
      final notice = QueueNoticeCubit(cubit.notices);
      await pump();
      expect(notice.state, isA<QueueBlocked>());
      expect((notice.state as QueueBlocked).text, 'Esperando o agente');
      await cubit.create(text: 'a');
      await pump();
      await cubit.send(id: cubit.state.queue.items.single.id);
      await pump();
      expect(notice.state, isA<QueueSendFailed>());
      await notice.close();
      await cubit.close();
    },
  );

  test('com ligação, mandar marca como enviada e trava', () async {
    final (cubit, _) = await make(queue: const PromptQueue(targets: linked));
    await cubit.create(text: 'a');
    await pump();
    await cubit.send();
    await pump();
    final item = cubit.state.queue.items.single;
    expect(item.status, ItemStatus.sent);
    expect(item.locked, isTrue);
    expect(item.sentTo, 'dev');
    await cubit.close();
  });

  test('mandar por cima de uma em andamento fecha a anterior', () async {
    final (cubit, _) = await make(queue: const PromptQueue(targets: linked));
    await cubit.create(text: 'a');
    await cubit.create(text: 'b');
    await pump();
    await cubit.send(id: cubit.state.queue.items[0].id);
    await pump();
    await cubit.send(id: cubit.state.queue.items[1].id);
    await pump();
    expect(cubit.state.queue.items.map((i) => i.status), [
      ItemStatus.done,
      ItemStatus.sent,
    ]);
    await cubit.close();
  });

  test('o checkbox marca e desmarca à mão; limpar tira o que foi', () async {
    final (cubit, _) = await make();
    await cubit.create(text: 'a');
    await cubit.create(text: 'b');
    await pump();
    cubit.toggleDone(cubit.state.queue.items.first.id);
    await pump();
    expect(cubit.state.queue.items.first.status, ItemStatus.done);
    cubit.clearDone();
    await pump();
    expect(cubit.state.queue.items.map((i) => i.text), ['b']);
    await cubit.close();
  });

  test('reordenar vai ao core e o índice conta as que ficaram', () async {
    final (cubit, _) = await make();
    for (final t in ['a', 'b', 'c', 'd']) {
      await cubit.create(text: t);
    }
    await pump();
    cubit.move(cubit.state.queue.items.first.id, to: 2);
    await pump();
    expect(cubit.state.queue.items.map((i) => i.text), ['b', 'c', 'a', 'd']);
    cubit.moveBy(cubit.state.queue.items.last.id, -1);
    await pump();
    expect(cubit.state.queue.items.map((i) => i.text), ['b', 'c', 'd', 'a']);
    await cubit.close();
  });

  test('automático e destino passam pelo core', () async {
    final (cubit, _) = await make(
      queue: const PromptQueue(
        targets: [
          QueueTarget(id: 'dev', label: 'Dev'),
          QueueTarget(id: 'front', label: 'Front'),
        ],
      ),
    );
    cubit.setAuto(on: true);
    cubit.setTarget('front');
    await pump();
    expect(cubit.state.queue.auto, isTrue);
    expect(cubit.state.queue.destination, 'front');
    await cubit.close();
  });

  test('a tarefa aberta que sai da fila fecha junto', () async {
    final (cubit, _) = await make();
    await cubit.create();
    await pump();
    final id = cubit.state.queue.items.single.id;
    cubit.remove(id);
    await pump();
    expect(openOf(cubit), isNull);
    await cubit.close();
  });

  test('print solto sem tarefa aberta vira tarefa nova já aberta', () async {
    final (cubit, repo) = await make();
    await cubit.attachToOpenOrNew([PastedImageFake.make('a.png')]);
    await pump();
    final item = cubit.state.queue.items.single;
    expect(item.images, ['a.png']);
    expect(openOf(cubit), item.id);
    expect(repo.attached[item.id], hasLength(1));
    await cubit.close();
  });

  test('core fora: anotar não derruba o cubit', () async {
    final repo = _FailingQueueRepository();
    final cubit = QueueCubit(
      nodeId: 'fila',
      watch: WatchQueue(repo),
      edit: EditQueue(repo),
    );
    await pump();
    await cubit.create(text: 'a');
    await cubit.attachToOpenOrNew([PastedImageFake.make('a.png')]);
    expect(cubit.state.queue.items, isEmpty);
    await cubit.close();
  });

  test('rascunho de fora cai na linha de baixo; abrir tarefa abre', () async {
    final repo = InMemoryQueueRepository(
      queue: const PromptQueue(
        items: [QueueItem(id: 'a1', text: 'x')],
      ),
    );
    final cubit = QueueCubit(
      nodeId: 'fila',
      watch: WatchQueue(repo),
      edit: EditQueue(repo),
      effects: WatchQueueEffects(repo),
    );
    final drafts = <String>[];
    final listening = cubit.drafts.listen(drafts.add);
    await pump();

    repo.effectsController.add(const QueueDraft('rascunho vindo do egeon'));
    await pump();
    expect(drafts, ['rascunho vindo do egeon']);
    // O mesmo texto de novo também vale.
    repo.effectsController.add(const QueueDraft('rascunho vindo do egeon'));
    await pump();
    expect(drafts, hasLength(2));
    await listening.cancel();

    repo.effectsController.add(const QueueOpenItem('a1'));
    await pump();
    expect(openOf(cubit), 'a1');
    await cubit.close();
  });

  group('arquivos soltos na fila', () {
    test(
      'só imagem entra; sem tarefa aberta vira tarefa nova já aberta',
      () async {
        final (cubit, repo) = await make();
        await cubit.attachFiles([
          '/tmp/nota.pdf',
          '/Users/eu/Desktop/Tela 1.PNG',
        ]);
        await pump();

        final item = cubit.state.queue.items.single;
        expect(item.images, ['Tela 1.PNG']);
        expect(openOf(cubit), item.id);
        expect(
          repo.attached[item.id]!.single.path,
          '/Users/eu/Desktop/Tela 1.PNG',
        );
        await cubit.close();
      },
    );

    test('o que não é imagem não cria nada', () async {
      final (cubit, _) = await make();
      await cubit.attachFiles(['/tmp/nota.pdf', '/tmp/script.swift']);
      await pump();
      expect(cubit.state.queue.items, isEmpty);
      await cubit.close();
    });

    test('com uma tarefa aberta, o print entra nela', () async {
      final (cubit, _) = await make();
      await cubit.create(text: 'a');
      await pump();
      final id = cubit.state.queue.items.single.id;
      cubit.expand(id);
      await cubit.attachFiles(['/tmp/x.jpg']);
      await pump();
      expect(cubit.state.queue.items, hasLength(1));
      expect(cubit.state.queue.items.single.images, ['x.jpg']);
      await cubit.close();
    });
  });
}

class _FailingQueueRepository extends InMemoryQueueRepository {
  @override
  Future<String> add(String nodeId, {String text = '', String? after}) =>
      Future.error(const QueueOffline());
}
