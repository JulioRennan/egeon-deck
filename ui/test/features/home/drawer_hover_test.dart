import 'package:egeon_deck/commons/widgets/eg/layer.dart';
import 'package:egeon_deck/features/home/presentation/widgets/drawer_hover.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late int opens;
  late int closes;
  late DrawerHover hover;

  setUp(() {
    opens = 0;
    closes = 0;
    hover = DrawerHover(onOpen: () => opens++, onClose: () => closes++);
  });

  tearDown(() {
    hover.dispose();
    Layer.openCount.value = 0;
  });

  testWidgets('sair espera um pouco; voltar à gaveta nesse tempo cancela', (
    tester,
  ) async {
    hover.enter();
    expect(opens, 1);
    hover.leave();
    await tester.pump(const Duration(milliseconds: 100));
    hover.stay();
    await tester.pump(const Duration(seconds: 1));
    expect(closes, 0);
    hover.leave();
    await tester.pump(DrawerHover.linger);
    expect(closes, 1);
  });

  testWidgets('com menu aberto não fecha; fecha depois que ele some', (
    tester,
  ) async {
    hover.enter();
    Layer.openCount.value = 1;
    hover.leave();
    await tester.pump(const Duration(seconds: 2));
    expect(closes, 0);
    Layer.openCount.value = 0;
    await tester.pump(DrawerHover.linger);
    expect(closes, 1);
  });

  testWidgets('o menu some com o ponteiro ainda na gaveta: fica aberta', (
    tester,
  ) async {
    hover.enter();
    Layer.openCount.value = 1;
    hover.leave();
    await tester.pump(DrawerHover.linger);
    Layer.openCount.value = 0;
    hover.stay();
    await tester.pump(const Duration(seconds: 1));
    expect(closes, 0);
  });
}
