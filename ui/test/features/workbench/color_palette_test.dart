import 'package:egeon_deck/features/workbench/presentation/widgets/color_palette_dialog.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/hand_cursor.dart';
import '../../support/overlay_host.dart';

void main() {
  testWidgets('a grade tem as 24 cores e a atual vem legendada', (
    tester,
  ) async {
    await tester.pumpWidget(
      overlayHost(
        Builder(
          builder: (context) => MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => showColorPalette(context, current: 'sand'),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pump();

    expect(find.byKey(const ValueKey('swatch-red')), findsOneWidget);
    expect(find.byKey(const ValueKey('swatch-grey')), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey &&
            '${(w.key! as ValueKey).value}'.startsWith('swatch-'),
      ),
      findsNWidgets(24),
    );
    expect(find.text('Areia'), findsOneWidget, reason: 'a cor atual legendada');
    expectHandOnEveryClickable(tester);
  });

  testWidgets('passar o ponteiro legenda a cor, e escolher a devolve', (
    tester,
  ) async {
    String? picked;
    await tester.pumpWidget(
      overlayHost(
        Builder(
          builder: (context) => GestureDetector(
            onTap: () async => picked = await showColorPalette(context),
            child: const Text('abrir'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pump();

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(
      location: tester.getCenter(find.byKey(const ValueKey('swatch-violet'))),
    );
    await tester.pump();
    expect(find.text('Violeta'), findsOneWidget);
    await mouse.removePointer();

    await tester.tap(find.byKey(const ValueKey('swatch-violet')));
    await tester.pump();
    expect(picked, 'violet');
    expect(find.byKey(const ValueKey('swatch-violet')), findsNothing);
  });
}
