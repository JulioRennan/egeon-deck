// ATENÇÃO: este teste ABRE A JANELA do app na tela de quem roda. Não faz parte
// de `fvm flutter test`; só rode de propósito, com o usuário ciente.
import 'package:egeon_deck/commons/widgets/dragged_image.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// O plugin de drop de imagem de verdade, lendo a área de arrasto do sistema:
// um TIFF deixado nela (como o arrasto de um print) volta como PNG.
//   /tmp/seed_drag && fvm flutter test integration_test/image_drop_e2e_test.dart -d macos
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('o arrasto sem arquivo volta como PNG', (tester) async {
    await tester.pumpWidget(const SizedBox());
    final png = await readDraggedImage();
    expect(png, isNotNull, reason: 'rode /tmp/seed_drag antes');
    expect(png!.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
  });
}
