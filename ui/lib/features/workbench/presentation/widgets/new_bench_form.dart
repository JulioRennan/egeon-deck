import 'package:flutter/widgets.dart';

import '../../../../commons/widgets/form_dialog.dart';
import '../../../../commons/widgets/form_kit.dart';
import '../../domain/entities/bench_template.dart';

/// O que o formulário de bancada nova devolve: o nome (vazio deixa o core
/// nomear) e o template escolhido, ou nenhum para começar vazia.
class NewBenchInput {
  const NewBenchInput({required this.name, this.template});

  final String name;
  final String? template;
}

/// Nome e template numa janela só — são a mesma decisão ("o que é esta
/// bancada"). O nome é a primeira parte do endereço de dispatch.
Future<NewBenchInput?> showNewBenchForm(
  BuildContext context, {
  required String suggested,
  required List<BenchTemplate> templates,
  String? problem,
}) => showFormDialog<NewBenchInput>(
  context,
  width: 340,
  builder: (_, close) => _Body(
    suggested: suggested,
    templates: templates,
    problem: problem,
    close: close,
  ),
);

class _Body extends StatefulWidget {
  const _Body({
    required this.suggested,
    required this.templates,
    required this.problem,
    required this.close,
  });

  final String suggested;
  final List<BenchTemplate> templates;
  final String? problem;
  final void Function([NewBenchInput? result]) close;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  static const _empty = 'Começar vazia';

  late final _name = TextEditingController(text: widget.suggested);

  /// 0 é "Começar vazia"; os templates vêm depois.
  var _chosen = 0;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _create() {
    final typed = _name.text.trim();
    widget.close(
      NewBenchInput(
        name: typed.isEmpty ? widget.suggested : typed,
        template: _chosen == 0 ? null : widget.templates[_chosen - 1].name,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FormDialogBody(
    title: 'Nova bancada',
    message:
        widget.problem ?? 'O nome é a primeira parte do endereço de dispatch.',
    actions: [
      FormDialogButton('Cancelar', onTap: widget.close),
      FormDialogButton('Criar', primary: true, onTap: _create),
    ],
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FormTextField(
          controller: _name,
          placeholder: 'nome da bancada',
          autofocus: true,
          onSubmitted: _create,
        ),
        const SizedBox(height: 10),
        const FormLabel('TEMPLATE'),
        PickList(
          keyPrefix: 'template',
          height: 110,
          items: [
            _empty,
            for (final template in widget.templates)
              '${template.name} · ${template.nodes} '
                  '${template.nodes == 1 ? 'nó' : 'nós'}',
          ],
          selected: {_chosen},
          onToggle: (index) => setState(() => _chosen = index),
        ),
      ],
    ),
  );
}
