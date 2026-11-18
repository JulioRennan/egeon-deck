import 'package:egeon_deck/features/processes/domain/repository/socket_processes_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/protocol_fixtures.dart';
import '../../support/pump.dart';
import '../../support/socket_fixture_harness.dart';

/// Os processos contra as fixtures do core.
void main() {
  late SocketHarness harness;
  late SocketProcessesRepository repository;
  final commands = loadProtocolFixture('commands');
  final replies = loadProtocolFixture('replies');

  setUp(() async {
    harness = await SocketHarness.start();
    repository = SocketProcessesRepository(harness.client);
  });
  tearDown(() => harness.dispose());

  test(
    'a lista vem pronta: ordem, idade, resumo, órfãos e a limpeza',
    () async {
      final view = await _list(harness, repository, replies['processes']!);
      expect(
        harness.connection.sent.first['cmd'],
        commands['processes']!['cmd'],
      );

      expect(view.rows.map((r) => r.pid), [4242, 4243]);
      expect(view.rows.first.node, 'deck/claude');
      expect(view.rows.first.orphan, isTrue);
      expect(view.rows.first.age, '19 d 4 h');
      expect(view.rows.last.node, isNull, reason: 'sem nó é o app');
      expect(view.summary, startsWith('1 no app · 1 órfão'));
      expect(
        view.orphans,
        1,
        reason: 'o core manda o número, a UI não recalcula',
      );
      expect(view.enabled, isTrue);
    },
  );

  test('o ensaio de encerrar órfãos devolve a pergunta escrita', () async {
    final ensaio = replies['processes_reap_ensaio']!;
    final future = repository.confirmReap();
    await pump();
    final sent = harness.connection.sent.last;
    expect(withoutId(sent), withoutId(commands['processes_reap_ensaio']!));
    harness.connection.say({...ensaio, 're': sent['id']});
    final confirm = await future;
    expect(confirm.title, 'Encerrar 1 processo órfão?');
    expect(confirm.detail, contains('SIGTERM'));
  });

  test('o ensaio de encerrar escolhidos manda os pids com dry_run', () async {
    final sent = await harness.sent(
      () => repository.confirmKill([4242, 4243]),
      reply: {'title': 'Encerrar 2 processos?', 'detail': 'x'},
    );
    expect(sent['dry_run'], isTrue);
    expect(sent['pids'], [4242, 4243]);
    expect(sent['cmd'], 'processes_kill');
  });

  test('encerrar de verdade manda dry_run falso e relê a lista', () async {
    final future = repository.kill([4242, 4243]);
    await pump();
    final kill = harness.connection.sent.last;
    expect(withoutId(kill), withoutId(commands['processes_kill']!));
    harness.connection.say({'re': kill['id'], 'ok': true});
    await pump();
    // A resposta não é a lista: a varredura seguinte mostra o que morreu.
    final relist = harness.connection.sent.last;
    expect(relist['cmd'], 'processes');
    harness.connection.say({...replies['processes']!, 're': relist['id']});
    final view = await future;
    expect(view.rows, hasLength(2));
  });

  test('encerrar órfãos de verdade usa processes_reap sem ensaio', () async {
    final future = repository.reap();
    await pump();
    final reap = harness.connection.sent.last;
    expect(reap['cmd'], 'processes_reap');
    expect(reap['dry_run'], isFalse);
    harness.connection.say({'re': reap['id'], 'ok': true});
    await pump();
    final relist = harness.connection.sent.last;
    harness.connection.say({...replies['processes']!, 're': relist['id']});
    await future;
  });

  test('a leitura que não terminou é erro do core', () async {
    final future = repository.list();
    await pump();
    harness.connection.say({
      ...replies['processes_erro_leitura']!,
      're': harness.connection.sent.last['id'],
    });
    expect(future, throwsA(isA<Object>()));
  });
}

Future<dynamic> _list(
  SocketHarness harness,
  SocketProcessesRepository repository,
  Map<String, Object?> reply,
) async {
  final future = repository.list();
  await pump();
  harness.connection.say({...reply, 're': harness.connection.sent.last['id']});
  return future;
}
