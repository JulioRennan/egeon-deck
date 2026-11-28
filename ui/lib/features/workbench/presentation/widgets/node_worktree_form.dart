import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../commons/widgets/form_dialog.dart';
import '../../../../commons/widgets/form_kit.dart';
import '../../../../core/adapters/injector.dart';
import '../../../../theme/egeon_colors.dart';
import '../../../../theme/egeon_type.dart';
import '../../domain/entities/worktree_source.dart';
import '../cubit/worktree_branch_cubit.dart';

/// Pergunta a branch da worktree de UM terminal (`NodeWorktreePlanner.ask`):
/// a bancada já está montada, e o que se quer é levar um card — o do backend,
/// quase sempre — para uma branch nova sem mexer no resto. A pasta não se
/// edita: vem da branch, pela convenção de sempre, e aparece para conferir.
/// Devolve a branch, ou nulo se cancelou.
Future<String?> showNodeWorktreeForm(
  BuildContext context, {
  required WorktreeSource source,
  required String nodeId,
  required String repo,
  required String currentPath,
  required String suggested,
}) => showFormDialog<String>(
  context,
  width: 460,
  builder: (_, close) => BlocProvider(
    create: (_) =>
        inject<WorktreeBranchCubit>((source: source, suggested: suggested)),
    child: _Body(
      nodeId: nodeId,
      repo: repo,
      currentPath: currentPath,
      close: close,
    ),
  ),
);

class _Body extends StatefulWidget {
  const _Body({
    required this.nodeId,
    required this.repo,
    required this.currentPath,
    required this.close,
  });

  final String nodeId;
  final String repo;
  final String currentPath;
  final void Function([String? branch]) close;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  late final _branch = TextEditingController(
    text: context.read<WorktreeBranchCubit>().branch,
  );

  @override
  void dispose() {
    _branch.dispose();
    super.dispose();
  }

  void _submit(String branch) {
    if (branch.isNotEmpty) widget.close(branch);
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<WorktreeBranchCubit>();
    final (branch, plan) = switch (context.watch<WorktreeBranchCubit>().state) {
      BranchEmpty() => ('', null),
      BranchAsking(:final branch) => (branch, null),
      BranchJudged(:final branch, :final plan) => (branch, plan),
    };
    return FormDialogBody(
      title: 'Worktree para "${widget.nodeId}"',
      message:
          'O terminal passa a abrir na worktree de ${widget.repo}, e sai de '
          '${widget.currentPath}.\n\n'
          'O processo reinicia — não há como trocar o diretório de um pty em '
          'curso — e a conversa do agente começa do zero. Id, papel, arestas '
          'e posição no canvas continuam os mesmos.',
      actions: [
        FormDialogButton('Cancelar', onTap: widget.close),
        FormDialogButton(
          'Abrir',
          primary: true,
          enabled: branch.isNotEmpty,
          onTap: () => _submit(branch),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FormLabel('BRANCH'),
          FormTextField(
            key: const ValueKey('node-worktree-branch'),
            controller: _branch,
            placeholder: 'nome da branch',
            autofocus: true,
            onChanged: cubit.setBranch,
            onSubmitted: () => _submit(branch),
          ),
          const SizedBox(height: 6),
          // O que vai acontecer com o nome escrito (ADR-018): a mesma caixa
          // cria branch e vai para uma que já existe, e sem esta linha as duas
          // são visualmente idênticas. Onde nasce, para conferir.
          SizedBox(
            height: 34,
            child: switch (plan) {
              null => null,
              final plan => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    plan.message ?? '',
                    key: const ValueKey('node-worktree-verdict'),
                    maxLines: 2,
                    style: EgeonType.caption.copyWith(
                      fontSize: 11,
                      color: plan.isFresh
                          ? context.eg.textMuted
                          : context.eg.attention,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  Text(
                    plan.folder,
                    key: const ValueKey('node-worktree-folder'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: EgeonType.monoMeta.copyWith(
                      color: context.eg.textMuted,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            },
          ),
        ],
      ),
    );
  }
}
