import 'context_reading.dart';
import 'effort_dial_view.dart';

/// Em que parte do menu de modelos a linha entra.
enum ModelGroup {
  /// O mais novo de cada família, com nome de gente.
  featured,

  /// Versões anteriores, num bloco à parte.
  older,

  /// Apelidos que o CLI resolve para "sempre o mais recente".
  alias,

  /// O padrão do CLI.
  standard;

  static ModelGroup parse(Object? raw) => values.firstWhere(
    (group) => group.name == raw,
    orElse: () => ModelGroup.alias,
  );
}

/// Uma linha do menu de modelos, já resolvida pelo core.
class ModelEntry {
  const ModelEntry({
    required this.label,
    required this.group,
    this.value,
    this.selected = false,
  });

  final String label;

  /// O que vai na flag; nulo é o padrão do CLI.
  final String? value;
  final ModelGroup group;
  final bool selected;

  factory ModelEntry.fromMap(Map<String, Object?> map) => ModelEntry(
    label: map['label']! as String,
    value: map['value'] as String?,
    group: ModelGroup.parse(map['group']),
    selected: map['selected'] as bool? ?? false,
  );

  Map<String, Object?> toMap() => {
    'label': label,
    'value': value,
    'group': group.name,
    'selected': selected,
  };
}

/// O ultracode de um agente: existe só em modelo com esforço.
class Ultracode {
  const Ultracode({required this.on, required this.available});

  final bool on;
  final bool available;

  factory Ultracode.fromMap(Map<String, Object?> map) => Ultracode(
    on: map['on'] as bool? ?? false,
    available: map['available'] as bool? ?? true,
  );

  Map<String, Object?> toMap() => {'on': on, 'available': available};
}

/// Tudo que a faixa do cabeçalho de um agente mostra, como o core o entrega.
/// Tudo depende do modelo — o nome, os níveis, o nível do auto, se o ultracode
/// existe — e o modelo de fato só se sabe depois do primeiro turno; por isso a
/// UI recebe o estado inteiro a cada mudança e remonta o que precisar.
class AgentStatus {
  const AgentStatus({
    this.modelTitle = 'padrão',
    this.models = const [],
    this.offersModel = false,
    this.dial = const EffortDialView(),
    this.offersEffort = true,
    this.ultracode,
    this.context,
    this.clearable = true,
  });

  /// Quem respondeu, com o pedido entre parênteses quando é outro
  /// (`Opus 5.5 (opusplan)`); antes do primeiro turno, o pedido.
  final String modelTitle;

  final List<ModelEntry> models;

  /// O CLI deste agente aceita escolher o modelo: sem isso o seletor nem
  /// aparece, e quem diz é o core (`offers_model`), não o tamanho da lista.
  final bool offersModel;

  /// O seletor de esforço, pronto, como o core o descreve.
  final EffortDialView dial;
  final bool offersEffort;
  final Ultracode? ultracode;

  /// Nulo é "não se sabe": anel vazio e travessão.
  final ContextReading? context;
  final bool clearable;

  factory AgentStatus.fromMap(Map<String, Object?> map) {
    final context = map['context'] as Map<String, Object?>?;
    final ultracode = map['ultracode'] as Map<String, Object?>?;
    return AgentStatus(
      modelTitle: map['model_title'] as String? ?? 'padrão',
      models: [
        for (final m in (map['models'] as List<Object?>? ?? const []))
          ModelEntry.fromMap(m! as Map<String, Object?>),
      ],
      offersModel: map['offers_model'] as bool? ?? false,
      dial: map['dial'] == null
          ? const EffortDialView()
          : EffortDialView.fromMap(map['dial']! as Map<String, Object?>),
      offersEffort: map['offers_effort'] as bool? ?? true,
      ultracode: ultracode == null ? null : Ultracode.fromMap(ultracode),
      context: context == null ? null : ContextReading.fromMap(context),
      clearable: map['clearable'] as bool? ?? true,
    );
  }

  Map<String, Object?> toMap() => {
    'model_title': modelTitle,
    'models': [for (final m in models) m.toMap()],
    'offers_model': offersModel,
    'dial': dial.toMap(),
    'offers_effort': offersEffort,
    'ultracode': ultracode?.toMap(),
    'context': context?.toMap(),
    'clearable': clearable,
  };
}
