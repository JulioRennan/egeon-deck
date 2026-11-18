import 'package:egeon_deck/features/node/agent/domain/entities/context_reading.dart';
import 'package:egeon_deck/features/node/agent/presentation/widgets/context_indicator.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Porte de testIndicatorWithoutReadingShowsADash.
void main() {
  Future<void> pumpIndicator(WidgetTester tester, ContextReading? reading) =>
      tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: ContextIndicator(reading: reading),
          ),
        ),
      );

  String text(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const ValueKey('context-text'))).data!;

  testWidgets('sem leitura mostra um travessão; com leitura, a porcentagem', (
    tester,
  ) async {
    await pumpIndicator(tester, null);
    expect(text(tester), '—');

    await pumpIndicator(
      tester,
      const ContextReading(used: 500000, window: 1000000),
    );
    expect(text(tester), '50%');
    expect(
      tester.getSize(find.byType(ContextIndicator)).width,
      greaterThan(12),
    );

    await pumpIndicator(tester, null);
    expect(text(tester), '—');
  });
}
