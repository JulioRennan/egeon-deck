import 'package:egeon_deck/core/domain/entities/workbench_node.dart';
import 'package:egeon_deck/features/canvas/domain/entities/canvas_card.dart';

import '../../../support/in_memory_canvas_repository.dart';

import 'package:egeon_deck/features/node/card/domain/entities/card_activity.dart';
import 'package:egeon_deck/commons/utils/agent_identity.dart';
import 'package:egeon_deck/commons/widgets/eg/identity.dart';
import 'package:egeon_deck/commons/widgets/eg/spinner.dart';
import 'package:egeon_deck/commons/widgets/eg/status.dart';
import 'package:egeon_deck/commons/widgets/eg/status_dot.dart';
import 'package:egeon_deck/features/node/card/presentation/widgets/card_state.dart';
import 'package:egeon_deck/theme/egeon_colors.dart';
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

  group('o ponto de estado do cabeçalho', () {
    test('o core diz o glifo e o tom; a UI escolhe um dos cinco estados', () {
      CardState of(CardActivity a) => CardState.of(a);
      expect(of(CardActivity.none), CardState.idle);
      expect(of(const CardActivity(needsAttention: true)), CardState.attention);
      expect(
        of(const CardActivity(glyph: ActivityGlyph.spinner)),
        CardState.working,
      );
      expect(
        of(const CardActivity(glyph: ActivityGlyph.hourglass)),
        CardState.working,
      );
      expect(of(const CardActivity(tone: ActivityTone.green)), CardState.done);
      expect(of(const CardActivity(tone: ActivityTone.red)), CardState.error);
      expect(
        of(const CardActivity(glyph: ActivityGlyph.cross)),
        CardState.error,
      );
      // Pedir você ganha de qualquer outro tom.
      expect(
        of(
          const CardActivity(
            needsAttention: true,
            tone: ActivityTone.red,
            glyph: ActivityGlyph.spinner,
          ),
        ),
        CardState.attention,
      );
    });

    testWidgets('cada card mostra o estado dele; o nome leva a identidade', (
      tester,
    ) async {
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

      Status statusOf(String id) => tester
          .widget<StatusDot>(
            find.descendant(of: card(id), matching: find.byType(StatusDot)),
          )
          .status;
      expect(statusOf('a'), Status.attention);
      expect(statusOf('b'), Status.running);
      expect(
        find.descendant(of: card('b'), matching: find.byType(Spinner)),
        findsOneWidget,
        reason: 'trabalhando gira',
      );

      // Cada agente, na ordem em que aparecem, leva uma cor de identidade.
      Color? titleColor(String id) => tester
          .widget<Text>(find.descendant(of: card(id), matching: find.text(id)))
          .style!
          .color;
      final c = EgeonColors.dark;
      expect(titleColor('a'), agentIdentity('a').color(c));
      expect(titleColor('b'), agentIdentity('b').color(c));
    });
  });

  testWidgets(
    'o maestro leva a faixa, a etiqueta e o anel de 4 (sempre em sand, e não na cor do agente)',
    (tester) async {
      final repo = InMemoryCanvasRepository(
        cards: [
          agent(
            'm',
            200,
            maestro: true,
            activity: const CardActivity(glyph: ActivityGlyph.spinner),
          ),
          agent('n', 1100),
        ],
        links: const [],
      );
      await pumpCanvas(tester, repo);
      final c = EgeonColors.dark;
      expect(
        tester
            .widget<Text>(
              find.descendant(of: card('m'), matching: find.text('m')),
            )
            .style!
            .color,
        Identity.sand.color(c),
      );
      expect(
        find.descendant(of: card('m'), matching: find.text('maestro')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card('n'), matching: find.text('maestro')),
        findsNothing,
      );
      BoxDecoration frame(String id) =>
          tester
                  .widgetList<DecoratedBox>(
                    find.descendant(
                      of: card(id),
                      matching: find.byType(DecoratedBox),
                    ),
                  )
                  .first
                  .decoration
              as BoxDecoration;
      expect(
        (frame('m').border! as Border).top.color,
        Identity.sand.color(c).withValues(alpha: 0.9),
      );
      expect(
        frame('m').boxShadow!.any((s) => s.spreadRadius == 4),
        isTrue,
        reason: 'anel de 4px',
      );
      expect(
        frame('n').boxShadow!.any((s) => s.spreadRadius == 3),
        isTrue,
        reason: 'anel de 3px',
      );
    },
  );

  testWidgets(
    'o maestro que precisa de você: a borda laranja vence a sand, a etiqueta fica',
    (tester) async {
      final repo = InMemoryCanvasRepository(
        cards: [
          agent(
            'm',
            200,
            maestro: true,
            activity: const CardActivity(needsAttention: true),
          ),
        ],
        links: const [],
      );
      await pumpCanvas(tester, repo);
      final c = EgeonColors.dark;
      final frame =
          tester
                  .widgetList<DecoratedBox>(
                    find.descendant(
                      of: card('m'),
                      matching: find.byType(DecoratedBox),
                    ),
                  )
                  .first
                  .decoration
              as BoxDecoration;
      expect(
        (frame.border! as Border).top.color,
        c.attention.withValues(alpha: 0.7),
      );
      expect(
        frame.boxShadow!.any(
          (s) => s.color == c.attention.withValues(alpha: 0.14),
        ),
        isTrue,
        reason: 'o anel é o do "precisa de você"',
      );
      expect(
        find.descendant(of: card('m'), matching: find.text('maestro')),
        findsOneWidget,
      );
    },
  );

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
