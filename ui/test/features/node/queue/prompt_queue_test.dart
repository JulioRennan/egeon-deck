import 'package:egeon_deck/features/node/queue/domain/entities/prompt_queue.dart';
import 'package:egeon_deck/features/node/queue/domain/entities/queue_item.dart';
import 'package:egeon_deck/features/node/queue/domain/entities/queue_panel.dart';
import 'package:flutter_test/flutter_test.dart';

/// Porte de PromptQueueTests: o que é do modelo que a tela mostra (reordenar). O
/// destino, o resumo e o runner da fila são do core.
void main() {
  chatColumnTests();
  PromptQueue queueOf(
    List<String> ids, {
    String? target,
    List<String> linked = const [],
  }) => PromptQueue(
    items: [for (final id in ids) QueueItem(id: id, text: id)],
    target: target,
    targets: [for (final id in linked) QueueTarget(id: id, label: id)],
  );

  test('subir e descer não sai da lista', () {
    var queue = queueOf(['a', 'b', 'c']);
    queue = queue.movedBy('a', -1);
    expect(queue.items.map((i) => i.id), ['a', 'b', 'c']);
    queue = queue.movedBy('a', 1);
    expect(queue.items.map((i) => i.id), ['b', 'a', 'c']);
    queue = queue.movedBy('c', -5);
    expect(queue.items.map((i) => i.id), ['c', 'b', 'a']);
  });

  test('o arrasto conta só as linhas que ficaram no lugar', () {
    var queue = queueOf(['a', 'b', 'c', 'd']);
    // "a" solto depois de "c": entre as que ficaram (b, c, d), posição 2.
    queue = queue.moved('a', to: 2);
    expect(queue.items.map((i) => i.id), ['b', 'c', 'a', 'd']);
    queue = queue.moved('d', to: 0);
    expect(queue.items.map((i) => i.id), ['d', 'b', 'c', 'a']);
    queue = queue.moved('b', to: 99);
    expect(queue.items.map((i) => i.id), ['d', 'c', 'a', 'b']);
  });

  test('a fila vai e volta pelo mapa', () {
    final queue = PromptQueue(
      items: [
        QueueItem(
          id: 'a',
          text: 'oi',
          images: const ['p.png'],
          status: ItemStatus.sent,
          sentTo: 'dev',
          sentAt: DateTime.fromMillisecondsSinceEpoch(1000000 * 1000),
          awaiting: true,
          locked: true,
          thread: [
            QueueMessage(
              kind: MessageKind.question,
              text: 'qual?',
              author: 'dev',
              at: DateTime.fromMillisecondsSinceEpoch(2000000 * 1000),
            ),
          ],
        ),
      ],
      auto: true,
      target: 'dev',
      targets: const [QueueTarget(id: 'dev', label: 'Dev')],
      blocker: 'x',
      destination: 'dev',
      pending: 2,
      asking: true,
      summary: '? pergunta',
      subtitle: '2 pendentes',
      imageExtensions: const ['png', 'jpg'],
    );
    expect(PromptQueue.fromMap(queue.toMap()).toMap(), queue.toMap());
  });
}

/// Porte de PromptQueueTests (coluna do chat): largura do painel.
void chatColumnTests() {
  group('coluna do chat', () {
    test('a largura arrastada fica dentro dos limites', () {
      expect(QueuePanel.width(content: 1000, preferred: 550), 550);
      // Nem o painel some, nem a conversa.
      expect(
        QueuePanel.width(content: 1000, preferred: 100),
        QueuePanel.minPanel,
      );
      expect(QueuePanel.width(content: 1000, preferred: 950), 600);
      // A escolha sobrevive à janela encolher: volta quando ela crescer.
      expect(QueuePanel.width(content: 800, preferred: 550), 400);
      expect(QueuePanel.width(content: 1200, preferred: 550), 550);
    });

    test('o painel deixa espaço para a conversa', () {
      expect(QueuePanel.width(content: 1000), 420);
      expect(QueuePanel.width(content: 1600), 672);
      // Estreita: a thread fica com 400 antes de o painel chegar ao que pede.
      expect(QueuePanel.width(content: 780), 380);
      expect(QueuePanel.width(content: 500), 300);
    });
  });
}
