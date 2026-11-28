// ATENÇÃO: este teste ABRE A JANELA do app na tela de quem roda. Não faz parte
// de `fvm flutter test`; só rode de propósito, com o usuário ciente.
import 'package:egeon_deck/core/adapters/window_frame.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// O canal egeon/window do runner de verdade: a janela tem tamanho e posição.
//   fvm flutter test integration_test/window_e2e_test.dart -d macos
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('o runner diz onde a janela está na tela', (tester) async {
    await tester.pumpWidget(const SizedBox());
    final frame = await const ChannelWindowFrame().read();
    expect(frame.width, greaterThan(100));
    expect(frame.height, greaterThan(100));
    expect(frame.screenHeight, greaterThanOrEqualTo(frame.height));
    expect(frame.y, greaterThanOrEqualTo(0), reason: 'de cima para baixo');
  });

  testWidgets('o runner atende o canal egeon/edit com um booleano', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    const channel = MethodChannel('egeon/edit');
    // Sem responder que aceite a ação o AppKit diz que não; o que importa é o
    // plugin existir e responder, e uma ação desconhecida ser recusada.
    final known = await channel.invokeMethod<bool>('send', 'selectAll');
    final unknown = await channel.invokeMethod<bool>('send', 'inventada');
    expect(known, isA<bool>());
    expect(unknown, isFalse);
  });
}
