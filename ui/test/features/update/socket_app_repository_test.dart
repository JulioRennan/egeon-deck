import 'package:egeon_deck/features/update/domain/entities/app_effect.dart';
import 'package:egeon_deck/features/update/domain/entities/app_snapshot.dart';
import 'package:egeon_deck/features/update/domain/repository/socket_app_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/protocol_fixtures.dart';
import '../../support/pump.dart';
import '../../support/socket_fixture_harness.dart';

/// O tópico `app` contra as fixtures do core (decisão 34).
void main() {
  late SocketHarness harness;
  late SocketAppRepository repository;
  final commands = loadProtocolFixture('commands');
  final events = loadProtocolFixture('events');

  setUp(() async {
    harness = await SocketHarness.start();
    repository = SocketAppRepository(harness.client);
  });
  tearDown(() => harness.dispose());

  group('o estado', () {
    test('parado: o menu de procurar e a limpeza ligada', () async {
      final first = repository.watch().first;
      await pump();
      expect(
        withoutId(harness.connection.sent.single),
        withoutId(commands['subscribe_app']!),
      );
      harness.connection.say(events['app_idle']!);
      final AppSnapshot state = await first;

      expect(state.update.phase, UpdatePhase.idle);
      expect(state.update.menu, 'Procurar atualizações…');
      expect(state.update.menuEnabled, isTrue);
      expect(state.update.auto, isFalse);
      expect(state.update.installed, '1.6.0');
      expect(state.update.staged, isFalse);
      expect(state.reaperEnabled, isTrue);
    });

    test('pronta: o menu vira "reiniciar" e a limpeza desligada', () async {
      final first = repository.watch().first;
      await pump();
      harness.connection.say(events['app_update_ready']!);
      final state = await first;
      expect(state.update.phase, UpdatePhase.ready);
      expect(state.update.version, '1.7.0');
      expect(state.update.menu, 'Reiniciar para atualizar para a versão 1.7.0');
      expect(state.update.staged, isTrue);
      expect(state.update.auto, isTrue);
      expect(state.reaperEnabled, isFalse);
    });

    test('efeito não vira estado', () async {
      final seen = <AppSnapshot>[];
      final sub = repository.watch().listen(seen.add);
      await pump();
      harness.connection.say(events['app_terminate']!);
      await pump();
      expect(seen, isEmpty);
      await sub.cancel();
    });
  });

  group('os efeitos', () {
    test('o aviso de versão nova traz tudo pronto', () async {
      final first = repository.effects().first;
      await pump();
      harness.connection.say(events['app_update_prompt']!);
      final prompt = await first as UpdatePrompt;
      expect(prompt.version, '1.7.0');
      expect(prompt.title, 'Versão 1.7.0 do Egeon Deck disponível');
      expect(prompt.text, contains('Reiniciar encerra o que estiver rodando'));
      expect(prompt.auto, isFalse);
      expect(prompt.acceptLabel, 'Atualizar e reiniciar');
      expect(prompt.laterLabel, 'Depois');
      expect(prompt.autoLabel, startsWith('Atualizar automaticamente'));
    });

    test(
      'mensagem, encerrar e abrir Processos; ui_request é da casca',
      () async {
        final seen = <AppEffect>[];
        final sub = repository.effects().listen(seen.add);
        await pump();
        harness.connection.say(events['app_update_message']!);
        harness.connection.say(events['app_terminate']!);
        harness.connection.say(events['app_show_processes']!);
        harness.connection.say(events['app_ui_request']!);
        harness.connection.say(events['app_idle']!);
        await pump();

        expect(seen, hasLength(3));
        final message = seen[0] as UpdateMessage;
        expect(message.title, 'Você está na última versão');
        expect(message.text, 'Egeon Deck 1.6.0.');
        expect(seen[1], isA<Terminate>());
        expect(seen[2], isA<ShowProcesses>());
        await sub.cancel();
      },
    );
  });

  test('os gestos batem com as fixtures', () async {
    expect(
      await harness.sent(
        () => repository.answerUpdate(
          version: '1.7.0',
          accept: true,
          auto: false,
        ),
      ),
      withoutId(commands['update_answer']!),
    );
    expect(
      await harness.sent(() => repository.setUpdateAuto(on: true)),
      withoutId(commands['update_auto']!),
    );
    expect(
      await harness.sent(() => repository.pressUpdateMenu()),
      withoutId(commands['update_menu']!),
    );
    expect(
      await harness.sent(() => repository.setReaperEnabled(on: false)),
      withoutId(commands['reaper_enabled']!),
    );
  });
}
