import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../commons/widgets/app_dialog.dart';
import '../../../../commons/widgets/app_text_field.dart';
import '../../../../commons/widgets/form_label.dart';
import '../../../../core/adapters/injector.dart';
import '../../../../theme/app_colors.dart';
import '../../domain/entities/bench_template.dart';
import '../../domain/entities/worktree_info.dart';
import '../cubit/multi_worktree_form_cubit.dart';
import 'template_pick_list.dart';

/// O que o formulário de multi-projeto devolve.
class MultiWorktreeInput {
  const MultiWorktreeInput({
    required this.branch,
    required this.repos,
    this.template,
  });

  final String branch;

  /// Só os repositórios com branch diferente da da bancada.
  final Map<String, String> repos;
  final String? template;
}

/// Branch da bancada e de cada repositório de um multi-projeto (ADR-065).
/// [templates] nulo é duplicar uma bancada: os nós vêm dela.
Future<MultiWorktreeInput?> showMultiWorktreeForm(
  BuildContext context, {
  required MultiWorktree multi,
  List<BenchTemplate>? templates,
}) => showAppDialog<MultiWorktreeInput>(
  context,
  width: 380,
  builder: (_, close) => BlocProvider(
    create: (_) => inject<MultiWorktreeFormCubit>(multi.repos),
    child: _Body(project: multi.project, templates: templates, close: close),
  ),
);

class _Body extends StatefulWidget {
  const _Body({
    required this.project,
    required this.templates,
    required this.close,
  });

  final String project;
  final List<BenchTemplate>? templates;
  final void Function([MultiWorktreeInput? result]) close;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  final _branch = TextEditingController();
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

  TextEditingController _row(String repo) =>
      _rows.putIfAbsent(repo, TextEditingController.new);

  void _submit(MultiWorktreeFormState state) {
    if (!state.canOpen) return;
    widget.close(
      MultiWorktreeInput(
        branch: state.branch.trim(),
        repos: state.overrides,
        template: _template,
      ),
    );
  }

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<MultiWorktreeFormCubit, MultiWorktreeFormState>(
        // As linhas que acompanham a bancada mostram a branch dela.
        listenWhen: (before, now) => before.branch != now.branch,
        listener: (context, state) {
          for (final repo in state.repos) {
            if (state.follows(repo)) _row(repo).text = state.branch;
          }
        },
        builder: (context, state) {
          final cubit = context.read<MultiWorktreeFormCubit>();
          final templates = widget.templates;
          return DialogBody(
            title: 'Worktree de ${widget.project}',
            message:
                'Todos numa pasta só, com o nome da branch da bancada. Cada '
                'repo segue essa branch, a não ser que você troque a dele. '
                'Branch que já existe é aberta, não recriada.',
            actions: [
              DialogButton('Cancelar', onTap: widget.close),
              DialogButton(
                'Abrir',
                primary: true,
                enabled: state.canOpen,
                onTap: () => _submit(state),
              ),
            ],
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const FormLabel('BRANCH DA BANCADA'),
                AppTextField(
                  key: const ValueKey('multi-branch'),
                  controller: _branch,
                  placeholder: 'ex.: feat/login',
                  autofocus: true,
                  onChanged: cubit.setBranch,
                  onSubmitted: () => _submit(state),
                ),
                const SizedBox(height: 10),
                const FormLabel('POR REPOSITÓRIO'),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 180),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final repo in state.repos)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 122,
                                child: Text(
                                  repo,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.white(0.8),
                                    decoration: TextDecoration.none,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: AppTextField(
                                  key: ValueKey('repo-$repo'),
                                  controller: _row(repo),
                                  placeholder: 'a mesma da bancada',
                                  onChanged: (text) =>
                                      cubit.editRepo(repo, text),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
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
        },
      );
}
