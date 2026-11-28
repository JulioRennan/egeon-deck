import 'package:egeon_deck/features/canvas/domain/entities/canvas_card.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind, kSecondaryButton;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/in_memory_canvas_repository.dart';
import '../../../support/pump_canvas.dart';

/// Onde o formulário de terminal se abre a partir do canvas: o lápis do card,
/// o menu do botão Terminal e o terminal solto sem componente.
void main() {
  testWidgets('só o card de terminal tem o lápis, e ele pede o formulário', (
    tester,
  ) async {
    final asked = <String>[];
    await pumpCanvas(
      tester,
      InMemoryCanvasRepository(),
      onRequestConfigure: (CanvasCard card) => asked.add(card.id),
    );
    Finder pencil(String id) => find.descendant(
      of: find.byKey(ValueKey('card-$id')),
      matching: find.byKey(const ValueKey('card-configure')),
    );
    expect(pencil('sh1'), findsOneWidget);
    expect(pencil('claude'), findsOneWidget);
    expect(pencil('web1'), findsNothing);

    await tester.tap(pencil('claude'));
    await tester.pump();
    expect(asked, ['claude']);
  });

  testWidgets('o botão direito no cabeçalho oferece configurar e remover', (
    tester,
  ) async {
    final asked = <String>[];
    await pumpCanvas(
      tester,
      InMemoryCanvasRepository(),
      onRequestConfigure: (CanvasCard card) => asked.add(card.id),
    );
    final header = tester.getTopLeft(find.byKey(const ValueKey('card-sh1')));
    await tester.tapAt(
      header + const Offset(40, 12),
      buttons: kSecondaryButton,
    );
    await tester.pump();
    expect(find.text('Configurar sh1…'), findsOneWidget);
    expect(find.text('Remover sh1…'), findsOneWidget);
    await tester.tap(find.text('Configurar sh1…'));
    await tester.pump();
    expect(asked, ['sh1']);
  });

  testWidgets('segurar o Terminal lista os componentes salvos na hora', (
    tester,
  ) async {
    final configured = <Rect>[];
    await pumpCanvas(
      tester,
      InMemoryCanvasRepository(),
      componentNames: const ['revisor', 'build'],
      onConfigureTerminal: configured.add,
    );
    await tester.longPress(find.byKey(const ValueKey('tool-agent')));
    await tester.pump();
    await tester.pump();
    expect(find.text('Componentes salvos'), findsOneWidget);
    expect(find.text('revisor'), findsOneWidget);
    expect(find.text('build'), findsOneWidget);
    await tester.tap(find.text('Configurar novo terminal…'));
    await tester.pump();
    // O que está à vista, no espaço do canvas: é onde o core põe o nó.
    expect(configured.single.isEmpty, isFalse);
  });

  testWidgets('terminal solto sem componente abre o formulário naquele lugar', (
    tester,
  ) async {
    final asked = <Rect>[];
    final repo = InMemoryCanvasRepository();
    await pumpCanvas(tester, repo, onConfigureTerminalAt: asked.add);

    await tester.tap(find.byKey(const ValueKey('tool-agent')));
    await tester.pump();
    await tester.tapAt(const Offset(600, 600));
    await tester.pump();
    await tester.pump();

    expect(asked, hasLength(1));
    // O repositório falso chama o terminal novo de `sh`: ele não nasceu.
    expect(find.byKey(const ValueKey('card-sh')), findsNothing);
  });

  testWidgets('o botão direito no Terminal abre o mesmo menu do segurar', (
    tester,
  ) async {
    await pumpCanvas(
      tester,
      InMemoryCanvasRepository(),
      componentNames: const ['revisor'],
    );
    await tester.tap(
      find.byKey(const ValueKey('tool-agent')),
      buttons: kSecondaryButton,
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Componentes salvos'), findsOneWidget);
    expect(find.text('revisor'), findsOneWidget);
  });

  testWidgets('parar o mouse num botão da barra mostra a dica, sem atalho', (
    tester,
  ) async {
    await pumpCanvas(tester, InMemoryCanvasRepository());
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(
      tester.getCenter(find.byKey(const ValueKey('tool-agent'))),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Terminal de agente'), findsOneWidget);
  });
}
