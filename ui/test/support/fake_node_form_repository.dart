import 'dart:ui';

import 'package:egeon_deck/core/domain/entities/workbench_node.dart';
import 'package:egeon_deck/features/node/agent/domain/entities/node_form_submit.dart';
import 'package:egeon_deck/features/node/agent/domain/entities/node_form_view.dart';
import 'package:egeon_deck/features/node/agent/domain/entities/node_screen.dart';
import 'package:egeon_deck/features/node/agent/domain/entities/node_template.dart';
import 'package:egeon_deck/features/node/agent/domain/errors/agent_error.dart';
import 'package:egeon_deck/features/node/agent/domain/repository/node_form_repository.dart';

/// A tela do Claude Code: modelos com nome de gente, esforço e configuração.
NodeScreen claudeScreen(NodeTemplate template, {ScreenFields? fields}) =>
    NodeScreen(
      template: template,
      fields: fields ?? const ScreenFields(),
      models: const [
        ModelOption(label: 'padrão do CLI'),
        ModelOption(label: 'Opus 5.5', id: 'claude-opus-5-5'),
      ],
      efforts: const ['low', 'medium', 'high'],
      configEnv: 'CLAUDE_CONFIG_DIR',
      configItems: const [
        ConfigOption(title: '~/.claude'),
        ConfigOption(title: '~/.claude-agro', value: '/h/.claude-agro'),
      ],
    );

/// O OpenCode: sem modelo, esforço nem configuração.
NodeScreen bareScreen(NodeTemplate template, {ScreenFields? fields}) =>
    NodeScreen(
      template: template,
      fields: fields ?? const ScreenFields(),
      models: const [ModelOption(label: 'padrão do CLI')],
    );

/// O formulário sem core: o que ele mandou, e respostas fixas.
class FakeNodeFormRepository implements NodeFormRepository {
  FakeNodeFormRepository({this.saved = const [], this.nodeTemplate});

  /// Os componentes salvos.
  final List<ComponentInfo> saved;

  /// O nó em edição; sem ele, o formulário é de terminal novo.
  final NodeTemplate? nodeTemplate;

  final opened = <String?>[];
  final screens = <({String? cli, ShownFields? shown, String? config})>[];
  final created = <({NodeFormSubmit form, Rect? frame, Rect? visible})>[];
  final applied = <({String nodeId, NodeFormSubmit form})>[];

  /// O próximo pedido é recusado com esta mensagem.
  String? refuse;

  /// Só o catálogo da tela é recusado (o resto responde).
  bool refuseScreen = false;
  String createdId = 'revisor';

  static const clis = [
    CliChoice(key: 'claude', name: 'Claude Code'),
    CliChoice(key: 'opencode', name: 'OpenCode'),
  ];

  Future<void> _gate() async {
    final reason = refuse;
    if (reason != null) {
      refuse = null;
      throw AgentRefused(reason);
    }
  }

  @override
  Future<NodeFormView> open(String workbenchId, {String? nodeId}) async {
    opened.add(nodeId);
    await _gate();
    final template =
        nodeTemplate ??
        const NodeTemplate(name: '', kind: NodeKind.agent, agent: 'claude');
    return NodeFormView(
      template: template,
      cli: template.agent ?? 'claude',
      clis: clis,
      folders: const [
        FolderOption(value: '', shown: 'root'),
        FolderOption(value: 'api', shown: 'api'),
      ],
      components: saved,
      screen: claudeScreen(
        template,
        fields: ScreenFields(prompt: template.prompt),
      ),
    );
  }

  @override
  Future<NodeScreen> screen(
    String workbenchId, {
    required NodeTemplate template,
    String? nodeId,
    ShownFields? shown,
    String? cli,
    String? config,
  }) async {
    screens.add((cli: cli, shown: shown, config: config));
    if (refuseScreen) throw const AgentRefused('sem catálogo');
    await _gate();
    final fields = ScreenFields(
      prompt: shown?.prompt ?? template.prompt,
      config: config,
    );
    return cli == 'claude'
        ? claudeScreen(template, fields: fields)
        : bareScreen(template, fields: fields);
  }

  @override
  Future<FolderOption> folder(String workbenchId, String path) async {
    await _gate();
    final value = path.split('/').last;
    return FolderOption(value: value, shown: value);
  }

  @override
  Future<String> create(
    String workbenchId,
    NodeFormSubmit form, {
    Rect? frame,
    Rect? visible,
  }) async {
    created.add((form: form, frame: frame, visible: visible));
    await _gate();
    return createdId;
  }

  @override
  Future<String> apply(
    String workbenchId,
    String nodeId,
    NodeFormSubmit form,
  ) async {
    applied.add((nodeId: nodeId, form: form));
    await _gate();
    return form.fields.name;
  }

  @override
  Future<List<ComponentInfo>> components() async {
    await _gate();
    return saved;
  }
}
