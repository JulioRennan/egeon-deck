import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../commons/widgets/form_dialog.dart';
import '../../../../commons/widgets/form_kit.dart';
import '../../../../core/adapters/injector.dart';
import '../../../../theme/egeon_colors.dart';
import '../../../../theme/egeon_type.dart';
import '../../domain/entities/worktree_info.dart';
import '../../domain/entities/bench_template.dart';
import '../../domain/entities/worktree_plan.dart';
import '../../domain/entities/worktree_source.dart';
import '../cubit/worktree_branch_cubit.dart';
import '../cubit/worktree_form_cubit.dart';
import 'template_pick_list.dart';

/// O que o formulário de worktree devolve.
class WorktreeInput {
  const WorktreeInput({
    required this.branch,
    required this.destination,
    required this.nodes,
    this.template,
  });

  final String branch;
  final WorktreeDestination destination;
  final Map<String, String> nodes;

  /// Sem bancada de origem: o template da bancada nova, ou nenhum.
  final String? template;
}

/// Abre o formulário de worktree: o resumo do repositório, a branch com o
/// veredito do core e, duplicando uma bancada, o destino e uma linha por
/// terminal; a partir de uma pasta, o template da bancada nova. [title] é o
/// `Worktree de <repo>`; [info], quando já lido, poupa a segunda leitura.
Future<WorktreeInput?> showWorktreeForm(
  BuildContext context, {
  required WorktreeSource source,
  required String title,
  WorktreeInfo? info,
  List<BenchTemplate> templates = const [],
}) => showFormDialog<WorktreeInput>(
  context,
  width: 460,
  builder: (_, close) => MultiBlocProvider(
    providers: [
      BlocProvider(
        create: (_) => inject<WorktreeFormCubit>((source: source, info: info)),
      ),
      BlocProvider(
        create: (_) => inject<WorktreeBranchCubit>((
          source: source,
          suggested: info?.suggestedBranch,
        )),
      ),
    ],
    child: _Body(
      title: title,
      offersMove: source.hasOrigin,
      templates: source.hasOrigin ? null : templates,
      close: close,
    ),
  ),
);

class _Body extends StatefulWidget {
  const _Body({
    required this.title,
    required this.offersMove,
    required this.templates,
    required this.close,
  });

  final String title;

  /// Duplicando há duas saídas; sem bancada de origem, só abrir uma nova.
  final bool offersMove;

  /// Sem bancada de origem, o seletor de template; duplicando, os nós vêm da
  /// bancada e não há o que escolher.
  final List<BenchTemplate>? templates;
  final void Function([WorktreeInput? result]) close;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  late final _branch = TextEditingController(
    text: context.read<WorktreeBranchCubit>().branch,
  );
  final _rows = <String, TextEditingController>{};
  String? _template;

