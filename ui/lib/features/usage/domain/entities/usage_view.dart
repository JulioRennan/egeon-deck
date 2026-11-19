/// A pastilha do custo da bancada (ADR-085): o texto e o que o ponteiro diz.
class UsagePillView {
  const UsagePillView({this.text = 'US\$ —', this.tooltip, this.empty = false});

  final String text;
  final String? tooltip;

  /// Nada consumido ainda: a barra lateral não mostra custo.
  final bool empty;

  factory UsagePillView.fromMap(Map<String, Object?>? map) => UsagePillView(
    text: map?['text'] as String? ?? 'US\$ —',
    tooltip: map?['tooltip'] as String?,
    empty: map?['empty'] as bool? ?? false,
  );
}

/// As quatro tarifas, as mesmas na barra e na legenda.
enum Tariff {
  output('output'),
  input('input'),
  cacheWrite('cache_write'),
  cacheRead('cache_read');

  const Tariff(this.wire);

  final String wire;

  static Tariff? parse(Object? raw) {
    for (final tariff in values) {
      if (tariff.wire == raw) return tariff;
    }
    return null;
  }
}

/// Uma tarifa: quanto custou e quantos tokens foram.
class TariffShare {
  const TariffShare({
    required this.tariff,
    required this.title,
    required this.amount,
    required this.detail,
    required this.dollars,
  });

  final Tariff tariff;
  final String title;
  final String amount;
  final String detail;

  /// O valor numérico, só para o tamanho do pedaço da barra.
  final double dollars;

  factory TariffShare.fromMap(Map<String, Object?> map) => TariffShare(
    tariff: Tariff.parse(map['key']) ?? Tariff.output,
    title: map['title'] as String? ?? '',
    amount: map['amount'] as String? ?? '',
    detail: map['detail'] as String? ?? '',
    dollars: (map['dollars'] as num?)?.toDouble() ?? 0,
  );
}

/// Uma linha de agente ou de modelo, com a barra proporcional ao maior.
class UsageRow {
  const UsageRow({
    required this.name,
    required this.amount,
    required this.fraction,
    required this.detail,
    this.tag,
    this.family,
  });

  final String name;

  /// O modelo principal do agente.
  final String? tag;
  final String amount;

  /// De 0 a 1, em relação ao maior da lista.
  final double fraction;
  final String detail;

  /// A família do modelo (`opus`, `sonnet`…), que escolhe a cor.
  final String? family;

  factory UsageRow.fromMap(Map<String, Object?> map) => UsageRow(
    name: map['name'] as String? ?? '',
    tag: map['tag'] as String?,
    amount: map['amount'] as String? ?? '',
    fraction: ((map['fraction'] as num?)?.toDouble() ?? 0).clamp(0.0, 1.0),
    detail: map['detail'] as String? ?? '',
    family: map['family'] as String?,
  );
}

/// Uma linha da tabela de preços.
class PriceRow {
  const PriceRow({
    required this.name,
    required this.values,
    this.lit = false,
    this.edited = false,
  });

  final String name;

  /// Usado por esta bancada.
  final bool lit;

  /// Veio do `pricing.json` do usuário.
  final bool edited;
  final List<String> values;

  factory PriceRow.fromMap(Map<String, Object?> map) => PriceRow(
    name: map['name'] as String? ?? '',
    lit: map['lit'] as bool? ?? false,
    edited: map['edited'] as bool? ?? false,
    values: [
      for (final v in (map['values'] as List<Object?>? ?? const [])) '$v',
    ],
  );
}

class PriceTableView {
  const PriceTableView({
    this.openNote = '',
    this.columns = const [],
    this.rows = const [],
    this.originNote = '',
    this.ruleNote = '',
    this.fileNote = '',
  });

  /// O que fica ao lado de "Tabela de preços": "US$ por milhão de tokens".
  final String openNote;
  final List<String> columns;
  final List<PriceRow> rows;
  final String originNote;
  final String ruleNote;
  final String fileNote;

  factory PriceTableView.fromMap(Map<String, Object?>? map) => PriceTableView(
    openNote: map?['open_note'] as String? ?? '',
    columns: [
      for (final c in (map?['columns'] as List<Object?>? ?? const [])) '$c',
    ],
    rows: [
      for (final r in (map?['rows'] as List<Object?>? ?? const []))
        PriceRow.fromMap(r! as Map<String, Object?>),
    ],
    originNote: map?['origin_note'] as String? ?? '',
    ruleNote: map?['rule_note'] as String? ?? '',
    fileNote: map?['file_note'] as String? ?? '',
  );
}

/// O detalhe do consumo: o total e para onde ele foi.
class UsagePanelView {
  const UsagePanelView({
    required this.heading,
    required this.totalAmount,
    required this.totalTokens,
    this.split = const [],
    this.agents = const [],
    this.models = const [],
    this.prices = const PriceTableView(),
  });

  final String heading;
  final String totalAmount;
  final String totalTokens;
  final List<TariffShare> split;
  final List<UsageRow> agents;
  final List<UsageRow> models;
  final PriceTableView prices;

  factory UsagePanelView.fromMap(Map<String, Object?> map) {
    final total = map['total'] as Map<String, Object?>? ?? const {};
    List<T> list<T>(String key, T Function(Map<String, Object?>) read) => [
      for (final e in (map[key] as List<Object?>? ?? const []))
        read(e! as Map<String, Object?>),
    ];
    return UsagePanelView(
      heading: map['heading'] as String? ?? '',
      totalAmount: total['amount'] as String? ?? '',
      totalTokens: total['tokens'] as String? ?? '',
      split: list('split', TariffShare.fromMap),
      agents: list('agents', UsageRow.fromMap),
      models: list('models', UsageRow.fromMap),
      prices: PriceTableView.fromMap(map['prices'] as Map<String, Object?>?),
    );
  }
}

/// O consumo de uma bancada como o core o manda: a pastilha e o painel.
class UsageView {
  const UsageView({this.pill = const UsagePillView(), this.panel});

  final UsagePillView pill;
  final UsagePanelView? panel;

  factory UsageView.fromMap(Map<String, Object?> map) => UsageView(
    pill: UsagePillView.fromMap(map['pill'] as Map<String, Object?>?),
    panel: map['panel'] == null
        ? null
        : UsagePanelView.fromMap(map['panel']! as Map<String, Object?>),
  );
}
