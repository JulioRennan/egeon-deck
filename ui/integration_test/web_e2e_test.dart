// ATENÇÃO: este teste ABRE A JANELA do app na tela de quem roda. Não faz parte
// de `fvm flutter test`; só rode de propósito, com o usuário ciente.
import 'dart:convert';

import 'package:egeon_deck/commons/widgets/web_surface.dart';
import 'package:egeon_deck/commons/widgets/web_surface_channel.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// O plugin nativo do runner de verdade (WKWebView + canal egeon/web), sem o
// core: carrega uma página, vê o estado mudar, mostra ao vivo e captura.
//   fvm flutter test integration_test/web_e2e_test.dart -d macos
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a página carrega, avisa o estado e vira PNG', (tester) async {
    final controller = createChannelWebSurfaceController(
      profile: 'teste-e2e',
      profileId: '6f1c5a2e-0000-4000-8000-000000000001',
    );
    final states = <WebPageState>[];
    final sub = controller.states.listen(states.add);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 400,
            height: 300,
            child: WebSurface(controller: controller, live: true),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    final html = base64.encode(utf8.encode('<h1 style="color:red">oi</h1>'));
    await controller.load('data:text/html;base64,$html');
    for (
      var i = 0;
      i < 40 && !states.any((s) => s.url.startsWith('data:'));
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      states.any((s) => s.url.startsWith('data:')),
      isTrue,
      reason: 'o runner devolveu o estado da navegação',
    );

    // A vista nativa nasce por canal, em tempo real: dá-lhe um instante.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    final png = await controller.capture();
    expect(png, isNotNull, reason: 'a captura devolve a página');
    expect(png!.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47], reason: 'é um PNG');

    await sub.cancel();
    controller.dispose();
    await tester.pump(const Duration(milliseconds: 200));
  });
}
