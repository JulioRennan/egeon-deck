import 'package:egeon_deck/features/workbench/presentation/widgets/color_palette_dialog.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/hand_cursor.dart';
import '../../support/overlay_host.dart';

Finder swatch(String label) => find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.label == label,
);

Future<void> open(WidgetTester tester, {String? current}) async {
  await tester.pumpWidget(
    overlayHost(
      Builder(
        builder: (context) => MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () =>
                showColorPalette(context, benchName: 'deck', current: current),
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('a grade tem as 12 cores e o título leva o nome da bancada', (
    tester,
  ) async {
    await open(tester, current: 'sky');
    expect(find.text('Cor da bancada'), findsOneWidget);
    expect(find.text('deck'), findsOneWidget);
    for (final name in [
      'Sky', 'Slate', 'Iris', 'Orchid', 'Mauve', 'Rose', //
      'Clay', 'Sand', 'Olive', 'Moss', 'Jade', 'Teal',
    ]) {
      expect(swatch(name), findsOneWidget, reason: name);
    }
    expectHandOnEveryClickable(tester);
  });

  testWidgets('escolher devolve o nome que o core grava', (tester) async {
    String? picked;
    await tester.pumpWidget(
      overlayHost(
        Builder(
          builder: (context) => GestureDetector(
            onTap: () async =>
                picked = await showColorPalette(context, benchName: 'deck'),
            child: const Text('abrir'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(swatch('Rose'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(picked, 'red');
  });

  testWidgets('Cancelar fecha sem escolher', (tester) async {
    await open(tester);
    await tester.tap(find.text('Cancelar'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Cor da bancada'), findsNothing);
  });
}
