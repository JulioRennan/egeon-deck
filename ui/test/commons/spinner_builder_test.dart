import 'package:egeon_deck/commons/widgets/spinner.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('o spinner gira sozinho, com o relógio do quadro', (
    tester,
  ) async {
    final seen = <String>{};
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SpinnerBuilder(
          builder: (context, glyph) {
            seen.add(glyph);
            return Text(glyph);
          },
        ),
      ),
    );
    // O glifo sai do relógio de parede; o quadro vem do ticker.
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(SpinnerGlyph.frameDuration),
      );
      await tester.pump(SpinnerGlyph.frameDuration);
    }
    expect(seen.length, greaterThan(1), reason: 'o ticker liga no initState');
  });

  testWidgets('sair da tela solta o ticker sem erro', (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SpinnerBuilder(builder: (_, glyph) => Text(glyph)),
      ),
    );
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}
