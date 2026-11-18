import 'package:flutter/widgets.dart';

import '../../../../commons/widgets/app_dialog.dart';
import '../../../../commons/widgets/app_text_field.dart';
import '../../../../theme/app_colors.dart';
import '../../domain/entities/workspace_draft.dart';

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
    return showAppDialog<MultiDraft>(
      context,
      builder: (_, close) => DialogBody(
        title: 'Novo multi-projeto',
        message:
            'Adicione antes as pastas do workspace — o multi-projeto junta '
            'algumas delas.',
        actions: [DialogButton('Entendi', primary: true, onTap: close)],
      ),
    );
  }
  return showAppDialog<MultiDraft>(
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
      } on Object {
        name = '';
      }
    }
    widget.close(widget.draft.copyWith(name: name, folders: folders));
  }

  @override
  Widget build(BuildContext context) => DialogBody(
    title: _isNew ? 'Novo multi-projeto' : 'Editar multi-projeto',
    message:
        'Marque as pastas que a bancada vai ver juntas, cada uma numa '
        'subpasta.',
    actions: [
      DialogButton('Cancelar', onTap: widget.close),
      DialogButton('OK', primary: true, onTap: _save),
    ],
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppTextField(
          controller: _name,
          placeholder: 'nome do multi-projeto',
          autofocus: true,
        ),
        const SizedBox(height: 10),
        Container(
          height: 180,
          decoration: BoxDecoration(
            color: AppColors.black(0.25),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.white(0.14)),
          ),
          child: ListView(
            children: [
              for (final folder in widget.folders)
                _Check(
                  key: ValueKey('multi-$folder'),
                  label: folder,
                  on: _chosen.contains(folder),
                  onTap: () => setState(() {
                    if (!_chosen.add(folder)) _chosen.remove(folder);
                  }),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _Check extends StatelessWidget {
  const _Check({
    required this.label,
    required this.on,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Row(
          children: [
            Container(
              width: 14,
              height: 14,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? AppColors.accent : null,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                  color: on ? AppColors.accent : AppColors.white(0.4),
                ),
              ),
              child: on
                  ? const Text(
                      '✓',
                      style: TextStyle(
                        fontSize: 10,
                        height: 1,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFFFFFFF),
                        decoration: TextDecoration.none,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFFFFFFFF),
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
