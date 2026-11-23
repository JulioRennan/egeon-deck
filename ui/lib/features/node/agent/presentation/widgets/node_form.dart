import '../../../../../commons/utils/effort_names.dart';

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../commons/widgets/form_dialog.dart';
import '../../../../../commons/widgets/form_kit.dart';
import '../../../../../core/adapters/injector.dart';
import '../../../../../core/adapters/path_picker.dart';
import '../../../../../core/domain/entities/workbench_node.dart';
import '../../../../../commons/widgets/eg/eg_icon.dart';
import '../../../../../commons/widgets/eg/pressable.dart';
import '../../../../../theme/egeon_colors.dart';
import '../../../../../theme/egeon_tokens.dart';
import '../../../../../theme/egeon_type.dart';
import '../../domain/entities/node_form_submit.dart';
import '../../domain/entities/node_form_view.dart';
import '../../domain/entities/node_screen.dart';
import '../../domain/errors/agent_error.dart';
import '../cubit/node_form_cubit.dart';

/// Abre o formulário de terminal — o mesmo para criar e para editar. Sem
/// [nodeId], cria um terminal na bancada (em [frame], ou no primeiro lugar
/// livre); com, configura o nó. [root] é a pasta da bancada, onde o + da pasta
/// começa. Devolve o id final do nó, ou nulo se cancelou.
Future<String?> showNodeForm(
  BuildContext context, {
  required String workbenchId,
  String? nodeId,
  Rect? frame,
  Rect? visible,
  String? root,
}) => showFormDialog<String>(
  context,
  width: 720,
  builder: (_, close) => BlocProvider(
    create: (_) => inject<NodeFormCubit>((
      workbenchId: workbenchId,
      nodeId: nodeId,
      frame: frame,
      visible: visible,
    )),
    child: NodeFormBody(close: close, root: root),
  ),
);

/// O corpo do formulário. Os campos digitados e as escolhas da tela são
/// daqui; o que mostrar em cada CLI, e o que gravar, é do core.
class NodeFormBody extends StatefulWidget {
  const NodeFormBody({required this.close, this.root, super.key});

  final void Function([String? nodeId]) close;
  final String? root;

  @override
  State<NodeFormBody> createState() => _NodeFormBodyState();
}

class _NodeFormBodyState extends State<NodeFormBody> {
  final _name = TextEditingController();
  final _cmd = TextEditingController();
  final _prompt = TextEditingController();
  final _rules = TextEditingController();

  /// "Criar do zero" (0) ou "Começar de outro" (1).
  var _tab = 0;
  var _agent = true;
  var _folder = '';
  var _maestro = false;
  var _save = false;
  String? _model;
  String? _effort;
  String? _config;

  NodeFormCubit get _cubit => context.read<NodeFormCubit>();

  @override
  void dispose() {
    _name.dispose();
    _cmd.dispose();
    _prompt.dispose();
    _rules.dispose();
    super.dispose();
  }

  /// Os campos de cima voltam aos do componente que entrou.
  void _load(NodeFormOpen open) {
    final template = open.template;
    _agent = template.kind == NodeKind.agent;
    _name.text = template.name;
    _cmd.text = template.cmd ?? '';
    _folder = template.cwd ?? '';
    _maestro = template.maestro;
    _show(open.screen);
  }

  /// Os campos do CLI voltam aos que o core mandou para ele.
  void _show(NodeScreen screen) {
    final fields = screen.fields;
    _model = fields.model;
    _effort = fields.effort;
    _config = fields.config;
    _prompt.text = fields.prompt ?? '';
    _rules.text = fields.rules ?? '';
  }

  void _onState(BuildContext context, NodeFormState state) {
    switch (state) {
      case NodeFormLoaded():
        setState(() => _load(state));
      case NodeFormSwitched():
        setState(() => _show(state.screen));
      case NodeFormFolderAdded(:final folder):
        setState(() => _folder = folder);
      case NodeFormDone(:final nodeId):
        widget.close(nodeId);
      case NodeFormOpening() ||
          NodeFormUnavailable() ||
          NodeFormSaving() ||
          NodeFormRefused():
        break;
    }
  }

