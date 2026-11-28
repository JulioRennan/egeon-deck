import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:egeon_deck/commons/widgets/web_surface.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

// 1x1 PNG válido (chunks com tamanho e CRC certos): bytes tortos passam em um
// decodificador e falham em outro ("Codec failed to produce an image").
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGP4DwQACfsD/fteaysAAAAASUVORK5CYII=',
);

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
