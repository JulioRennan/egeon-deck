import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../commons/widgets/app_dialog.dart';
import '../../../../commons/widgets/app_text_field.dart';
import '../../../../commons/widgets/form_label.dart';
import '../../../../theme/app_colors.dart';
import '../../domain/entities/worktree_info.dart';
import '../../domain/entities/worktree_plan.dart';
import '../../domain/usecase/bench_creation.dart';
import '../cubit/worktree_form_cubit.dart';

/// O que o formulário de worktree devolve.
class WorktreeInput {
  const WorktreeInput({
    required this.branch,
    required this.destination,
    required this.nodes,
  });

  final String branch;
  final WorktreeDestination destination;
  final Map<String, String> nodes;
}

/// Abre o formulário de worktree da bancada [benchId]: o resumo do repositório,
/// a branch com o veredito do core, o destino e uma linha por terminal.
Future<WorktreeInput?> showWorktreeForm(
  BuildContext context, {
  required String benchId,
  required String benchName,
  required WorktreeActions actions,
}) => showAppDialog<WorktreeInput>(
  context,
  width: 460,
  builder: (_, close) => BlocProvider(
    create: (_) => WorktreeFormCubit(benchId: benchId, actions: actions),
    child: _Body(benchName: benchName, close: close),
  ),
);

class _Body extends StatefulWidget {
  const _Body({required this.benchName, required this.close});

  final String benchName;
  final void Function([WorktreeInput? result]) close;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  final _branch = TextEditingController();
  final _rows = <String, TextEditingController>{};

  @override
  void dispose() {
    _branch.dispose();
    for (final controller in _rows.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _submit(WorktreeFormState state) {
    final branch = state.branch.trim();
    if (branch.isEmpty) return;
    widget.close(
      WorktreeInput(
        branch: branch,
        destination: state.destination,
        nodes: state.nodes,
      ),
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocConsumer<WorktreeFormCubit, WorktreeFormState>(
    listenWhen: (before, now) =>
        before.info == null && now.info != null && _branch.text.isEmpty,
    listener: (context, state) => _branch.text = state.branch,
    builder: (context, state) {
      final cubit = context.read<WorktreeFormCubit>();
      final info = state.info;
      return DialogBody(
        title: 'Worktree de ${widget.benchName}',
        message: info?.summary,
        actions: [
          DialogButton('Cancelar', onTap: widget.close),
          DialogButton(
            'Abrir',
            primary: true,
            enabled: state.branch.trim().isNotEmpty,
            onTap: () => _submit(state),
          ),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
            const FormLabel('BRANCH DA BANCADA'),
            AppTextField(
              controller: _branch,
              placeholder: 'nome da branch',
              autofocus: true,
              onChanged: cubit.setBranch,
              onSubmitted: () => _submit(state),
            ),
            const SizedBox(height: 6),
            _Verdict(plan: state.plan),
            if (info != null && info.nodes.isNotEmpty) ...[
              const SizedBox(height: 10),
              const FormLabel('TERMINAIS'),
              Text(
                'Todos vão. Na mesma branch da bancada, junto com ela; com '
                'outra branch, em worktree própria do repositório dele. Em '
                'branco, acompanha a bancada.',
                style: _hint,
              ),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 150),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final node in info.nodes) _row(cubit, state, node),
                  ],
                ),
              ),
            ],
          ],
        ),
      );
    },
  );

  Widget _row(
    WorktreeFormCubit cubit,
    WorktreeFormState state,
    NodeWorktree node,
  ) {
    final controller = _rows.putIfAbsent(
      node.node,
      () => TextEditingController(text: state.rowText(node)),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              node.node,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _mono,
            ),
          ),
          Expanded(
            child: node.editable
                ? AppTextField(
                    key: ValueKey('node-${node.node}'),
                    controller: controller,
                    placeholder: state.branch.trim().isEmpty
                        ? 'branch'
                        : state.branch.trim(),
                    onChanged: (text) => cubit.editNode(node.node, text),
                  )
                : Text(
                    'fora de um repositório — fica onde está',
                    key: ValueKey('node-${node.node}-norepo'),
                    style: _hint,
                  ),
          ),
        ],
      ),
    );
  }
}

TextStyle get _hint => TextStyle(
  fontSize: 10,
  color: AppColors.white(0.5),
  decoration: TextDecoration.none,
);

TextStyle get _mono => TextStyle(
  fontFamily: 'Menlo',
  fontSize: 11,
  color: AppColors.white(0.7),
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
          style: TextStyle(
            fontSize: 10,
            color: plan.isFresh ? AppColors.white(0.5) : AppColors.attention,
            decoration: TextDecoration.none,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          plan.folder,
          key: const ValueKey('worktree-folder'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _mono,
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
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 14,
              height: 14,
              margin: const EdgeInsets.only(top: 1),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? AppColors.accent : AppColors.white(0.4),
                ),
              ),
              alignment: Alignment.center,
              child: selected
                  ? Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.accent,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.white(0.9),
                      decoration: TextDecoration.none,
                    ),
                  ),
                  Text(hint, style: _hint),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
