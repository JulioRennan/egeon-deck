/// As três fases do cronômetro de uma bancada.
enum ClockPhase {
  running('running'),
  waiting('waiting'),
  failed('failed');

  const ClockPhase(this.wire);

  final String wire;

  static ClockPhase? fromWire(Object? raw) {
    for (final phase in values) {
      if (phase.wire == raw) return phase;
    }
    return null;
  }
}

/// O tempo que a bancada passou rodando, esperando você e em erro, e quais
/// dessas fases estão andando agora. A conta é do core Rust; a UI só formata.
class WorkbenchClock {
  const WorkbenchClock({
    this.running = 0,
    this.waiting = 0,
    this.failed = 0,
    this.ticking = const {},
  });

  final double running;
  final double waiting;
  final double failed;

  /// As fases que estão contando neste instante.
  final Set<ClockPhase> ticking;

  double of(ClockPhase phase) => switch (phase) {
    ClockPhase.running => running,
    ClockPhase.waiting => waiting,
    ClockPhase.failed => failed,
  };

  /// `mm:ss`, ou `h:mm:ss` a partir de uma hora.
  static String format(double seconds) {
    final total = seconds < 0 ? 0 : seconds.floor();
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  factory WorkbenchClock.fromMap(Map<String, Object?> map) => WorkbenchClock(
    running: (map['running'] as num?)?.toDouble() ?? 0,
    waiting: (map['waiting'] as num?)?.toDouble() ?? 0,
    failed: (map['failed'] as num?)?.toDouble() ?? 0,
    ticking: {
      for (final raw in (map['ticking'] as List<Object?>? ?? const []))
        ?ClockPhase.fromWire(raw),
    },
  );

  /// O que aparece ao parar o ponteiro em cima.
  String get tooltip =>
      'rodando ${format(running)} · esperando você ${format(waiting)} · '
      'em erro ${format(failed)}';

  @override
  bool operator ==(Object other) =>
      other is WorkbenchClock &&
      other.running.floor() == running.floor() &&
      other.waiting.floor() == waiting.floor() &&
      other.failed.floor() == failed.floor() &&
      other.ticking.length == ticking.length &&
      other.ticking.containsAll(ticking);

  @override
  int get hashCode => Object.hash(
    running.floor(),
    waiting.floor(),
    failed.floor(),
    ticking.length,
  );
}
