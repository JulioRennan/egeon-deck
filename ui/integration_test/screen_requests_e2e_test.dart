// ATENÇÃO: este teste ABRE A JANELA do app na tela de quem roda. Não faz parte
// de `fvm flutter test`; só rode de propósito, com o usuário ciente.
import 'dart:convert';
import 'dart:io';

import 'package:egeon_deck/features/home/presentation/widgets/root_layout.dart';
import 'package:egeon_deck/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// Decisão 35 de ponta a ponta: o HTTP do core pede à tela e a tela responde.
// Precisa de EGEON_APP_BIN e de EGEON_HOME numa pasta curta e temporária.
//   EGEON_HOME=/tmp/egeon-e2e EGEON_APP_BIN=… fvm flutter test \
//     integration_test/screen_requests_e2e_test.dart -d macos
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('/sidebar, /layout, /geometry e /shot respondem pela tela', (
    tester,
  ) async {
    final env = Platform.environment;
    final home = env['EGEON_HOME']!;
    final app = createEgeonDeckApp(env);
    addTearDown(() => tester.runAsync(app.connection.close));
    await tester.pumpWidget(app);

    /// O curl nasce e segue em paralelo; a resposta se lê depois, quando a tela
    /// já atendeu o pedido (o relógio do teste não deixa esperar os dois juntos).
    Future<Future<Map<String, Object?>> Function()> get(String path) async {
      final process = await tester.runAsync(
        () => Process.start('curl', [
          '-s',
          '--max-time',
          '8',
          '--unix-socket',
          '$home/sock',
          'http://eg$path',
        ]),
      );
      return () async {
        final out = await tester.runAsync(
          () => process!.stdout.transform(utf8.decoder).join(),
        );
        return jsonDecode(out!) as Map<String, Object?>;
      };
    }

    // Espera a casca montar e o core ouvir.
    for (
      var i = 0;
      i < 100 && find.byType(RootLayout).evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
    expect(find.byType(RootLayout), findsOneWidget);

    bool collapsed() =>
        tester.widget<RootLayout>(find.byType(RootLayout)).collapsed;

    Future<void> settle([int ms = 300]) async {
      await tester.runAsync(
        () => Future<void>.delayed(Duration(milliseconds: ms)),
      );
      await tester.pump();
    }

    // A casca monta antes de a conexão e a assinatura do `app` existirem; sem
    // ninguém assinando, o core responde "sem janela". Insiste até a UI ouvir.
    var listening = false;
    for (var i = 0; i < 40 && !listening; i++) {
      final probe = await get('/sidebar?collapsed=0');
      await settle();
      listening = (await probe())['ok'] == true;
    }
    expect(listening, isTrue, reason: 'a UI assinou o tópico app');

    var reply = await get('/sidebar?collapsed=1');
    await settle();
    expect(collapsed(), isTrue);
    expect(await reply(), {'ok': true, 'collapsed': true});

    reply = await get('/sidebar?collapsed=toggle');
    await settle();
    expect(collapsed(), isFalse);
    expect(await reply(), {'ok': true, 'collapsed': false});

    final tab = await get('/sidebar?tab=active');
    await settle();
    expect(await tab(), {'ok': true, 'tab': 'active'});

    final bad = await get('/sidebar?tab=nada');
    await settle();
    expect(await bad(), {'ok': false, 'tab': 'nada'});

    final layout = await get('/layout?mode=chat');
    await settle();
    // Sem bancada aberta o Swift também responde 404.
    expect((await layout())['ok'], isFalse);

    final shot = await get('/shot?target=window');
    await settle(1500);
    final body = await shot();
    expect(body['target'], 'window');
    final path = body['path']! as String;
    expect(path, startsWith(home));
    expect(File(path).readAsBytesSync().sublist(0, 4), [
      0x89,
      0x50,
      0x4E,
      0x47,
    ]);

    final sidebarShot = await get('/shot?target=sidebar');
    await settle(1500);
    expect(File((await sidebarShot())['path']! as String).existsSync(), isTrue);
  });
}
