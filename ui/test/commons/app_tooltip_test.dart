import 'package:egeon_deck/commons/widgets/app_tooltip.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/overlay_host.dart';

void main() {
  Future<TestGesture> hover(WidgetTester tester, Finder target) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(target));
    await tester.pump();
    return mouse;
  }

  Widget host() => overlayHost(
    const Center(
      child: AppTooltip(
        message: 'Enquadrar todos os nós',
        child: SizedBox(
          key: ValueKey('alvo'),
          width: 40,
          height: 40,
          child: ColoredBox(color: Color(0xFF333333)),
        ),
      ),
    ),
  );

  testWidgets('a dica aparece depois de o cursor parar e some ao sair', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    final mouse = await hover(tester, find.byKey(const ValueKey('alvo')));
    expect(find.text('Enquadrar todos os nós'), findsNothing, reason: 'cedo');

    await tester.pump(AppTooltip.delay);
    expect(find.text('Enquadrar todos os nós'), findsOneWidget);

    await mouse.moveTo(const Offset(5, 5));
    await tester.pump();
    expect(find.text('Enquadrar todos os nós'), findsNothing);
  });

  testWidgets('clicar some com a dica', (tester) async {
    await tester.pumpWidget(host());
    await hover(tester, find.byKey(const ValueKey('alvo')));
    await tester.pump(AppTooltip.delay);
    await tester.tap(find.byKey(const ValueKey('alvo')));
    await tester.pump();
    expect(find.text('Enquadrar todos os nós'), findsNothing);
  });

  testWidgets('sem Overlay acima, só mostra o filho', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: AppTooltip(message: 'x', child: Text('filho')),
      ),
    );
    final mouse = await hover(tester, find.text('filho'));
    await tester.pump(AppTooltip.delay);
    expect(find.text('filho'), findsOneWidget);
    await mouse.moveTo(Offset.zero);
  });
}
