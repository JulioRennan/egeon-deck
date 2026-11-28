import '../../../../../core/domain/entities/workbench_node.dart';
import 'node_template.dart';

/// O que estava na tela para um CLI: o core guarda no componente com a regra
/// do ADR-057.
class ShownFields {
  const ShownFields({
    required this.cli,
    this.model,
    this.effort,
    this.config,
    this.prompt,
    this.rules,
  });

  final String cli;
  final String? model;
  final String? effort;
  final String? config;
  final String? prompt;
  final String? rules;

  Map<String, Object?> toMap() => {
    'cli': cli,
    'model': ?model,
    'effort': ?effort,
    'config': ?config,
    'prompt': ?prompt,
    'rules': ?rules,
  };
}

/// Os campos de cima do formulário. [cwd] vazio é a raiz da bancada.
class FormFields {
  const FormFields({
    required this.name,
    required this.kind,
    this.agent,
    this.cwd = '',
    this.cmd,
    this.maestro = false,
  });

  final String name;
  final NodeKind kind;
  final String? agent;
  final String cwd;
  final String? cmd;
  final bool maestro;

  Map<String, Object?> toMap() => {
    'name': name,
    'kind': kind.wire,
    'agent': ?agent,
    'cwd': cwd,
    'cmd': ?cmd,
    'maestro': maestro,
  };
}

/// O formulário confirmado: criar o terminal ou aplicar ao nó.
class NodeFormSubmit {
  const NodeFormSubmit({
    required this.template,
    required this.fields,
    this.shown,
    this.saveComponent = false,
  });

  final NodeTemplate template;
  final FormFields fields;
  final ShownFields? shown;

  /// "Salvar como componente reutilizável".
  final bool saveComponent;

  Map<String, Object?> toMap() => {
    'template': template.toMap(),
    'fields': fields.toMap(),
    if (shown != null) 'shown': shown!.toMap(),
    'save_component': saveComponent,
  };
}
