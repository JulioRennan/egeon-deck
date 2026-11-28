import 'dart:async';

import 'package:egeon_deck/features/usage/domain/entities/usage_view.dart';
import 'package:egeon_deck/features/usage/domain/repository/usage_repository.dart';

/// O consumo de mentira: o teste empurra o que o core mandaria.
class FakeUsageRepository implements UsageRepository {
  FakeUsageRepository([UsageView? first]) : _last = first;

  UsageView? _last;
  final _changes = StreamController<UsageView>.broadcast();
  final watched = <String>[];

  void push(UsageView view) {
    _last = view;
    _changes.add(view);
  }

  @override
  Stream<UsageView> watch(String workbenchId) {
    watched.add(workbenchId);
    late final StreamController<UsageView> controller;
    StreamSubscription<UsageView>? inner;
    controller = StreamController<UsageView>(
      onListen: () {
        final last = _last;
        if (last != null) controller.add(last);
        inner = _changes.stream.listen(controller.add);
      },
      onCancel: () => inner?.cancel(),
    );
    return controller.stream;
  }
}

/// Um painel como o core o mandaria, com tudo que o Swift mostra.
Map<String, Object?> sampleUsage() => {
  'pill': {'text': 'US\$ 12,34', 'tooltip': 'Esta bancada · 1,2M tokens'},
  'panel': {
    'heading': 'Nexus · bancada',
    'total': {'amount': 'US\$ 12,34', 'tokens': '1,2M tokens'},
    'split': [
      {
        'key': 'output',
        'title': 'Saída',
        'amount': 'US\$ 6,00',
        'detail': '300K tokens',
        'dollars': 6.0,
      },
      {
        'key': 'input',
        'title': 'Entrada',
        'amount': 'US\$ 3,00',
        'detail': '600K tokens',
        'dollars': 3.0,
      },
      {
        'key': 'cache_write',
        'title': 'Cache escrito',
        'amount': 'US\$ 2,34',
        'detail': '200K tokens',
        'dollars': 2.34,
      },
      {
        'key': 'cache_read',
        'title': 'Cache lido',
        'amount': 'US\$ 1,00',
        'detail': '100K tokens',
        'dollars': 1.0,
      },
    ],
    'agents': [
      {
        'name': 'claude',
        'tag': 'Opus 5.5',
        'amount': 'US\$ 9,00',
        'fraction': 1.0,
        'detail': 'saída 200K · cache lido 80K',
      },
      {
        'name': 'dev',
        'amount': 'US\$ 3,34',
        'fraction': 0.37,
        'detail': 'saída 100K · cache lido 20K',
      },
    ],
    'models': [
      {
        'name': 'Opus 5.5',
        'family': 'opus',
        'amount': 'US\$ 9,00',
        'fraction': 1.0,
        'detail': '800K tokens',
      },
      {
        'name': 'Sonnet 5.5',
        'family': 'sonnet',
        'amount': 'US\$ 3,34',
        'fraction': 0.37,
        'detail': '400K tokens',
      },
    ],
    'prices': {
      'open_note': 'US\$ por milhão de tokens',
      'columns': ['', 'Entrada', 'Saída', '5 min', '1 h', 'Lido'],
      'rows': [
        {
          'name': 'Opus 5.5',
          'lit': true,
          'edited': false,
          'values': ['5,00', '25,00', '6,25', '10,00', '0,50'],
        },
        {
          'name': 'Haiku',
          'lit': false,
          'edited': true,
          'values': ['1,00', '5,00', '1,25', '2,00', '0,10'],
        },
      ],
      'origin_note': 'Preços do Claude Code instalado · ✎ = seu pricing.json · modo rápido custa 2×',
      'rule_note':
          'Custo no preço do dia do gasto: tabela nova vale daqui para frente.',
      'file_note': 'Exceções em ~/.egeon/pricing.json',
    },
  },
};
