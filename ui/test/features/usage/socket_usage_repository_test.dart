import 'package:egeon_deck/features/usage/domain/entities/usage_view.dart';
import 'package:egeon_deck/features/usage/domain/repository/socket_usage_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/protocol_fixtures.dart';
import '../../support/pump.dart';
import '../../support/socket_fixture_harness.dart';

/// O consumo contra a fixture `usage` do core.
void main() {
  late SocketHarness harness;
  late SocketUsageRepository repository;
  final events = loadProtocolFixture('events');

  setUp(() async {
    harness = await SocketHarness.start();
    repository = SocketUsageRepository(harness.client);
  });
  tearDown(() => harness.dispose());

  test(
    'assina workbench/<id>/usage e lê a pastilha e o painel prontos',
    () async {
      final first = repository.watch('1a2b3c4d').first;
      await pump();
      expect(
        harness.connection.sent.single['topic'],
        'workbench/1a2b3c4d/usage',
      );
      harness.connection.say(events['usage']!);
      final view = await first;

      expect(view.pill.text, 'US\$ 1,23');
      expect(view.pill.tooltip, 'Consumo da bancada');

      final panel = view.panel!;
      expect(panel.heading, 'CONSUMO DA BANCADA');
      expect(panel.totalAmount, 'US\$ 12,34');
      expect(panel.totalTokens, '1,2M tokens');
      expect(panel.split.map((s) => s.tariff), [
        Tariff.output,
        Tariff.input,
        Tariff.cacheWrite,
        Tariff.cacheRead,
      ]);
      expect(panel.split.first.dollars, 6.0);
      expect(panel.agents.single.name, 'claude');
      expect(panel.agents.single.tag, 'maestro');
      expect(panel.agents.single.fraction, 1.0);
      expect(panel.models.single.family, 'opus');
      expect(panel.prices.columns, [
        '',
        'Entrada',
        'Saída',
        '5 min',
        '1 h',
        'Lido',
      ]);
      expect(panel.prices.rows.single.lit, isTrue);
      expect(panel.prices.rows.single.values.last, '0,500');
      expect(panel.prices.fileNote, '~/.egeon-next/pricing.json');
      expect(panel.prices.ruleNote, startsWith('Cache gravado'));
    },
  );

  test('o consumo de outra bancada não chega', () async {
    final seen = <UsageView>[];
    final sub = repository.watch('outra').listen(seen.add);
    await pump();
    harness.connection.say(events['usage']!);
    await pump();
    expect(seen, isEmpty);
    await sub.cancel();
  });
}
