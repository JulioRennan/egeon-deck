import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/hand_cursor.dart';

// A régua do teste presta: clicável sem ponteiro de mão é pego, e com a mão
// passa (o controle de HandCursorTests.swift).
void main() {
  testWidgets('pega o clicável sem cursor e deixa passar o que tem a mão', (
    tester,
  ) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: GestureDetector(
          onTap: () {},
          child: const SizedBox(width: 9, height: 9),
        ),
      ),
    );
    expect(
      () => expectHandOnEveryClickable(tester),
      throwsA(isA<TestFailure>()),
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () {},
            child: const SizedBox(width: 9, height: 9),
          ),
        ),
      ),
    );
    expectHandOnEveryClickable(tester);
  });
}
