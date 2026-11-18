import 'package:egeon_deck/core/domain/entities/workbench_clock.dart';
import 'package:egeon_deck/features/workbench/presentation/widgets/clock_chip.dart';
import 'package:egeon_deck/features/workbench/presentation/widgets/clock_text.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/overlay_host.dart';

void main() {
  // Porte de testFormat de WorkbenchClockTests.swift: o resto daquele arquivo
  // (fases, acúmulo, arquivo) é a conta do core.
  test('o formato é mm:ss, e h:mm:ss a partir de uma hora', () {
    expect(WorkbenchClock.format(0), '00:00');
    expect(WorkbenchClock.format(59.9), '00:59');
    expect(WorkbenchClock.format(61), '01:01');
    expect(WorkbenchClock.format(3599), '59:59');
    expect(WorkbenchClock.format(3600 + 5 * 60 + 12), '1:05:12');
    expect(WorkbenchClock.format(-4), '00:00');
  });

  test('o relógio lê o que o core manda', () {
    final clock = WorkbenchClock.fromMap({
      'running': 754,
      'waiting': 120,
      'failed': 0,
      'ticking': ['running'],
    });
    expect(clock.running, 754);
    expect(clock.waiting, 120);
    expect(clock.failed, 0);
    expect(clock.ticking, {ClockPhase.running});
    expect(WorkbenchClock.fromMap(const {}).ticking, isEmpty);
  });

  test('o texto e a dica trazem os três tempos', () {
    const clock = WorkbenchClock(running: 3725, waiting: 61, failed: 5);
    expect(ClockText.plain(clock), '⚒︎ 1:02:05   ✋︎ 01:01   ⊗ 00:05');
    expect(
      clock.tooltip,
      'rodando 1:02:05 · esperando você 01:01 · em erro 00:05',
    );
  });

  testWidgets('a fase que anda fica em negrito', (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: const ClockText(
          WorkbenchClock(running: 1, ticking: {ClockPhase.running}),
        ),
      ),
    );
    final weights = <FontWeight?>[];
    tester.widget<RichText>(find.byType(RichText)).text.visitChildren((span) {
      if (span is TextSpan && (span.text ?? '').trim().isNotEmpty) {
        weights.add(span.style!.fontWeight);
      }
      return true;
    });
    expect(weights, [FontWeight.w700, FontWeight.w500, FontWeight.w500]);
  });

  testWidgets('clicar na pastilha oferece zerar', (tester) async {
    var resets = 0;
    await tester.pumpWidget(
      overlayHost(
        Center(
          child: ClockChip(
            clock: const WorkbenchClock(running: 5),
            onReset: () => resets++,
          ),
        ),
      ),
    );
    await tester.tap(find.byType(ClockChip));
    await tester.pump();
    await tester.tap(find.text('Zerar cronômetro'));
    expect(resets, 1);
  });
}
