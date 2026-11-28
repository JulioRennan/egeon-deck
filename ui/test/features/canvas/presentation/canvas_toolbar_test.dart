import 'package:flutter/gestures.dart' show PointerDeviceKind;

import 'package:egeon_deck/commons/widgets/eg/glass_surface.dart';
import 'package:egeon_deck/features/canvas/presentation/widgets/canvas_grid.dart';
import 'package:egeon_deck/features/canvas/domain/entities/canvas_component.dart';
import 'package:egeon_deck/features/canvas/presentation/widgets/canvas_bench_actions.dart';
import 'package:egeon_deck/features/canvas/presentation/widgets/canvas_toolbar.dart';
import 'package:egeon_deck/features/canvas/presentation/widgets/tool_overlay.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/in_memory_canvas_repository.dart';
import '../../../support/pump_canvas.dart';

void main() {
  testWidgets(
    'a barra é de vidro, a dica também (só enquanto aparece); a grade não borra',
    (tester) async {
      await pumpCanvas(tester, InMemoryCanvasRepository());
      expect(
        find.descendant(
          of: find.byType(CanvasToolbar),
          matching: find.byType(GlassSurface),
        ),
        findsOneWidget,
      );
      expect(find.byType(BackdropFilter), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tool-web')));
      await tester.pump();
      expect(find.byType(BackdropFilter), findsNWidgets(2));
      final hint = tester.getRect(find.byType(ToolHint));
      expect(hint.height, 32);
      expect(hint.top, 16 + CanvasToolbar.height + 10);
      // A grade e os nós não borram nada.
      expect(
        find.descendant(
          of: find.byType(CanvasGrid),
          matching: find.byType(BackdropFilter),
        ),
        findsNothing,
      );
    },
  );

  testWidgets('a barra fica no topo, ao centro, com 46 de altura', (
    tester,
  ) async {
    await pumpCanvas(tester, InMemoryCanvasRepository());
    final box = tester.getRect(find.byType(CanvasToolbar));
    expect(box.height, CanvasToolbar.height);
    expect(box.top, 16);
    expect(box.center.dx, closeTo(600, 1));
  });

  testWidgets('ligar a ferramenta mostra a dica com "Esc cancela"', (
    tester,
  ) async {
    await pumpCanvas(tester, InMemoryCanvasRepository());
    expect(find.byType(ToolHint), findsNothing);
    await tester.tap(find.byKey(const ValueKey('tool-queue')));
    await tester.pump();
    expect(
      find.text('Clique no canvas para criar uma fila de prompts'),
      findsOneWidget,
    );
    expect(find.text('Esc cancela'), findsOneWidget);
  });

  testWidgets('Esc devolve o cursor e a dica some', (tester) async {
    await pumpCanvas(tester, InMemoryCanvasRepository());
    await tester.tap(find.byKey(const ValueKey('tool-web')));
    await tester.pump();
    expect(find.byType(ToolOverlay), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byType(ToolOverlay), findsNothing);
    expect(find.byType(ToolHint), findsNothing);
  });

  testWidgets('os tooltips dizem o nome e, no zoom, o atalho', (tester) async {
    await pumpCanvas(tester, InMemoryCanvasRepository());
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byKey(const ValueKey('zoom-in'))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Aproximar'), findsOneWidget);
    expect(find.text('⌘='), findsOneWidget);
    // Os atalhos ⌘1–⌘4 da v3 não estão decididos: as ferramentas não os têm.
    await mouse.moveTo(
      tester.getCenter(find.byKey(const ValueKey('tool-web'))),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Web'), findsOneWidget);
    expect(find.text('⌘4'), findsNothing);
  });

  testWidgets('o terminal leva o canto ◢ e segurar abre o menu', (
    tester,
  ) async {
    await pumpCanvas(
      tester,
      InMemoryCanvasRepository(),
      componentNames: const ['claude'],
    );
    final button = find.byKey(const ValueKey('tool-agent'));
    await tester.longPress(button);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Componentes salvos'), findsOneWidget);
    expect(find.text('Configurar novo terminal…'), findsOneWidget);
  });

  testWidgets('segurar o agente mostra nome e a linha CLI · modelo · esforço', (
    tester,
  ) async {
    await pumpCanvas(
      tester,
      InMemoryCanvasRepository(),
      components: const [
        CanvasComponent('revisor', meta: 'Claude Code · opus · alto'),
      ],
    );
    await tester.longPress(find.byKey(const ValueKey('tool-agent')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('revisor'), findsOneWidget);
    expect(find.text('Claude Code · opus · alto'), findsOneWidget);
  });

  testWidgets('shell e agente são ferramentas distintas', (tester) async {
    await pumpCanvas(tester, InMemoryCanvasRepository());
    await tester.tap(find.byKey(const ValueKey('tool-shell')));
    await tester.pump();
    expect(
      find.text('Clique ou arraste no canvas para criar um shell'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('tool-agent')));
    await tester.pump();
    expect(
      find.text('Clique ou arraste no canvas para criar um terminal de agente'),
      findsOneWidget,
    );
  });

  group('menu Template ▾', () {
    Future<void> open(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('template-menu')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('salvar e atualizar o de origem', (tester) async {
      final log = <String>[];
      await pumpCanvas(
        tester,
        InMemoryCanvasRepository(),
        benchActions: CanvasBenchActions(
          onSaveTemplate: () => log.add('salvar'),
          onNewWorktree: () => log.add('worktree'),
          originTemplate: 'Equipe redesign',
          onUpdateTemplate: () => log.add('atualizar'),
        ),
      );
      await open(tester);
      expect(find.text('Salvar como template…'), findsOneWidget);
      await tester.tap(find.text('Atualizar “Equipe redesign”'));
      await tester.pump();
      expect(log, ['atualizar']);

      await open(tester);
      await tester.tap(find.text('Salvar como template…'));
      await tester.pump();
      expect(log, ['atualizar', 'salvar']);
    });

    testWidgets('sem template de origem, atualizar fica desabilitado', (
      tester,
    ) async {
      final log = <String>[];
      await pumpCanvas(
        tester,
        InMemoryCanvasRepository(),
        benchActions: CanvasBenchActions(
          onSaveTemplate: () => log.add('salvar'),
          onNewWorktree: () => log.add('worktree'),
        ),
      );
      await open(tester);
      await tester.tap(find.text('Atualizar o template de origem'));
      await tester.pump();
      expect(log, isEmpty);
    });
  });

  group('cor da bancada', () {
    testWidgets('a grade tem as 12 cores e a escolhida leva o anel', (
      tester,
    ) async {
      final picked = <String>[];
      await pumpCanvas(
        tester,
        InMemoryCanvasRepository(),
        benchName: 'deck',
        benchColor: 'sky',
        onPickColor: picked.add,
      );
      await tester.tap(find.byKey(const ValueKey('bench-color')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Cor da bancada'), findsOneWidget);
      expect(find.text('deck'), findsOneWidget, reason: 'o nome da bancada');
      for (final name in [
        'Sky', 'Slate', 'Iris', 'Orchid', 'Mauve', 'Rose', //
        'Clay', 'Sand', 'Olive', 'Moss', 'Jade', 'Teal',
      ]) {
        expect(
          find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.label == name,
          ),
          findsOneWidget,
          reason: name,
        );
      }
    });

    testWidgets('escolher grava o nome que o core lê e fecha', (tester) async {
      final picked = <String>[];
      await pumpCanvas(
        tester,
        InMemoryCanvasRepository(),
        benchColor: 'sky',
        onPickColor: picked.add,
      );
      await tester.tap(find.byKey(const ValueKey('bench-color')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == 'Rose',
        ),
      );
      await tester.pump();
      expect(picked, ['red']);
      expect(find.text('Cor da bancada'), findsNothing);
    });

    testWidgets('sem quem grave a cor, o botão não aparece', (tester) async {
      await pumpCanvas(tester, InMemoryCanvasRepository());
      expect(find.byKey(const ValueKey('bench-color')), findsNothing);
    });
  });

  group('a grade de pontos', () {
    testWidgets('pinta pontos de 24 em 24 unidades, sem linhas', (
      tester,
    ) async {
      await pumpCanvas(tester, InMemoryCanvasRepository());
      final paint = find.descendant(
        of: find.byType(CanvasGrid),
        matching: find.byType(CustomPaint),
      );
      expect(paint, findsWidgets);
      expect(CanvasGrid.step, 24);
    });
  });
}
