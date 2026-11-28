import 'package:egeon_deck/core/domain/entities/workbench_node.dart';

import 'dart:ui';

import 'package:egeon_deck/commons/widgets/eg/edge_label.dart';
import 'package:egeon_deck/theme/egeon_colors.dart';
import 'package:egeon_deck/commons/widgets/eg/eg_icon.dart';
import 'package:egeon_deck/features/canvas/presentation/widgets/edge_controls.dart';
import 'package:egeon_deck/features/canvas/domain/entities/canvas_card.dart';
import 'package:egeon_deck/features/node/card/domain/entities/card_activity.dart';
import 'package:egeon_deck/features/canvas/domain/entities/edge_link.dart';
import 'package:egeon_deck/features/canvas/domain/repository/canvas_repository.dart';

import '../../../support/in_memory_canvas_repository.dart';

import 'package:egeon_deck/features/canvas/presentation/widgets/edge_painter.dart';
import 'package:egeon_deck/features/canvas/presentation/widgets/tool_overlay.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/pump_canvas.dart';

const cards = [
  CanvasCard(
    id: 'a',
    kind: NodeKind.shell,
    title: 'a',
    subtitle: '~/x',
    frame: Rect.fromLTWH(200, 300, 720, 460),
  ),
  CanvasCard(
    id: 'b',
    kind: NodeKind.agent,
    title: 'b',
    subtitle: '~/x',
    frame: Rect.fromLTWH(1100, 300, 720, 460),
  ),
];

Finder card(String id) => find.byKey(ValueKey('card-$id'));

/// O retângulo do card NA TELA: `getSize` devolve o tamanho local, sem o zoom.
Rect screenRect(WidgetTester tester, Finder finder) =>
    Rect.fromPoints(tester.getTopLeft(finder), tester.getBottomRight(finder));

/// O que o core tem agora. Stream fora do relógio falso: `runAsync` deixa o
/// microtask do repositório andar.
Future<CanvasSnapshot> snapshotOf(
  WidgetTester tester,
  InMemoryCanvasRepository repo,
) async => (await tester.runAsync(() => repo.watch('bancada').first))!;

Future<Rect> frameOf(
  WidgetTester tester,
  InMemoryCanvasRepository repo,
  String id,
) async =>
    (await snapshotOf(tester, repo)).cards.firstWhere((c) => c.id == id).frame;

