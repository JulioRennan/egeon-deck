import 'package:egeon_deck/features/node/web/domain/repository/socket_web_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/protocol_fixtures.dart';
import '../../../support/pump.dart';
import '../../../support/socket_fixture_harness.dart';

void main() {
  late SocketHarness harness;
  late SocketWebRepository repository;
  final commands = loadProtocolFixture('commands');
  final events = loadProtocolFixture('events');
  const wb = '1a2b3c4d';

  setUp(() async {
    harness = await SocketHarness.start();
    repository = SocketWebRepository(harness.client, wb);
  });
  tearDown(() => harness.dispose());

  test('o estado traz a URL, o perfil e o UUID do data store', () async {
    final first = repository.watch('docs').first;
    await pump();
    harness.connection.say(events['node_web']!);
    final state = await first;
    expect(state.url, 'https://docs.rs');
    expect(state.profile, 'padrão');
    expect(state.profileId, '3f2a9c1e-5b7d-4e8a-9c0b-1d2e3f4a5b6c');
    expect(state.profiles, ['padrão', 'trabalho']);
  });

  test('os comandos batem com as fixtures', () async {
    expect(
      await harness.sent(() => repository.navigate('docs', 'docs.rs/tokio')),
      withoutId(commands['web_navigate']!),
    );
    expect(
      await harness.sent(
        () => repository.reportNavigated(
          'docs',
          'https://docs.rs/tokio/latest/tokio/',
        ),
      ),
      withoutId(commands['web_navigated']!),
    );
    expect(
      await harness.sent(() => repository.setProfile('docs', 'trabalho')),
      withoutId(commands['web_set_profile']!),
    );
    expect(wb, commands['web_navigate']!['workbench']);
  });
}
