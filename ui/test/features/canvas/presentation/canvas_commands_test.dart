import 'package:egeon_deck/core/domain/entities/workbench_node.dart';
import 'package:egeon_deck/features/canvas/domain/entities/canvas_card.dart';
import 'package:egeon_deck/features/canvas/domain/entities/canvas_tool.dart';
import 'package:egeon_deck/features/canvas/presentation/cubit/canvas_commands.dart';
import 'package:egeon_deck/features/canvas/presentation/widgets/tool_overlay.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/in_memory_canvas_repository.dart';
import '../../../support/pump_canvas.dart';

class _TwoCards extends InMemoryCanvasRepository {
  _TwoCards()
    : super(
        cards: const [
          CanvasCard(
            id: 'a',
            kind: NodeKind.shell,
            frame: Rect.fromLTWH(1000, 900, 600, 400),
          ),
          CanvasCard(
            id: 'b',
            kind: NodeKind.shell,
            frame: Rect.fromLTWH(1700, 900, 600, 400),
          ),
        ],
        links: const [],
      );
}

/// O menu "Canvas" da casca: ferramentas e zoom chamados de fora.
void main() {
  String zoomLabel(WidgetTester tester) => tester
      .widget<Text>(
        find.descendant(
          of: find.byKey(const ValueKey('zoom-label')),
          matching: find.byType(Text),
        ),
      )
      .data!;

  testWidgets('liga ao nascer, solta ao sair; sem canvas não faz nada', (
    tester,
  ) async {
    final commands = CanvasCommands();
    expect(commands.attached, isFalse);
    commands.zoomIn(); // sem canvas: nada acontece, nada quebra

    await pumpCanvas(tester, InMemoryCanvasRepository(), commands: commands);
    expect(commands.attached, isTrue);

    await tester.pumpWidget(const SizedBox());
    expect(commands.attached, isFalse);
  });

  testWidgets('as ferramentas do menu armam o próximo clique', (tester) async {
    final commands = CanvasCommands();
    await pumpCanvas(tester, InMemoryCanvasRepository(), commands: commands);

    commands.selectTool(CanvasTool.terminal);
    await tester.pump();
    await tester.pump();
    expect(find.byType(ToolOverlay), findsOneWidget);

    commands.selectTool(CanvasTool.cursor);
    await tester.pump();
    await tester.pump();
    expect(find.byType(ToolOverlay), findsNothing);

    commands.selectTool(CanvasTool.web);
    await tester.pump();
    await tester.pump();
    expect(find.byType(ToolOverlay), findsOneWidget);
  });

  testWidgets('aproximar, afastar e 100% andam pelos passos', (tester) async {
    final commands = CanvasCommands();
    await pumpCanvas(tester, InMemoryCanvasRepository(), commands: commands);

    commands.resetZoom();
    await tester.pump();
    await tester.pump();
    expect(zoomLabel(tester), '100%');
    commands.zoomIn();
    await tester.pump();
    await tester.pump();
    expect(zoomLabel(tester), '125%');
    commands.zoomOut();
    commands.zoomOut();
    await tester.pump();
    await tester.pump();
    expect(zoomLabel(tester), '80%');
    commands.resetZoom();
    await tester.pump();
    await tester.pump();
    expect(zoomLabel(tester), '100%');
  });

  testWidgets('enquadrar tudo traz os nós para a janela', (tester) async {
    final commands = CanvasCommands();
    await pumpCanvas(tester, InMemoryCanvasRepository(), commands: commands);
    commands.resetZoom();
    commands.fitAll();
    await tester.pump();
    await tester.pump();
    expect(zoomLabel(tester), isNot('100%'));
  });

  group('enquadrar desconta a barra lateral flutuante', () {
    Offset centerOf(WidgetTester tester) {
      final a = tester.getCenter(find.byKey(const ValueKey('card-a')));
      final b = tester.getCenter(find.byKey(const ValueKey('card-b')));
      return Offset.lerp(a, b, 0.5)!;
    }

    testWidgets('com 300 de barra, o conteúdo centra no que sobra', (
      tester,
    ) async {
      final commands = CanvasCommands();
      await pumpCanvas(
        tester,
        _TwoCards(),
        commands: commands,
        sidebarInset: 300,
      );
      commands.fitAll();
      await tester.pump();
      await tester.pump();
      // Janela de 1200: sem barra o centro cai em 600; com 300, em 750.
      expect(centerOf(tester).dx, closeTo((300 + 1200) / 2, 2));
    });

    testWidgets('o enquadramento inicial já desconta a barra', (tester) async {
      await pumpCanvas(tester, _TwoCards(), sidebarInset: 300);
      await tester.pump();
      await tester.pump();
      expect(centerOf(tester).dx, closeTo((300 + 1200) / 2, 2));
    });

    testWidgets('mudar a barra muda o enquadrar seguinte', (tester) async {
      final commands = CanvasCommands();
      await pumpCanvas(tester, _TwoCards(), commands: commands);
      commands.fitAll();
      await tester.pump();
      await tester.pump();
      expect(centerOf(tester).dx, closeTo(600, 2));
    });
  });

  group('a porta de ligação vem do core', () {
    testWidgets('shell sem destino livre mantém a porta; o web não tem', (
      tester,
    ) async {
      await pumpCanvas(
        tester,
        InMemoryCanvasRepository(
          cards: const [
            CanvasCard(
              id: 'so',
              kind: NodeKind.shell,
              frame: Rect.fromLTWH(1000, 900, 600, 400),
              port: true,
            ),
            CanvasCard(
              id: 'w',
              kind: NodeKind.web,
              frame: Rect.fromLTWH(1700, 900, 600, 400),
            ),
          ],
          links: const [],
        ),
      );
      // O fake do core dá `port` aos que não são web, e destino só entre
      // terminais: o shell sozinho não tem para onde ligar, mas tem porta.
      expect(find.byKey(const ValueKey('port-so')), findsOneWidget);
      expect(find.byKey(const ValueKey('port-w')), findsNothing);
    });
  });
}
