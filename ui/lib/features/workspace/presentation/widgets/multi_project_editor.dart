import 'package:flutter/widgets.dart';

import '../../../../commons/widgets/form_dialog.dart';
import '../../../../commons/widgets/form_kit.dart';
import '../../../../theme/egeon_colors.dart';
import '../../../../theme/egeon_tokens.dart';
import '../../domain/entities/workspace_draft.dart';
import '../../domain/errors/workspace_error.dart';

/// Marca as pastas que a bancada vai ver juntas. Sem pasta no workspace não há
/// o que juntar: avisa e devolve `null`.
Future<MultiDraft?> showMultiProjectEditor(
  BuildContext context, {
  required MultiDraft draft,
  required List<String> folders,
  required Future<String> Function(List<String> folders) suggestName,
}) {
  // Pasta do rascunho que o workspace não tem mais — tirada lá em cima e
  // escolhida aqui antes — não some da lista sem você ver.
  final all = [
    ...folders,
    for (final f in draft.folders)
      if (!folders.contains(f)) f,
  ];
  if (all.isEmpty) {
    return showFormDialog<MultiDraft>(
      context,
      builder: (_, close) => FormDialogBody(
        title: 'Novo multi-projeto',
        message:
            'Adicione antes as pastas do workspace — o multi-projeto junta '
            'algumas delas.',
        actions: [FormDialogButton('Entendi', primary: true, onTap: close)],
      ),
    );
  }
  return showFormDialog<MultiDraft>(
    context,
    builder: (_, close) => _EditorBody(
      draft: draft,
      folders: all,
      suggestName: suggestName,
      close: close,
    ),
  );
}

class _EditorBody extends StatefulWidget {
  const _EditorBody({
    required this.draft,
    required this.folders,
    required this.suggestName,
    required this.close,
  });

  final MultiDraft draft;
  final List<String> folders;
  final Future<String> Function(List<String> folders) suggestName;
  final void Function([MultiDraft? result]) close;

  @override
  State<_EditorBody> createState() => _EditorBodyState();
}

class _EditorBodyState extends State<_EditorBody> {
  late final _name = TextEditingController(text: widget.draft.name);
  late final Set<String> _chosen = {...widget.draft.folders};

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _isNew => widget.draft.id == null && widget.draft.name.isEmpty;

  Future<void> _save() async {
    final folders = [
      for (final f in widget.folders)
        if (_chosen.contains(f)) f,
    ];
    if (folders.isEmpty) return widget.close();
    var name = _name.text.trim();
    // Sem nome digitado, quem nomeia é o core, igual faria ao salvar.
    if (name.isEmpty) {
      try {
        name = await widget.suggestName(folders);
      } on WorkspaceError {
        name = '';
      }
    }
    widget.close(widget.draft.copyWith(name: name, folders: folders));
  }

  @override
  Widget build(BuildContext context) => FormDialogBody(
    title: _isNew ? 'Novo multi-projeto' : 'Editar multi-projeto',
    message:
        'Marque as pastas que a bancada vai ver juntas, cada uma numa '
        'subpasta.',
    actions: [
      FormDialogButton('Cancelar', onTap: widget.close),
      FormDialogButton('OK', primary: true, onTap: _save),
    ],
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FormTextField(
          controller: _name,
          placeholder: 'nome do multi-projeto',
          autofocus: true,
        ),
        const SizedBox(height: 10),
        DecoratedBox(
          decoration: BoxDecoration(
            color: context.eg.obsidian,
            borderRadius: BorderRadius.circular(EgeonRadius.md),
            border: Border.all(color: context.eg.line),
          ),
          child: SizedBox(
            height: 180,
            child: ListView(
              padding: const EdgeInsets.all(8),
              children: [
                for (final folder in widget.folders)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: FormCheckbox(
                      key: ValueKey('multi-$folder'),
                      label: folder,
                      on: _chosen.contains(folder),
                      onChanged: (_) => setState(() {
                        if (!_chosen.add(folder)) _chosen.remove(folder);
                      }),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
