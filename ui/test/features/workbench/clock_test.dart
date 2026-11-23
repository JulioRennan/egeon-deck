import 'package:egeon_deck/core/domain/entities/workbench_clock.dart';
import 'package:flutter_test/flutter_test.dart';

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

  test('a dica traz os três tempos', () {
    const clock = WorkbenchClock(running: 3725, waiting: 61, failed: 5);
    expect(
      clock.tooltip,
      'rodando 1:02:05 · esperando você 01:01 · em erro 00:05',
    );
  });
}
