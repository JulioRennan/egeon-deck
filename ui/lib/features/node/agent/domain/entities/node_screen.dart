import 'node_template.dart';

/// Um item do popup de modelo. Sem [id], o padrão do CLI.
class ModelOption {
  const ModelOption({required this.label, this.id});

  final String label;
  final String? id;

  factory ModelOption.fromMap(Map<String, Object?> map) => ModelOption(
    label: map['label'] as String? ?? '',
    id: map['id'] as String?,
  );
}

/// Um item do popup de configuração. Sem [value], o padrão do CLI.
class ConfigOption {
  const ConfigOption({required this.title, this.value});

  final String title;
  final String? value;

  factory ConfigOption.fromMap(Map<String, Object?> map) => ConfigOption(
    title: map['title'] as String? ?? '',
    value: map['value'] as String?,
  );
}

/// O que a tela mostra para o CLI escolhido. Nulo é o padrão do CLI.
class ScreenFields {
  const ScreenFields({
    this.model,
    this.effort,
    this.config,
    this.prompt,
    this.rules,
  });

  final String? model;
  final String? effort;
  final String? config;
  final String? prompt;
  final String? rules;

  factory ScreenFields.fromMap(Map<String, Object?> map) => ScreenFields(
    model: map['model'] as String?,
    effort: map['effort'] as String?,
    config: map['config'] as String?,
    prompt: map['prompt'] as String?,
    rules: map['rules'] as String?,
  );
}

/// A tela do formulário para um CLI, como o core a monta: o componente com o
/// que estava na tela já guardado, os valores e as listas. Campo que o CLI não
/// tem vem sem lista e não aparece.
class NodeScreen {
  const NodeScreen({
    required this.template,
    this.fields = const ScreenFields(),
    this.models = const [],
    this.efforts = const [],
    this.configEnv,
    this.configItems = const [],
  });

  final NodeTemplate template;
  final ScreenFields fields;

  /// O primeiro é o padrão do CLI. Só ele: o CLI não escolhe modelo.
  final List<ModelOption> models;

  /// Os níveis, sem o padrão. Vazio: o CLI não tem esforço.
  final List<String> efforts;

  /// A variável de ambiente da configuração. Nula: o CLI não tem.
  final String? configEnv;
  final List<ConfigOption> configItems;

  bool get offersModel => models.length > 1;
  bool get offersEffort => efforts.isNotEmpty;
  bool get offersConfig => configEnv != null;

  factory NodeScreen.fromMap(Map<String, Object?> map) => NodeScreen(
    template: NodeTemplate.fromMap(map['template']! as Map<String, Object?>),
    fields: ScreenFields.fromMap(
      map['fields'] as Map<String, Object?>? ?? const {},
    ),
    models: [
      for (final m in (map['models'] as List<Object?>? ?? const []))
        ModelOption.fromMap(m! as Map<String, Object?>),
    ],
    efforts: [
      for (final e in (map['efforts'] as List<Object?>? ?? const []))
        e! as String,
    ],
    configEnv: map['config_env'] as String?,
    configItems: [
      for (final c in (map['config_items'] as List<Object?>? ?? const []))
        ConfigOption.fromMap(c! as Map<String, Object?>),
    ],
  );
}
