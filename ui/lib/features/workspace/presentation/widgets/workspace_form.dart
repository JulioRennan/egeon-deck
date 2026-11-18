import 'package:flutter/widgets.dart';

import '../../../../commons/widgets/app_dialog.dart';
import '../../../../commons/widgets/app_text_field.dart';
import '../../../../commons/widgets/pick_list.dart';
import '../../../../commons/widgets/workspace_badge.dart';
import '../../../../core/adapters/path_picker.dart';
import '../../domain/entities/workspace_draft.dart';
import 'multi_project_editor.dart';

/// O formulário de criar ou editar um workspace: nome, imagem, as pastas (cada
/// uma vira um projeto) e os multi-projetos. Devolve o rascunho, ou `null`.
Future<WorkspaceDraft?> showWorkspaceForm(
  BuildContext context, {
  required WorkspaceDraft initial,
  required bool editing,
  required PathPicker picker,
  required Future<String> Function(List<String> folders) suggestName,
}) => showAppDialog<WorkspaceDraft>(
  context,
  width: 380,
  builder: (_, close) => _FormBody(
    initial: initial,
    editing: editing,
    picker: picker,
    suggestName: suggestName,
    close: close,
  ),
);

class _FormBody extends StatefulWidget {
  const _FormBody({
    required this.initial,
    required this.editing,
    required this.picker,
    required this.suggestName,
    required this.close,
  });

  final WorkspaceDraft initial;
  final bool editing;
  final PathPicker picker;
  final Future<String> Function(List<String> folders) suggestName;
  final void Function([WorkspaceDraft? result]) close;

  @override
  State<_FormBody> createState() => _FormBodyState();
}

class _FormBodyState extends State<_FormBody> {
  late final _name = TextEditingController(text: widget.initial.name);
  late List<String> _folders = [...widget.initial.folders];
  late List<MultiDraft> _multis = [...widget.initial.multis];
  final _selectedFolders = <int>{};
  int? _selectedMulti;
  String? _iconSource;
  bool _clearIcon = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final path = await widget.picker.image();
    if (path == null || !mounted) return;
    setState(() {
      _iconSource = path;
      _clearIcon = false;
    });
  }

  void _dropImage() => setState(() {
    _iconSource = null;
    _clearIcon = widget.initial.icon != null;
  });

  Future<void> _addFolders() async {
    final picked = await widget.picker.folders(prompt: 'Adicionar');
    if (!mounted) return;
    setState(() {
      for (final path in picked) {
        final clean = path.length > 1
            ? path.replaceAll(RegExp(r'/+$'), '')
            : path;
        if (!_folders.contains(clean)) _folders.add(clean);
      }
    });
  }

  void _removeFolders() {
    if (_selectedFolders.isEmpty) return;
    final gone = {for (final i in _selectedFolders) _folders[i]};
    setState(() {
      _folders = [
        for (var i = 0; i < _folders.length; i++)
          if (!_selectedFolders.contains(i)) _folders[i],
      ];
      // A pasta que saiu sai também dos conjuntos: multi-projeto aponta para
      // projeto deste workspace, e ela deixou de ser.
      _multis = [
        for (final m in _multis)
          m.copyWith(
            folders: [
              for (final f in m.folders)
                if (!gone.contains(f)) f,
            ],
          ),
      ];
      _selectedFolders.clear();
    });
  }

  Future<void> _editMulti(int? index) async {
    final draft = index == null ? const MultiDraft(name: '') : _multis[index];
    final result = await showMultiProjectEditor(
      context,
      draft: draft,
      folders: _folders,
      suggestName: widget.suggestName,
    );
    if (result == null || !mounted) return;
    setState(() {
      if (index == null) {
        _multis = [..._multis, result];
      } else {
        _multis = [..._multis]..[index] = result;
      }
    });
  }

  void _removeMulti() {
    final index = _selectedMulti;
    if (index == null) return;
    setState(() {
      _multis = [..._multis]..removeAt(index);
      _selectedMulti = null;
    });
  }

  void _save() {
    final typed = _name.text.trim();
    if (typed.isEmpty) return widget.close();
    widget.close(
      WorkspaceDraft(
        name: typed,
        icon: widget.initial.icon,
        folders: _folders,
        multis: _multis,
        iconSource: _iconSource,
        clearIcon: _clearIcon && _iconSource == null,
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 4),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: Color(0xFFFFFFFF),
        decoration: TextDecoration.none,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final iconPath = _iconSource ?? (_clearIcon ? null : widget.initial.icon);
    return ListenableBuilder(
      listenable: _name,
      builder: (context, _) => DialogBody(
        title: widget.editing ? 'Editar workspace' : 'Novo workspace',
        message:
            'Cada pasta vira um projeto; um multi-projeto junta algumas delas '
            'numa pasta só. As bancadas se organizam por projeto.',
        actions: [
          DialogButton('Cancelar', onTap: widget.close),
          DialogButton(
            widget.editing ? 'Salvar' : 'Criar',
            primary: true,
            enabled: _name.text.trim().isNotEmpty,
            onTap: _save,
          ),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                WorkspaceBadge(
                  name: _name.text.isEmpty ? '?' : _name.text,
                  iconPath: iconPath,
                  side: 44,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppTextField(
                        controller: _name,
                        placeholder: 'nome do workspace',
                        autofocus: true,
                        onSubmitted: _save,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          DialogButton(
                            'Imagem…',
                            small: true,
                            onTap: _pickImage,
                          ),
                          DialogButton(
                            'Sem imagem',
                            small: true,
                            onTap: _dropImage,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            _label('Pastas (projetos)'),
            PickList(
              keyPrefix: 'folder',
              height: 110,
              items: _folders,
              selected: _selectedFolders,
              emptyText: 'Nenhuma pasta ainda.',
              onToggle: (i) => setState(() {
                if (!_selectedFolders.add(i)) _selectedFolders.remove(i);
              }),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                DialogButton(
                  'Adicionar pastas…',
                  small: true,
                  onTap: _addFolders,
                ),
                DialogButton(
                  'Tirar selecionadas',
                  small: true,
                  onTap: _removeFolders,
                ),
              ],
            ),
            _label('Multi-projetos'),
            PickList(
              keyPrefix: 'multi-item',
              height: 70,
              items: [
                for (final m in _multis)
                  '${m.name} — '
                      '${m.foldersLabel.isEmpty ? 'nenhuma pasta' : m.foldersLabel}',
              ],
              selected: {?_selectedMulti},
              onToggle: (i) => setState(() => _selectedMulti = i),
              onOpen: _editMulti,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                DialogButton(
                  'Novo multi-projeto…',
                  small: true,
                  onTap: () => _editMulti(null),
                ),
                DialogButton(
                  'Editar…',
                  small: true,
                  onTap: () {
                    final i = _selectedMulti;
                    if (i != null) _editMulti(i);
                  },
                ),
                DialogButton('Tirar', small: true, onTap: _removeMulti),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
