/// Os avisos de uma bancada: quantos agentes trabalham, esperam por você ou
/// terminaram. Chega pronto do core Rust; a UI só mostra.
class ActivitySummary {
  const ActivitySummary({
    this.starting = 0,
    this.working = 0,
    this.background = 0,
    this.attention = 0,
    this.done = 0,
  });

  static const none = ActivitySummary();

  final int starting;
  final int working;
  final int background;
  final int attention;
  final int done;

  bool get isWorking => working > 0 || starting > 0;
  bool get wantsAttention => attention > 0;

  /// Só terminais subindo, nada mais a dizer: é a bancada se preparando.
  bool get isPreparing =>
      starting > 0 &&
      working == 0 &&
      background == 0 &&
      attention == 0 &&
      done == 0;

  factory ActivitySummary.fromMap(Map<String, Object?> map) => ActivitySummary(
    starting: map['starting'] as int? ?? 0,
    working: map['working'] as int? ?? 0,
    background: map['background'] as int? ?? 0,
    attention: map['attention'] as int? ?? 0,
    done: map['done'] as int? ?? 0,
  );

  Map<String, Object?> toMap() => {
    'starting': starting,
    'working': working,
    'background': background,
    'attention': attention,
    'done': done,
  };

  @override
  bool operator ==(Object other) =>
      other is ActivitySummary &&
      other.starting == starting &&
      other.working == working &&
      other.background == background &&
      other.attention == attention &&
      other.done == done;

  @override
  int get hashCode =>
      Object.hash(starting, working, background, attention, done);
}
