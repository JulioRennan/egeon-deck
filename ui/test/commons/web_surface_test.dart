import 'dart:async';
import 'dart:typed_data';

import 'package:egeon_deck/commons/widgets/web_surface.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

// 1x1 PNG.
final _png = Uint8List.fromList([
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0xF8,
  0xFF,
  0xFF,
  0x3F,
  0x00,
  0x05,
  0xFE,
  0x02,
  0xFE,
  0xA7,
  0x35,
  0x81,
  0x84,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

class _Fake implements WebSurfaceController {
  var captures = 0;

  @override
  Stream<WebPageState> get states => const Stream.empty();

  @override
  Future<void> load(String url) async {}

  @override
  Future<void> goBack() async {}

  @override
  Future<void> goForward() async {}

  @override
  Future<void> reload() async {}

  @override
  Future<Uint8List?> capture() async {
    captures++;
    return _png;
  }

  @override
  Widget buildView(BuildContext context) =>
      const SizedBox(key: ValueKey('native'));

  @override
  void dispose() {}
}

void main() {
  testWidgets('ao vivo mostra a vista nativa, sem capturar', (tester) async {
    final controller = _Fake();
    await tester.pumpWidget(WebSurface(controller: controller, live: true));
    expect(find.byKey(const ValueKey('native')), findsOneWidget);
    expect(controller.captures, 0);
  });

  testWidgets('sair do ao vivo troca a vista pela captura', (tester) async {
    final controller = _Fake();
    await tester.pumpWidget(WebSurface(controller: controller, live: true));
    await tester.pumpWidget(WebSurface(controller: controller, live: false));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(controller.captures, 1);
    expect(find.byKey(const ValueKey('native')), findsNothing);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('congelada desde o começo também captura', (tester) async {
    final controller = _Fake();
    await tester.pumpWidget(WebSurface(controller: controller, live: false));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(controller.captures, 1);
    expect(find.byType(Image), findsOneWidget);
  });
}