  /// O que está na tela do CLI marcado, para o core guardar nele.
  ShownFields? _shown(NodeFormOpen open) {
    final cli = open.cli;
    if (cli == null) return null;
    return ShownFields(
      cli: cli,
      model: _model,
      effort: _effort,
      config: _config,
      prompt: _prompt.text,
      rules: _rules.text,
    );
  }

  void _confirm(NodeFormOpen open) => unawaited(
    _cubit.confirm(
      FormFields(
        name: _name.text,
        kind: _agent ? NodeKind.agent : NodeKind.shell,
        agent: _agent ? open.cli : null,
        cwd: _folder,
        cmd: _cmd.text,
        maestro: _maestro,
      ),
      shown: _shown(open),
      saveComponent: _save,
    ),
  );

  Future<void> _addFolder() async {
    final path = await inject<PathPicker>().folder(
      prompt: 'Usar esta pasta',
      initialDirectory: widget.root,
    );
    if (path != null && mounted) await _cubit.addFolder(path);
  }

  Future<void> _browseConfig(NodeFormOpen open) async {
    final path = await inject<PathPicker>().folder(
      prompt: 'Escolher',
      initialDirectory: '~',
    );
    if (path != null && mounted) await _cubit.pickConfig(path, _shown(open));
  }

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<NodeFormCubit, NodeFormState>(
        listener: _onState,
        builder: (context, state) => switch (state) {
          NodeFormOpening() => _frame(const SizedBox(height: 80), null),
          NodeFormUnavailable(:final error) => _frame(
            Text(_message(error), style: _hint(context)),
            null,
          ),
          NodeFormDone() => const SizedBox.shrink(),
          NodeFormOpen() => _frame(_form(state), state),
        },
      );

  Widget _frame(Widget child, NodeFormOpen? open) => FormDialogBody(
    title: _cubit.editing
        ? 'Configurar ${_cubit.target.nodeId}'
        : 'Novo terminal',
    message: 'O nome vira o id do nó e aparece no endereço de dispatch.',
    actions: [
      FormDialogButton('Cancelar', onTap: widget.close),
      FormDialogButton(
        _cubit.editing ? 'Aplicar' : 'Criar',
        primary: true,
        enabled: open != null && open is! NodeFormSaving,
        onTap: () {
          if (open != null) _confirm(open);
        },
      ),
    ],
    child: child,
  );

