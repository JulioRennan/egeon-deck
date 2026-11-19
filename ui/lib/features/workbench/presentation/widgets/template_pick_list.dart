import 'package:flutter/widgets.dart';

import '../../../../commons/widgets/pick_list.dart';
import '../../domain/entities/bench_template.dart';

/// "Começar vazia" e os templates de bancada, um só marcado. [chosen] nulo é
/// começar vazia.
class TemplatePickList extends StatelessWidget {
  const TemplatePickList({
    required this.templates,
    required this.chosen,
    required this.onChoose,
    this.height = 110,
    super.key,
  });

  static const empty = 'Começar vazia';

  final List<BenchTemplate> templates;
  final String? chosen;
  final ValueChanged<String?> onChoose;
  final double height;

  @override
  Widget build(BuildContext context) {
    final index = templates.indexWhere((t) => t.name == chosen);
    return PickList(
      keyPrefix: 'template',
      height: height,
      items: [
        empty,
        for (final template in templates)
          '${template.name} · ${template.nodes} '
              '${template.nodes == 1 ? 'nó' : 'nós'}',
      ],
      selected: {index + 1},
      onToggle: (row) => onChoose(row == 0 ? null : templates[row - 1].name),
    );
  }
}
