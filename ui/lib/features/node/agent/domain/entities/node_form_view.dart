import '../../../../../core/domain/entities/workbench_node.dart';
import 'node_screen.dart';
import 'node_template.dart';

/// Um CLI dos radios do formulário.
class CliChoice {
  const CliChoice({required this.key, required this.name});

  final String key;
  final String name;

  factory CliChoice.fromMap(Map<String, Object?> map) =>
      CliChoice(key: map['key']! as String, name: map['name'] as String? ?? '');
}

/// Uma pasta da lista: o valor gravado e o texto (`root` é a raiz da bancada).
class FolderOption {
  const FolderOption({required this.value, required this.shown});

  final String value;
  final String shown;

  factory FolderOption.fromMap(Map<String, Object?> map) => FolderOption(
    value: map['value'] as String? ?? '',
    shown: map['shown'] as String? ?? '',
  );
}

/// Um componente salvo: card da aba "Começar de outro" e item do menu do
/// botão Terminal.
class ComponentInfo {
  const ComponentInfo({
    required this.name,
    required this.kind,
    required this.subtitle,
    required this.template,
    this.prompt,
  });

  final String name;
  final NodeKind kind;
  final String subtitle;
  final String? prompt;
  final NodeTemplate template;

  factory ComponentInfo.fromMap(Map<String, Object?> map) => ComponentInfo(
    name: map['name'] as String? ?? '',
    kind: NodeKind.fromWire(map['kind']),
    subtitle: map['subtitle'] as String? ?? '',
    prompt: map['prompt'] as String?,
    template: NodeTemplate.fromMap(map['template']! as Map<String, Object?>),
  );
}

/// O formulário aberto: o componente, os CLIs, as pastas, os componentes
/// salvos e a tela do CLI marcado.
class NodeFormView {
  const NodeFormView({
    required this.template,
    required this.screen,
    this.cli,
    this.clis = const [],
    this.folders = const [],
    this.components = const [],
  });

  final NodeTemplate template;

  /// O CLI marcado ao abrir; nulo quando não há perfil nenhum.
  final String? cli;
  final List<CliChoice> clis;
  final List<FolderOption> folders;
  final List<ComponentInfo> components;
  final NodeScreen screen;

  factory NodeFormView.fromMap(Map<String, Object?> map) => NodeFormView(
    template: NodeTemplate.fromMap(map['template']! as Map<String, Object?>),
    cli: map['cli'] as String?,
    clis: [
      for (final c in (map['clis'] as List<Object?>? ?? const []))
        CliChoice.fromMap(c! as Map<String, Object?>),
    ],
    folders: [
      for (final f in (map['folders'] as List<Object?>? ?? const []))
        FolderOption.fromMap(f! as Map<String, Object?>),
    ],
    components: [
      for (final c in (map['components'] as List<Object?>? ?? const []))
        ComponentInfo.fromMap(c! as Map<String, Object?>),
    ],
    screen: NodeScreen.fromMap(map['screen']! as Map<String, Object?>),
  );
}
