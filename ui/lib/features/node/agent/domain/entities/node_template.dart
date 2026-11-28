import '../../../../../core/domain/entities/workbench_node.dart';

/// O que um CLI muda no componente (ADR-057).
class CliOverrides {
  const CliOverrides({
    this.cmd,
    this.config,
    this.model,
    this.effort,
    this.prompt,
    this.rules,
  });

  final String? cmd;
  final String? config;
  final String? model;
  final String? effort;
  final String? prompt;
  final String? rules;

  factory CliOverrides.fromMap(Map<String, Object?> map) => CliOverrides(
    cmd: map['cmd'] as String?,
    config: map['config'] as String?,
    model: map['model'] as String?,
    effort: map['effort'] as String?,
    prompt: map['prompt'] as String?,
    rules: map['rules'] as String?,
  );

  Map<String, Object?> toMap() => {
    'cmd': ?cmd,
    'config': ?config,
    'model': ?model,
    'effort': ?effort,
    'prompt': ?prompt,
    'rules': ?rules,
  };
}

/// Um componente (preset de terminal) como o core manda e recebe: o formato
/// do `components.json`. A UI só o carrega de um pedido para o outro; quem
/// mexe nele é o core.
class NodeTemplate {
  const NodeTemplate({
    required this.name,
    required this.kind,
    this.agent,
    this.maestro = false,
    this.cwd,
    this.prompt,
    this.rules,
    this.byAgent = const {},
    this.cmd,
  });

  final String name;

  /// `shell` ou `agent`.
  final NodeKind kind;
  final String? agent;
  final bool maestro;
  final String? cwd;
  final String? prompt;
  final String? rules;
  final Map<String, CliOverrides> byAgent;

  /// O comando do shell; o de agente é do CLI, em [byAgent].
  final String? cmd;

  factory NodeTemplate.fromMap(Map<String, Object?> map) => NodeTemplate(
    name: map['name'] as String? ?? '',
    kind: NodeKind.fromWire(map['kind']),
    agent: map['agent'] as String?,
    maestro: map['maestro'] as bool? ?? false,
    cwd: map['cwd'] as String?,
    prompt: map['prompt'] as String?,
    rules: map['rules'] as String?,
    byAgent: {
      for (final e
          in ((map['byAgent'] as Map<String, Object?>?) ?? const {}).entries)
        e.key: CliOverrides.fromMap(e.value! as Map<String, Object?>),
    },
    cmd: map['cmd'] as String?,
  );

  Map<String, Object?> toMap() => {
    'name': name,
    'kind': kind.wire,
    'agent': ?agent,
    if (maestro) 'maestro': true,
    'cwd': ?cwd,
    'prompt': ?prompt,
    'rules': ?rules,
    if (byAgent.isNotEmpty)
      'byAgent': {for (final e in byAgent.entries) e.key: e.value.toMap()},
    'cmd': ?cmd,
  };
}