void main() {
  testWidgets('abre enquadrado: os dois cards cabem na janela', (tester) async {
    final repo = InMemoryCanvasRepository(cards: cards, links: const []);
    await pumpCanvas(tester, repo);

    for (final id in ['a', 'b']) {
      final rect = screenRect(tester, card(id));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(1200));
      expect(rect.bottom, lessThanOrEqualTo(800));
    }
    expect(find.text('a'), findsWidgets);
  });

  testWidgets('quem espera você troca a borda e o anel para attention', (
    tester,
  ) async {
    final repo = InMemoryCanvasRepository(
      cards: [
        cards[0].copyWith(),
        const CanvasCard(
          id: 'b',
          kind: NodeKind.agent,
          title: 'b',
          frame: Rect.fromLTWH(1100, 300, 720, 460),
          activity: CardActivity(state: 'asking', needsAttention: true),
        ),
      ],
      links: const [],
    );
    await pumpCanvas(tester, repo);

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
    final attention = EgeonColors.dark.attention;
    expect(
      (frame('b').border! as Border).top.color,
      attention.withValues(alpha: 0.7),
    );
    expect(
      frame('b').boxShadow!.any(
        (s) =>
            s.color == attention.withValues(alpha: 0.14) && s.spreadRadius == 3,
      ),
      isTrue,
      reason: 'o anel de 3px',
    );
    expect(
      (frame('a').border! as Border).top.color,
      isNot(attention.withValues(alpha: 0.7)),
    );
  });

  testWidgets('arrastar o cabeçalho move o card e grava só ao soltar', (
    tester,
  ) async {
    final repo = InMemoryCanvasRepository(cards: cards, links: const []);
    await pumpCanvas(tester, repo);
    final zoom = screenRect(tester, card('a')).width / 720;
    final before = tester.getTopLeft(card('a'));

    final gesture = await tester.startGesture(before + const Offset(60, 20));
    await gesture.moveBy(const Offset(80, 0));
    await gesture.moveBy(const Offset(40, 30));
    await tester.pump();
    expect(tester.getTopLeft(card('a')).dx, closeTo(before.dx + 120, 1.5));
    expect(
      await frameOf(tester, repo, 'a'),
      cards.first.frame,
      reason: 'ainda não gravou',
    );

    await gesture.up();
    await tester.pump();
    final saved = await frameOf(tester, repo, 'a');
    expect(saved.left, closeTo(200 + 120 / zoom, 1.5));
    expect(saved.top, closeTo(300 + 30 / zoom, 1.5));
  });

  testWidgets(
    'um card além da janela, em coordenadas de documento, recebe o arrasto',
    (tester) async {
      final repo = InMemoryCanvasRepository(cards: cards, links: const []);
      await pumpCanvas(tester, repo);
      final b = screenRect(tester, card('b'));

      // A 80% da largura do card b o documento passa de x=1600, muito além da
      // janela de 1200: se o mundo medisse o hit test pela janela, o arrasto
      // cairia no pan do fundo e moveria tudo.
      final gesture = await tester.startGesture(
        Offset(b.left + b.width * 0.8, b.top + 10),
      );
      await gesture.moveBy(const Offset(40, 0));
      await gesture.up();
      await tester.pump();

      expect((await frameOf(tester, repo, 'b')).left, greaterThan(1100));
      expect(await frameOf(tester, repo, 'a'), cards.first.frame);
    },
  );

  testWidgets('apertar o X não arrasta o card', (tester) async {
    final repo = InMemoryCanvasRepository(cards: cards, links: const []);
    await pumpCanvas(tester, repo);
    final close = find.descendant(
      of: card('b'),
      matching: find.byKey(const ValueKey('card-close')),
    );
    final gesture = await tester.startGesture(tester.getCenter(close));
    await gesture.moveBy(const Offset(3, 2));
    await gesture.cancel();
    await tester.pump();
    expect(await frameOf(tester, repo, 'b'), cards.last.frame);
  });

  testWidgets('gesto da porta cancelado apaga a linha tracejada', (
    tester,
  ) async {
    final repo = InMemoryCanvasRepository(cards: cards, links: const []);
    await pumpCanvas(tester, repo);
    final port = find.descendant(
      of: card('a'),
      matching: find.byKey(const ValueKey('card-port')),
    );
    final gesture = await tester.startGesture(tester.getCenter(port));
    await gesture.moveBy(const Offset(60, 0));
    await tester.pump();
    EdgePainter painter() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((w) => w.painter)
        .whereType<EdgePainter>()
        .single;
    expect(painter().pending, isNotNull);
    await gesture.cancel();
    await tester.pump();
    expect(painter().pending, isNull);
  });

  testWidgets('a alça do canto redimensiona o card', (tester) async {
    final repo = InMemoryCanvasRepository(cards: cards, links: const []);
    await pumpCanvas(tester, repo);
    final zoom = screenRect(tester, card('a')).width / 720;
    final rect = screenRect(tester, card('a'));

    final gesture = await tester.startGesture(
      rect.bottomRight - const Offset(5, 5),
    );
    await gesture.moveBy(const Offset(50, 20));
    await gesture.up();
    await tester.pump();

    final saved = await frameOf(tester, repo, 'a');
    expect(saved.width, closeTo(720 + 50 / zoom, 1.5));
    expect(saved.height, closeTo(460 + 20 / zoom, 1.5));
  });

  testWidgets('arrastar o fundo pana a vista; ⌥ pana por cima de um card', (
    tester,
  ) async {
    final repo = InMemoryCanvasRepository(cards: cards, links: const []);
    await pumpCanvas(tester, repo);
    final before = tester.getTopLeft(card('a'));

    // Fundo: o canto de baixo da janela está vazio.
    final bg = await tester.startGesture(const Offset(600, 780));
    await bg.moveBy(const Offset(-30, 0));
    await bg.up();
    await tester.pump();
    expect(tester.getTopLeft(card('a')).dx, closeTo(before.dx - 30, 1.5));

    // ⌥ sobre o cabeçalho: pana, e o card não se move no documento.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.alt);
    final alt = await tester.startGesture(
      tester.getTopLeft(card('a')) + const Offset(60, 20),
    );
    await alt.moveBy(const Offset(20, 0));
    await alt.up();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.alt);
    await tester.pump();
    expect(await frameOf(tester, repo, 'a'), cards.first.frame);
  });

  testWidgets('⌘+scroll dá zoom no cursor; clicar no número volta a 100%', (
    tester,
  ) async {
    final repo = InMemoryCanvasRepository(cards: cards, links: const []);
    await pumpCanvas(tester, repo);
    final label = find.byKey(const ValueKey('zoom-label'));
    final shown = (tester.widget<Text>(
      find.descendant(of: label, matching: find.byType(Text)),
    )).data;

    await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(mouse.hover(const Offset(600, 500)));
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, -60)));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
    await tester.pump();
    final zoomed = tester
        .widget<Text>(find.descendant(of: label, matching: find.byType(Text)))
        .data;
    expect(zoomed, isNot(shown));

    await tester.tap(label);
    await tester.pump();
    expect(
      tester
          .widget<Text>(find.descendant(of: label, matching: find.byType(Text)))
          .data,
      '100%',
    );
  });

  testWidgets('os botões − e + andam pelos passos e enquadrar volta', (
    tester,
  ) async {
    final repo = InMemoryCanvasRepository(cards: cards, links: const []);
    await pumpCanvas(tester, repo);
    String shown() => tester
        .widget<Text>(
          find.descendant(
            of: find.byKey(const ValueKey('zoom-label')),
            matching: find.byType(Text),
          ),
        )
        .data!;

    await tester.tap(find.byKey(const ValueKey('zoom-label')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('zoom-in')));
    await tester.pump();
    expect(shown(), '125%');
    await tester.tap(find.byKey(const ValueKey('zoom-out')));
    await tester.tap(find.byKey(const ValueKey('zoom-out')));
    await tester.pump();
    expect(shown(), '80%');

    await tester.tap(find.byKey(const ValueKey('fit-all')));
    await tester.pump();
    expect(screenRect(tester, card('a')).left, greaterThanOrEqualTo(0));
  });

  testWidgets('ferramenta armada: o clique cria o nó e volta ao cursor', (
    tester,
  ) async {
    final repo = InMemoryCanvasRepository(cards: cards, links: const []);
    await pumpCanvas(tester, repo);
    expect(find.byType(ToolOverlay), findsNothing);

    await tester.tap(find.byKey(const ValueKey('tool-queue')));
    await tester.pump();
    expect(find.byType(ToolOverlay), findsOneWidget);

    // Em cima de um card: sem o overlay, isto cairia no card.
    await tester.tapAt(tester.getCenter(card('a')));
    await tester.pump();
    await tester.pump();

    expect(find.byType(ToolOverlay), findsNothing);
    expect(find.byKey(const ValueKey('card-fila1')), findsOneWidget);
  });

  testWidgets(
    'arrastar a partir do + e soltar no outro terminal liga os dois',
    (tester) async {
      final repo = InMemoryCanvasRepository(cards: cards, links: const []);
      await pumpCanvas(tester, repo);

      final port = find.descendant(
        of: card('a'),
        matching: find.byKey(const ValueKey('card-port')),
      );
      final gesture = await tester.startGesture(tester.getCenter(port));
      await gesture.moveTo(tester.getCenter(card('b')));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      await tester.pump();

      final snapshot = await snapshotOf(tester, repo);
      expect(snapshot.links, hasLength(1));
      expect(snapshot.links.single.aToB, isTrue);
    },
  );

  testWidgets('o X remove o card e as ligações dele', (tester) async {
    final repo = InMemoryCanvasRepository(
      cards: cards,
      links: const [EdgeLink(a: 'a', b: 'b')],
    );
    await pumpCanvas(tester, repo);

    await tester.tap(
      find.descendant(
        of: card('a'),
        matching: find.byKey(const ValueKey('card-close')),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(card('a'), findsNothing);
    expect((await snapshotOf(tester, repo)).links, isEmpty);
  });

  group('a ligação sob o cursor', () {
    Future<TestGesture> hoverOnLink(WidgetTester tester) async {
      final a = screenRect(tester, card('a'));
      final b = screenRect(tester, card('b'));
      // Meio da linha reta: porta direita de a → porta esquerda de b.
      final mid = Offset((a.right + b.left) / 2, a.center.dy);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(mid);
      await tester.pump();
      return mouse;
    }

    testWidgets('mostra os controles e o botão de direção cicla', (
      tester,
    ) async {
      final repo = InMemoryCanvasRepository(
        cards: cards,
        links: const [EdgeLink(a: 'a', b: 'b')],
      );
      await pumpCanvas(tester, repo);
      expect(find.text('→'), findsNothing);

      await hoverOnLink(tester);
      expect(find.text('→'), findsOneWidget);
      expect(find.widgetWithText(EdgeLabel, '2'), findsOneWidget);

      await tester.tap(find.text('→'));
      await tester.pump();
      await tester.pump();
      expect((await snapshotOf(tester, repo)).links.single.bToA, isTrue);
    });

    testWidgets('a pastilha chama o editor de limite e o X remove a ligação', (
      tester,
    ) async {
      final repo = InMemoryCanvasRepository(
        cards: cards,
        links: const [EdgeLink(a: 'a', b: 'b', maxSends: null)],
      );
      final edited = <dynamic>[];
      await pumpCanvas(tester, repo, onEditLimit: edited.add);
      await hoverOnLink(tester);
      expect(find.widgetWithText(EdgeLabel, '∞'), findsOneWidget);

      await tester.tap(find.widgetWithText(EdgeLabel, '∞'));
      expect(edited, hasLength(1));

      final remove = find
          .descendant(
            of: find.byType(EdgeControlsLayer),
            matching: find.byType(EgIcon),
          )
          .last;
      await tester.tap(remove);
      await tester.pump();
      await tester.pump();
      expect((await snapshotOf(tester, repo)).links, isEmpty);
    });
  });

  group('onde se clica, o ponteiro diz (ADR-048)', () {
    TestGesture? mouse;
    Future<MouseCursor> cursorOver(WidgetTester tester, Offset at) async {
      if (mouse == null) {
        mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse!.addPointer(location: Offset.zero);
      }
      await mouse!.moveTo(at);
      await tester.pump();
      return RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1) ??
          SystemMouseCursors.basic;
    }

    testWidgets('mão em tudo que responde a clique', (tester) async {
      final repo = InMemoryCanvasRepository(cards: cards, links: const []);
      await pumpCanvas(tester, repo);
      final clickable = <String, Finder>{
        'cursor': find.byKey(const ValueKey('tool-cursor')),
        'shell': find.byKey(const ValueKey('tool-shell')),
        'agente': find.byKey(const ValueKey('tool-agent')),
        'web': find.byKey(const ValueKey('tool-web')),
        'fila': find.byKey(const ValueKey('tool-queue')),
        'zoom −': find.byKey(const ValueKey('zoom-out')),
        'zoom +': find.byKey(const ValueKey('zoom-in')),
        'número do zoom': find.byKey(const ValueKey('zoom-label')),
        'enquadrar': find.byKey(const ValueKey('fit-all')),
        'fechar card': find.descendant(
          of: card('a'),
          matching: find.byKey(const ValueKey('card-close')),
        ),
        'porta +': find.descendant(
          of: card('a'),
          matching: find.byKey(const ValueKey('card-port')),
        ),
      };
      for (final entry in clickable.entries) {
        expect(
          await cursorOver(tester, tester.getCenter(entry.value)),
          SystemMouseCursors.click,
          reason: '${entry.key} responde a clique e não diz nada ao ponteiro',
        );
      }
      // A régua presta: o fundo vazio não ganha mão.
      expect(
        await cursorOver(tester, const Offset(600, 790)),
        isNot(SystemMouseCursors.click),
      );
    });

    testWidgets('os controles da ligação também ganham a mão', (tester) async {
      final repo = InMemoryCanvasRepository(
        cards: cards,
        links: const [EdgeLink(a: 'a', b: 'b')],
      );
      await pumpCanvas(tester, repo);
      final a = screenRect(tester, card('a'));
      final b = screenRect(tester, card('b'));
      await cursorOver(tester, Offset((a.right + b.left) / 2, a.center.dy));
      for (final (name, finder) in [
        ('→', find.text('→')),
        ('limite', find.widgetWithText(EdgeLabel, '2')),
      ]) {
        expect(
          await cursorOver(tester, tester.getCenter(finder)),
          SystemMouseCursors.click,
          reason: '$name responde a clique',
        );
      }
    });

    testWidgets(
      'o cabeçalho do card é seta (ADR-048: se arrasta), e a alça é de arrastar',
      (tester) async {
        final repo = InMemoryCanvasRepository(cards: cards, links: const []);
        await pumpCanvas(tester, repo);
        final rect = screenRect(tester, card('a'));
        expect(
          await cursorOver(tester, rect.topLeft + const Offset(80, 8)),
          SystemMouseCursors.basic,
        );
        expect(
          await cursorOver(tester, rect.bottomRight - const Offset(4, 4)),
          SystemMouseCursors.precise,
        );
      },
    );

    testWidgets('com a ferramenta armada, o cursor é de mira', (tester) async {
      final repo = InMemoryCanvasRepository(cards: cards, links: const []);
      await pumpCanvas(tester, repo);
      await tester.tap(find.byKey(const ValueKey('tool-web')));
      await tester.pump();
      expect(
        await cursorOver(tester, const Offset(600, 500)),
        SystemMouseCursors.precise,
      );
    });
  });
}