  Widget _form(NodeFormOpen open) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SegmentedTabs(
        keyPrefix: 'form-tab',
        labels: const ['Criar do zero', 'Começar de outro'],
        selected: _tab,
        onSelect: (tab) => setState(() => _tab = tab),
      ),
      const SizedBox(height: 12),
      if (_tab == 0) _details(open) else _presets(open),
      if (open case NodeFormRefused(:final error)) ...[
        const SizedBox(height: 8),
        Text(
          _message(error),
          key: const ValueKey('node-form-error'),
          style: _hint(context).copyWith(color: context.eg.attention),
        ),
      ],
    ],
  );

  Widget _details(NodeFormOpen open) {
    final screen = open.screen;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedTabs(
          keyPrefix: 'node-kind',
          labels: const ['Shell', 'Agente'],
          selected: _agent ? 1 : 0,
          onSelect: (i) => setState(() => _agent = i == 1),
        ),
        const SizedBox(height: 14),
        const FormLabel('NOME'),
        FormTextField(
          key: const ValueKey('node-name'),
          controller: _name,
          placeholder: 'revisor, front end, build…',
          autofocus: true,
          maxLines: 1,
        ),
        const SizedBox(height: 14),
        if (_agent) ..._agentFields(open, screen) else ..._shellFields(),
        _folders(open),
        if (_agent) ...[const SizedBox(height: 14), _texts()],
        const SizedBox(height: 14),
        FormCheckbox(
          key: const ValueKey('save-component'),
          label: 'Salvar como componente reutilizável',
          on: _save,
          onChanged: (on) => setState(() => _save = on),
        ),
      ],
    );
  }

  List<Widget> _shellFields() => [
    const FormLabel('COMANDO — vazio abre o zsh'),
    FormTextField(
      key: const ValueKey('node-cmd'),
      controller: _cmd,
      placeholder: 'ex: npm run dev',
      maxLines: 1,
    ),
    const SizedBox(height: 14),
  ];

  List<Widget> _agentFields(NodeFormOpen open, NodeScreen screen) {
    final clis = open.view.clis;
    // O padrão do CLI vem do core, no primeiro item de modelo.
    final defaultLabel = screen.models.isEmpty ? '' : screen.models.first.label;
    return [
      const FormLabel('CLI'),
      Row(
        children: [
          for (final cli in clis)
            Expanded(
              child: FormRadio(
                key: ValueKey('cli-${cli.key}'),
                label: cli.name,
                selected: cli.key == open.cli,
                onTap: () {
                  if (cli.key != open.cli) {
                    unawaited(_cubit.switchCli(cli.key, _shown(open)));
                  }
                },
              ),
            ),
        ],
      ),
      const SizedBox(height: 14),
      if (screen.offersModel || screen.offersEffort) ...[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (screen.offersModel)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const FormLabel('MODELO'),
                    PopupField(
                      key: const ValueKey('node-model'),
                      items: [for (final m in screen.models) m.label],
                      selected: _index(screen.models.map((m) => m.id), _model),
                      onSelect: (i) =>
                          setState(() => _model = screen.models[i].id),
                    ),
                  ],
                ),
              ),
            if (screen.offersModel && screen.offersEffort)
              const SizedBox(width: 10),
            if (screen.offersEffort)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const FormLabel('ESFORÇO'),
                    PopupField(
                      key: const ValueKey('node-effort'),
                      items: [
                        defaultLabel,
                        for (final e in screen.efforts) effortName(e),
                      ],
                      selected: _index([null, ...screen.efforts], _effort),
                      onSelect: (i) => setState(
                        () => _effort = i == 0 ? null : screen.efforts[i - 1],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
      ],
      // Logo embaixo do modelo: ser maestro é decisão sobre o agente, como o
      // modelo, e não um detalhe do rodapé.
      FormCheckbox(
        key: const ValueKey('node-maestro'),
        label: 'Maestro — monta a bancada',
        on: _maestro,
        onChanged: (on) => setState(() => _maestro = on),
      ),
      const SizedBox(height: 14),
      if (screen.offersConfig) ...[
        _titled(
          'CONFIGURAÇÃO — ${screen.configEnv}',
          PlusButton(
            key: const ValueKey('config-browse'),
            tooltip: 'Outra configuração',
            onTap: () => unawaited(_browseConfig(open)),
          ),
        ),
        PopupField(
          key: const ValueKey('node-config'),
          items: [for (final c in screen.configItems) c.title],
          selected: _index(screen.configItems.map((c) => c.value), _config),
          onSelect: (i) =>
              setState(() => _config = screen.configItems[i].value),
        ),
        const SizedBox(height: 14),
      ],
    ];
  }

  Widget _folders(NodeFormOpen open) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _titled(
        'PASTA — relativa à raiz da bancada',
        PlusButton(
          key: const ValueKey('folder-add'),
          tooltip: 'Outra pasta',
          onTap: () => unawaited(_addFolder()),
        ),
      ),
      Container(
        constraints: const BoxConstraints(maxHeight: 88),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: context.eg.obsidian,
          borderRadius: BorderRadius.circular(EgeonRadius.md),
          border: Border.all(color: context.eg.line),
        ),
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final folder in open.folders)
              FormRadio(
                key: ValueKey('folder-${folder.value}'),
                label: folder.shown,
                monospace: true,
                selected: folder.value == _folder,
                onTap: () => setState(() => _folder = folder.value),
              ),
          ],
        ),
      ),
    ],
  );

  /// Lado a lado, papel à esquerda: é a ordem em que os dois entram no system
  /// prompt — e é ela que faz a regra valer sobre o papel (ADR-056).
  Widget _texts() => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const FormLabel('PAPEL — quem este terminal é'),
            FormTextField(
              key: const ValueKey('node-prompt'),
              controller: _prompt,
              maxLines: 6,
              minLines: 6,
            ),
          ],
        ),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const FormLabel('REGRAS — somam às da bancada'),
            FormTextField(
              key: const ValueKey('node-rules'),
              controller: _rules,
              maxLines: 6,
              minLines: 6,
            ),
          ],
        ),
      ),
    ],
  );

  /// Os presets ficam numa aba própria, com cards, e não num menu: escondidos
  /// atrás de uma pressão longa, salvar funcionava e ninguém achava o
  /// resultado.
  Widget _presets(NodeFormOpen open) {
    final saved = open.view.components;
    if (saved.isEmpty) {
      return SizedBox(
        height: 200,
        child: Center(
          child: Text(
            'Nenhum componente salvo ainda.\n\nMonte um terminal na aba '
            '"Criar do zero" e marque "Salvar como componente reutilizável" — '
            'ele aparece aqui da próxima vez.',
            textAlign: TextAlign.center,
            style: _hint(context).copyWith(fontSize: 12),
          ),
        ),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 420),
      child: SingleChildScrollView(
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final component in saved)
              _ComponentCard(
                key: ValueKey('component-${component.name}'),
                component: component,
                onTap: () {
                  // Escolher um preset não é o fim da tarefa: quase sempre você
                  // quer ajustar o nome ou a pasta antes de criar.
                  setState(() => _tab = 0);
                  unawaited(_cubit.startFrom(component));
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _titled(String text, Widget plus) => Row(
    children: [
      Expanded(child: FormLabel(text)),
      Padding(padding: const EdgeInsets.only(bottom: 4), child: plus),
    ],
  );

  /// A posição de [value] na lista; o primeiro (o padrão) quando não está.
  static int _index(Iterable<String?> values, String? value) {
    final index = values.toList().indexOf(value);
    return index < 0 ? 0 : index;
  }

  static String _message(AgentError error) => switch (error) {
    AgentRefused(:final message) => message,
    AgentOffline() => 'Sem conexão com o core. Tente de novo.',
  };
}

TextStyle _hint(BuildContext context) => EgeonType.caption.copyWith(
  color: context.eg.textMuted,
  decoration: TextDecoration.none,
);

/// Card de um componente salvo: o nome e o que ele roda. A escolha é visual —
/// você reconhece "revisor" pelo formato antes de ler o nome.
class _ComponentCard extends StatefulWidget {
  const _ComponentCard({
    required this.component,
    required this.onTap,
    super.key,
  });

  final ComponentInfo component;
  final VoidCallback onTap;

  @override
  State<_ComponentCard> createState() => _ComponentCardState();
}

class _ComponentCardState extends State<_ComponentCard> {
  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    final component = widget.component;
    return Pressable(
      onPressed: widget.onTap,
      semanticLabel: component.name,
      builder: (context, s) => DecoratedBox(
        decoration: BoxDecoration(
          color: s.hovered ? c.accentSoft : c.steel,
          borderRadius: BorderRadius.circular(EgeonRadius.lg),
          border: Border.all(color: s.hovered ? c.accent : c.line),
        ),
        child: SizedBox(
          width: 132,
          height: 96,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                EgIcon(
                  component.kind == NodeKind.agent
                      ? EgIcons.agent
                      : EgIcons.terminal,
                  size: 20,
                  color: s.hovered ? c.accent : c.textSecondary,
                ),
                const SizedBox(height: 8),
                Text(
                  component.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: EgeonType.label.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  component.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: _hint(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
