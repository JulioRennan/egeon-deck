import 'package:egeon_deck/core/adapters/event_parsing.dart';
import 'package:egeon_deck/features/node/agent/domain/entities/agent_status.dart';
import 'package:egeon_deck/features/node/agent/domain/entities/model_choice.dart';
import 'package:egeon_deck/features/node/agent/domain/repository/socket_agent_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/protocol_fixtures.dart';
import '../../../support/pump.dart';
import '../../../support/socket_fixture_harness.dart';

/// O agente contra as fixtures do core (decisão 31).
void main() {
  late SocketHarness harness;
  late SocketAgentRepository repository;
  final commands = loadProtocolFixture('commands');
  final events = loadProtocolFixture('events');
  const wb = '1a2b3c4d';

  setUp(() async {
    harness = await SocketHarness.start();
    repository = SocketAgentRepository(harness.client, wb);
  });
  tearDown(() => harness.dispose());

  test('assina node/<bancada>/<nó> e lê o estado do agente', () async {
    final first = repository.watch('claude').first;
    await pump();
    expect(
      withoutId(harness.connection.sent.single),
      withoutId(commands['subscribe_node']!),
    );
    harness.connection.say(events['node_agent']!);
    final AgentStatus status = await first;

    expect(status.modelTitle, 'Opus 5.5');
    expect(status.offersModel, isTrue);
    expect(status.models.where((m) => m.selected).single.value, 'opus');
    expect(status.models.first.group, ModelGroup.standard);
    expect(status.dial.levels, ['low', 'medium', 'high', 'xhigh', 'max']);
    expect(status.dial.markIndex, 2);
    expect(status.dial.label, 'high');
    expect(status.dial.pending, isFalse);
    expect(status.ultracode!.available, isTrue);
    expect(status.context!.used, 84000);
    expect(status.clearable, isTrue);
  });

  test(
    'o agente recém-aberto (medidor sem números) chega do mesmo jeito',
    () async {
      final first = repository.watch('claude').first;
      await pump();
      harness.connection.say(events['node_agent_novo']!);
      final status = await first;

      expect(status.modelTitle, 'padrão');
      expect(status.offersModel, isTrue);
      expect(status.context, isNull);
      expect(status.dial.levels, ['low', 'medium', 'high']);
    },
  );

  group('evento ilegível', () {
    late List<String> failures;

    setUp(() {
      failures = [];
      final previous = ParseFailures.sink;
      ParseFailures.reset();
      ParseFailures.sink = (what, error, stack) => failures.add(what);
      addTearDown(() {
        ParseFailures.sink = previous;
        ParseFailures.reset();
      });
    });

    Map<String, Object?> broken() => {
      ...events['node_agent']!,
      'agent': {'model_title': 'x', 'dial': 'quebrado'},
    };

    test('antes do primeiro estado bom: a faixa mostra o que der', () async {
      final seen = <AgentStatus>[];
      final sub = repository.watch('claude').listen(seen.add);
      await pump();
      harness.connection.say(broken());
      await pump();
      harness.connection.say(events['node_agent']!);
      await pump();

      expect(failures, ['node/$wb/claude']);
      expect(seen, hasLength(2));
      expect(seen.first.modelTitle, 'padrão');
      expect(seen.last.modelTitle, 'Opus 5.5');
      await sub.cancel();
    });

    test('depois de um estado bom: nada emitido, o último continua', () async {
      final seen = <AgentStatus>[];
      final sub = repository.watch('claude').listen(seen.add);
      await pump();
      harness.connection.say(events['node_agent']!);
      await pump();
      harness.connection.say(broken());
      await pump();

      expect(failures, hasLength(1));
      expect(seen.single.modelTitle, 'Opus 5.5');
      await sub.cancel();
    });

    test('a mesma falha repetida registra uma linha só', () async {
      final sub = repository.watch('claude').listen((_) {});
      await pump();
      harness.connection.say(broken());
      harness.connection.say(broken());
      harness.connection.say(broken());
      await pump();

      expect(failures, hasLength(1));
      expect(ParseFailures.counts.values.single, 3);
      await sub.cancel();
    });
  });

  test('o estado do nó web ou da fila não vira agente', () async {
    final seen = <AgentStatus>[];
    final sub = repository.watch('claude').listen(seen.add);
    await pump();
    harness.connection.say({
      ...events['node_queue']!,
      'topic': 'node/$wb/claude',
    });
    await pump();
    expect(seen, isEmpty);
    await sub.cancel();
  });

  test('as intenções do seletor batem com as fixtures', () async {
    expect(
      await harness.sent(
        () => repository.choose('claude', const EffortMove(3)),
      ),
      withoutId(commands['effort_move']!),
    );
    expect(
      await harness.sent(
        () => repository.choose('claude', const EffortToggleAuto()),
      ),
      withoutId(commands['effort_toggle_auto']!),
    );
    expect(
      await harness.sent(
        () => repository.choose('claude', const EffortSettle()),
      ),
      withoutId(commands['effort_settle']!),
    );
  });

  test('limpar a conversa é node_clear', () async {
    expect(
      await harness.sent(() => repository.clear('claude')),
      withoutId(commands['node_clear']!),
    );
  });

  test('tentar agora é retry com now', () async {
    expect(
      await harness.sent(() => repository.retry('claude', now: true)),
      withoutId(commands['retry']!),
    );
  });

  test('modelo e ultracode vão em set_node, só o campo mexido', () async {
    final model = await harness.sent(
      () => repository.choose('claude', const ModelPick('sonnet')),
    );
    expect(model['cmd'], 'set_node');
    expect(only(model, ['workbench', 'node', 'model']), {
      'workbench': wb,
      'node': 'claude',
      'model': 'sonnet',
    });
    expect(model.containsKey('role'), isFalse);

    final standard = await harness.sent(
      () => repository.choose('claude', const ModelPick(null)),
    );
    expect(
      standard.containsKey('model') && standard['model'] == null,
      isTrue,
      reason: 'padrão do CLI é a chave com valor nulo',
    );

    final ultracode = await harness.sent(
      () => repository.choose('claude', const UltracodePick(on: true)),
    );
    expect(ultracode['ultracode'], isTrue);
  });
}