  @override
  void dispose() {
    _branch.dispose();
    for (final controller in _rows.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _submit(WorktreeFormState state, String branch) {
    if (branch.isEmpty) return;
    widget.close(
      WorktreeInput(
        branch: branch,
        destination: state.destination,
        nodes: state.nodes(branch),
        template: _template,
      ),
    );
  }

  /// O resumo chegou: a branch que o core sugere entra no campo, se a pessoa
  /// ainda não escreveu nada, e o veredito dela já é pedido.
  void _onForm(BuildContext context, WorktreeFormState state) {
    if (state is! WorktreeFormReady || _branch.text.isNotEmpty) return;
    final suggested = state.info.suggestedBranch;
    _branch.text = suggested;
    context.read<WorktreeBranchCubit>().suggest(suggested);
  }

  /// A branch da bancada mudou: as linhas que ninguém tocou a acompanham
  /// (`NodeWorktreeRow.suggest`).
  void _onBranch(BuildContext context, WorktreeBranchState state) {
    final branch = switch (state) {
      BranchEmpty() => '',
      BranchAsking(:final branch) => branch,
      BranchJudged(:final branch) => branch,
    };
    final edited = context.read<WorktreeFormCubit>().state.edited;
    for (final MapEntry(key: node, value: controller) in _rows.entries) {
      if (!edited.containsKey(node) && controller.text != branch) {
        controller.text = branch;
      }
    }
  }

  @override
  Widget build(BuildContext context) => MultiBlocListener(
    listeners: [
      BlocListener<WorktreeFormCubit, WorktreeFormState>(
        listenWhen: (before, now) =>
            before is WorktreeFormOpening && now is WorktreeFormReady,
        listener: _onForm,
      ),
      BlocListener<WorktreeBranchCubit, WorktreeBranchState>(
        listener: _onBranch,
      ),
    ],
    child: Builder(builder: _content),
  );

  Widget _content(BuildContext context) {
    final state = context.watch<WorktreeFormCubit>().state;
    final cubit = context.read<WorktreeFormCubit>();
    final branches = context.read<WorktreeBranchCubit>();
    final (branch, plan) = switch (context.watch<WorktreeBranchCubit>().state) {
      BranchEmpty() => ('', null),
      BranchAsking(:final branch) => (branch, null),
      BranchJudged(:final branch, :final plan) => (branch, plan),
    };
    final info = switch (state) {
      WorktreeFormOpening() => null,
      WorktreeFormReady(:final info) => info,
    };
    final templates = widget.templates;
    return FormDialogBody(
      title: widget.title,
      message: info?.summary,
      actions: [
        FormDialogButton('Cancelar', onTap: widget.close),
        FormDialogButton(
          'Abrir',
          primary: true,
          enabled: branch.isNotEmpty,
          onTap: () => _submit(state, branch),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.offersMove) ...[
            const FormLabel('O QUE FAZER'),
            _Radio(
              key: const ValueKey('destination-new'),
              title: 'Abrir uma bancada nova na worktree',
              hint:
                  'Nada aqui é reiniciado; você troca entre as duas na '
                  'barra.',
              selected: state.destination == WorktreeDestination.newWorkbench,
              onTap: () =>
                  cubit.setDestination(WorktreeDestination.newWorkbench),
            ),
            _Radio(
              key: const ValueKey('destination-move'),
              title: 'Mudar esta bancada para a worktree',
              hint:
                  'Os terminais reiniciam na pasta nova — o que estiver '
                  'rodando neles para.',
              selected: state.destination == WorktreeDestination.moveCurrent,
              onTap: () =>
                  cubit.setDestination(WorktreeDestination.moveCurrent),
            ),
            const SizedBox(height: 10),
          ],
          const FormLabel('BRANCH DA BANCADA'),
          FormTextField(
            key: const ValueKey('worktree-branch'),
            controller: _branch,
            placeholder: 'nome da branch',
            autofocus: true,
            onChanged: branches.setBranch,
            onSubmitted: () => _submit(state, branch),
          ),
          const SizedBox(height: 6),
          _Verdict(plan: plan),
          if (info != null && info.nodes.isNotEmpty) ...[
            const SizedBox(height: 10),
            const FormLabel('TERMINAIS'),
            Text(
              'Todos vão. Na mesma branch da bancada, junto com ela; com '
              'outra branch, em worktree própria do repositório dele. Em '
              'branco, fica onde está.',
              style: _hint(context),
            ),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 150),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final node in info.nodes)
                    _row(cubit, state, node, branch),
                ],
              ),
            ),
          ],
          if (templates != null) ...[
            const SizedBox(height: 10),
            const FormLabel('TEMPLATE'),
            TemplatePickList(
              templates: templates,
              chosen: _template,
              height: 90,
              onChoose: (name) => setState(() => _template = name),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(
    WorktreeFormCubit cubit,
    WorktreeFormState state,
    NodeWorktree node,
    String branch,
  ) {
    final text = state.rowText(node, branch);
    final controller = _rows.putIfAbsent(
      node.node,
      () => TextEditingController(text: text),
    );
    final choice = node.choice(text, branch);
    final warns = choice.warns || (!node.editable && !node.exists);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  node.node,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _mono(context),
                ),
                Text(
                  node.detail(choice),
                  key: ValueKey('node-${node.node}-detail'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _hint(context)
                      .copyWith(color: warns ? context.eg.attention : null),
                ),
              ],
            ),
          ),
          if (node.editable) ...[
            const SizedBox(width: 10),
            SizedBox(
              width: 170,
              child: FormTextField(
                key: ValueKey('node-${node.node}'),
                controller: controller,
                placeholder: 'não levar',
                onChanged: (text) => cubit.editNode(node.node, text),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

TextStyle _hint(BuildContext context) => EgeonType.caption.copyWith(
  color: context.eg.textMuted,
  decoration: TextDecoration.none,
);

TextStyle _mono(BuildContext context) => EgeonType.monoMeta.copyWith(
  color: context.eg.textSecondary,
  decoration: TextDecoration.none,
);

/// O que vai acontecer com o nome escrito e onde a pasta nasce. Em laranja
/// quando não é criar do zero: seguir uma remota ou reaproveitar uma worktree
/// pedem um olhar antes.
class _Verdict extends StatelessWidget {
  const _Verdict({required this.plan});

  final WorktreePlan? plan;

  @override
  Widget build(BuildContext context) {
    final plan = this.plan;
    if (plan == null) return const SizedBox(height: 30);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          plan.message ?? _summary(plan.verdict),
          key: const ValueKey('worktree-verdict'),
          style: _hint(context).copyWith(
            color: plan.isFresh ? context.eg.textMuted : context.eg.attention,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          plan.folder,
          key: const ValueKey('worktree-folder'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _mono(context),
        ),
      ],
    );
  }

  static String _summary(WorktreeVerdict verdict) => switch (verdict) {
    WorktreeVerdict.create => 'Cria a branch.',
    WorktreeVerdict.openExisting => 'Abre a branch que já existe.',
    WorktreeVerdict.followRemote => 'Segue a branch remota.',
    WorktreeVerdict.alreadyOpen => 'Essa branch já está aberta numa worktree.',
    WorktreeVerdict.other => '',
  };
}

class _Radio extends StatelessWidget {
  const _Radio({
    required this.title,
    required this.hint,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String title;
  final String hint;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FormRadio(label: title, selected: selected, onTap: onTap),
          Padding(
            padding: const EdgeInsets.only(left: 26, top: 2),
            child: Text(hint, style: _hint(context)),
          ),
        ],
      ),
    ),
  );
}
