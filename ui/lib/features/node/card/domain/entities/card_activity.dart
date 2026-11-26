/// O glifo do cabeçalho: a animação é da UI, o que mostrar é do core.
enum ActivityGlyph {
  spinner,
  hourglass,
  dot,
  retry,
  cross;

  static ActivityGlyph? parse(Object? raw) {
    for (final glyph in values) {
      if (glyph.name == raw) return glyph;
    }
    return null;
  }
}

/// O tom do estado. Ausente, o título fica com o acento do tipo e o texto com
/// o cinza de sempre.
enum ActivityTone {
  green,
  orange,
  red;

  static ActivityTone? parse(Object? raw) {
    for (final tone in values) {
      if (tone.name == raw) return tone;
    }
    return null;
  }
}

/// O que o agente está fazendo, como o core diz — o cabeçalho vem pronto. A
/// borda acende por [needsAttention]; a regra de quando acender é do core, não
/// se repete aqui.
class CardActivity {
  const CardActivity({
    this.state = '',
    this.needsAttention = false,
    this.label,
    this.glyph,
    this.tone,
    this.pending = 0,
    this.waitingOn = const [],
    this.error,
    this.attempt,
  });

  static const none = CardActivity();

  final String state;
  final bool needsAttention;

  /// "trabalhando", "precisa de você", "tentando de novo às 14:05 (2/3)"…
  final String? label;
  final ActivityGlyph? glyph;
  final ActivityTone? tone;

  /// Prompts na fila do agente: o "N na fila".
  final int pending;

  /// Em `awaiting`: os vizinhos que ainda não responderam. Lista no fio — lida
  /// como texto, derrubava a bancada inteira e o canvas ficava vazio.
  final List<String> waitingOn;
  final String? error;
  final int? attempt;

  factory CardActivity.fromMap(Map<String, Object?>? map) => map == null
      ? none
      : CardActivity(
          state: map['state'] as String? ?? '',
          needsAttention: map['needs_attention'] as bool? ?? false,
          label: map['label'] as String?,
          glyph: ActivityGlyph.parse(map['glyph']),
          tone: ActivityTone.parse(map['tone']),
          pending: (map['pending'] as num?)?.toInt() ?? 0,
          waitingOn: [
            for (final peer in map['waiting_on'] as List<Object?>? ?? const [])
              ?peer as String?,
          ],
          error: map['error'] as String?,
          attempt: (map['attempt'] as num?)?.toInt(),
        );

  /// O texto do cabeçalho, como o Swift o junta: "rótulo  ·  N na fila". Vazio
  /// quando não há o que dizer.
  String get text =>
      [?label, if (pending > 0) '$pending na fila'].join('  ·  ');
}
