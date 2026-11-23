import 'package:flutter/widgets.dart';

import '../../../../commons/widgets/form_dialog.dart';
import '../../../../commons/widgets/form_kit.dart';
import '../../../../core/adapters/path_picker.dart';
import '../../../../theme/egeon_colors.dart';
import '../../../../theme/egeon_type.dart';

/// O que o formulário de projeto novo devolve.
class NewProjectInput {
  const NewProjectInput({
    required this.name,
    required this.parent,
    required this.git,
  });

  final String name;
  final String parent;
  final bool git;
}

/// Pede o nome da pasta, onde criá-la e se inicia o git. [problem] é a recusa
/// do core na tentativa anterior: aparece no lugar do texto de apoio, e o que
/// foi digitado volta preenchido.
Future<NewProjectInput?> showNewProjectForm(
  BuildContext context, {
  required String workspaceName,
  required String parent,
  required PathPicker picker,
  String name = '',
  bool git = true,
  String? problem,
}) => showFormDialog<NewProjectInput>(
  context,
  width: 380,
  builder: (_, close) => _Body(
    workspaceName: workspaceName,
    parent: parent,
    picker: picker,
    name: name,
    git: git,
    problem: problem,
    close: close,
  ),
);

class _Body extends StatefulWidget {
  const _Body({
    required this.workspaceName,
    required this.parent,
    required this.picker,
    required this.name,
    required this.git,
    required this.problem,
    required this.close,
  });

  final String workspaceName;
  final String parent;
  final PathPicker picker;
  final String name;
  final bool git;
  final String? problem;
  final void Function([NewProjectInput? result]) close;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  late final _name = TextEditingController(text: widget.name);
  late String _parent = widget.parent;
  late bool _git = widget.git;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _choose() async {
    final path = await widget.picker.folder(
      prompt: 'Escolher',
      initialDirectory: _parent,
    );
    if (path == null || !mounted) return;
    setState(() => _parent = path);
  }

  void _create() {
    final typed = _name.text.trim();
    if (typed.isEmpty) return widget.close();
    widget.close(NewProjectInput(name: typed, parent: _parent, git: _git));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _name,
    builder: (context, _) => FormDialogBody(
      title: 'Novo projeto em "${widget.workspaceName}"',
      message:
          widget.problem ??
          'Cria a pasta e a põe no workspace. Pasta que já existe com esse '
              'nome é só adicionada.',
      actions: [
        FormDialogButton('Cancelar', onTap: widget.close),
        FormDialogButton(
          'Criar',
          primary: true,
          enabled: _name.text.trim().isNotEmpty,
          onTap: _create,
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FormTextField(
            controller: _name,
            placeholder: 'nome da pasta',
            autofocus: true,
            onSubmitted: _create,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                'em',
                style: EgeonType.caption.copyWith(
                  color: context.eg.textSecondary,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _parent,
                  key: const ValueKey('new-project-parent'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: EgeonType.monoMeta.copyWith(
                    color: context.eg.textPrimary,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FormDialogButton('Escolher…', small: true, onTap: _choose),
            ],
          ),
          const SizedBox(height: 10),
          FormCheckbox(
            key: const ValueKey('git-box'),
            label: 'Iniciar repositório git',
            on: _git,
            onChanged: (v) => setState(() => _git = v),
          ),
        ],
      ),
    ),
  );
}
