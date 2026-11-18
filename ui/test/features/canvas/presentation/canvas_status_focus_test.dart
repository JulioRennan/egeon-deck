import 'package:egeon_deck/core/domain/entities/workbench_node.dart';
import 'package:egeon_deck/features/canvas/domain/entities/canvas_card.dart';

import '../../../support/in_memory_canvas_repository.dart';

import 'package:egeon_deck/features/node/card/domain/entities/card_activity.dart';
import 'package:egeon_deck/features/node/card/presentation/widgets/card_accent.dart';
import 'package:egeon_deck/features/node/card/presentation/widgets/card_status.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/protocol_fixtures.dart';
import '../../../support/pump_canvas.dart';

/// O cabeçalho pronto do core (glifo, rótulo, tom, fila) e o foco da interface.
void main() {
  Finder card(String id) => find.byKey(ValueKey('card-$id'));

  CanvasCard agent(
    String id,
    double x, {
    CardActivity? activity,
    bool maestro = false,
  }) => CanvasCard(
    id: id,
    kind: NodeKind.agent,
    title: id,
    frame: Rect.fromLTWH(x, 300, 720, 460),
    activity: activity ?? CardActivity.none,
    maestro: maestro,
  );

  group('o texto de estado do cabeçalho', () {
    test('junta como o Swift: rótulo e fila separados por "·"', () {
      expect(
        const CardActivity(label: 'trabalhando', pending: 2).text,
        'trabalhando  ·  2 na fila',
      );
      expect(
        const CardActivity(label: 'precisa de você').text,
        'precisa de você',
      );
      expect(const CardActivity(pending: 1).text, '1 na fila');
      expect(CardActivity.none.text, isEmpty);
    });

    test('lê glifo, tom e fila da fixture do core', () {
      final nodes = (loadProtocolFixture('events')['nodes']!['nodes']! as List)
          .cast<Map<String, Object?>>();
      final asking = CardActivity.fromMap(
        nodes[0]['activity'] as Map<String, Object?>,
      );
      expect(asking.glyph, ActivityGlyph.dot);
      expect(asking.tone, ActivityTone.orange);
      expect(asking.label, 'precisa de você');
      expect(asking.needsAttention, isTrue);

      final working = CardActivity.fromMap(
        nodes[1]['activity'] as Map<String, Object?>,
      );
      expect(working.glyph, ActivityGlyph.spinner);
      expect(working.tone, isNull);
      expect(working.pending, 2);
      expect(working.text, 'trabalhando  ·  2 na fila');
    });

    test('glifo ou tom desconhecido não derruba a tela', () {
      final activity = CardActivity.fromMap({'glyph': 'novo', 'tone': 'roxo'});
      expect(activity.glyph, isNull);
      expect(activity.tone, isNull);
    });
  });

  testWidgets(
    'o card mostra glifo, rótulo e fila; o tom pinta o texto e o título',
    (tester) async {
      final repo = InMemoryCanvasRepository(
        cards: [
          agent(
            'a',
            200,
            activity: const CardActivity(
              state: 'asking',
              needsAttention: true,
              label: 'precisa de você',
              glyph: ActivityGlyph.dot,
              tone: ActivityTone.orange,
            ),
          ),
          agent(
            'b',
            1100,
            activity: const CardActivity(
              state: 'working',
              label: 'trabalhando',
              glyph: ActivityGlyph.spinner,
              pending: 2,
            ),
          ),
        ],
        links: const [],
      );
      await pumpCanvas(tester, repo);

      Text status(String id) => tester.widget<Text>(
        find.descendant(
          of: card(id),
          matching: find.byKey(const ValueKey('card-status')),
        ),
      );
      expect(status('a').data, '● precisa de você');
      expect(status('a').style!.color, ActivityColors.of(ActivityTone.orange));
      expect(status('b').data, contains('trabalhando  ·  2 na fila'));
      expect(
        status('b').data!.startsWith('●'),
        isFalse,
        reason: 'o glifo é o spinner',
      );

      // O título do que pede você leva a cor do tom; o outro, a do tipo.
      Color? titleColor(String id) => tester
          .widget<Text>(find.descendant(of: card(id), matching: find.text(id)))
          .style!
          .color;
      expect(titleColor('a'), ActivityColors.of(ActivityTone.orange));
      expect(titleColor('b'), CardAccent.agent);
    },
  );

  testWidgets('o spinner gira com o relógio', (tester) async {
    final repo = InMemoryCanvasRepository(
      cards: [
        agent(
          'a',
          200,
          activity: const CardActivity(
            label: 'trabalhando',
            glyph: ActivityGlyph.spinner,
          ),
        ),
      ],
      links: const [],
    );
    await pumpCanvas(tester, repo);
    String glyph() => tester
        .widget<Text>(find.byKey(const ValueKey('card-status')))
        .data!
        .split(' ')
        .first;
    final first = glyph();
    // O spinner lê o relógio de verdade, e não o falso do teste.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(glyph(), isNot(first));
  });

  testWidgets('o maestro leva o título dourado, mesmo com estado', (
    tester,
  ) async {
    final repo = InMemoryCanvasRepository(
      cards: [
        agent(
          'm',
          200,
          maestro: true,
          activity: const CardActivity(
            label: 'precisa de você',
            tone: ActivityTone.orange,
          ),
        ),
      ],
      links: const [],
    );
    await pumpCanvas(tester, repo);
    expect(
      tester
          .widget<Text>(
            find.descendant(of: card('m'), matching: find.text('m')),
          )
          .style!
          .color,
      CardAccent.maestro,
    );
  });

  group('foco da interface (ui_focus)', () {
    testWidgets(
      'clicar no card avisa o core uma vez; outro card avisa de novo',
      (tester) async {
        final repo = InMemoryCanvasRepository(
          cards: [agent('a', 200), agent('b', 1100)],
          links: const [],
        );
        await pumpCanvas(tester, repo);

        await tester.tapAt(tester.getTopLeft(card('a')) + const Offset(60, 20));
        await tester.pump();
        await tester.tapAt(tester.getTopLeft(card('a')) + const Offset(80, 20));
        await tester.pump();
        expect(repo.focuses, hasLength(1), reason: 'o mesmo card não repete');
        expect(repo.focuses.single.appActive, isTrue);
        expect(repo.focuses.single.nodeId, 'a');
        expect(repo.focuses.single.workbenchId, 'bancada');
        expect(
          repo.focuses.single.window,
          const Size(1200, 800),
          reason: 'o core usa o tamanho da área para o frame padrão',
        );

        await tester.tapAt(tester.getTopLeft(card('b')) + const Offset(60, 20));
        await tester.pump();
        expect(repo.focuses.map((f) => f.nodeId), ['a', 'b']);
      },
    );

    testWidgets(
      'a janela mudou com um nó em foco: o core recebe o tamanho novo',
      (tester) async {
        final repo = InMemoryCanvasRepository(
          cards: [agent('a', 200)],
          links: const [],
        );
        await pumpCanvas(tester, repo);
        await tester.tapAt(tester.getTopLeft(card('a')) + const Offset(60, 20));
        await tester.pump();
        expect(repo.focuses, hasLength(1));

        tester.view.physicalSize = const Size(1000, 700);
        await tester.pump();
        await tester.pump();
        expect(repo.focuses, hasLength(1), reason: 'espera o arrasto parar');
        await tester.pump(const Duration(milliseconds: 400));
        expect(repo.focuses, hasLength(2));
        expect(repo.focuses.last.nodeId, 'a');
        expect(repo.focuses.last.window, const Size(1000, 700));
      },
    );
  });
}
