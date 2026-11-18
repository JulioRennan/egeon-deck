/// O seletor de esforço como o core o descreve: a UI só desenha as marcas, a
/// posição e o texto que ele manda, e devolve o gesto. A regra (auto como
/// interruptor, nível fora da lista, "…" enquanto não assenta) é do core.
class EffortDialView {
  const EffortDialView({
    this.levels = const [],
    this.markIndex = 0,
    this.auto = true,
    this.pending = false,
    this.label = '',
  });

  /// Uma marca por nível, do menor para o maior. Vazio é modelo sem esforço: o
  /// slider fica desligado.
  final List<String> levels;

  /// Onde a marca fica: a escolha, senão a do auto.
  final int markIndex;

  /// Em auto a barra mostra, apagada, o nível que o modelo usa.
  final bool auto;

  /// A escolha ainda não assentou.
  final bool pending;

  /// O texto ao lado da barra, já com o "…" quando falta assentar.
  final String label;

  bool get usable => levels.isNotEmpty;

  factory EffortDialView.fromMap(Map<String, Object?> map) => EffortDialView(
    levels: [
      for (final l in (map['levels'] as List<Object?>? ?? const []))
        l! as String,
    ],
    markIndex: (map['index'] as num?)?.toInt() ?? 0,
    auto: map['auto'] as bool? ?? true,
    pending: map['pending'] as bool? ?? false,
    label: map['label'] as String? ?? '',
  );

  Map<String, Object?> toMap() => {
    'levels': levels,
    'index': markIndex,
    'auto': auto,
    'pending': pending,
    'label': label,
  };
}
