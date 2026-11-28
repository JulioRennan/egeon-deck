import 'package:egeon_deck/commons/widgets/dragged_image.dart';
import 'package:egeon_deck/commons/widgets/file_drop_target.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Imagem arrastada sem arquivo (print só com PNG/TIFF na área de arrasto): o
/// Dart pede ao plugin do runner e entrega em PNG.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const imageChannel = MethodChannel('egeon/image-drop');
  const dropChannel = MethodChannel('desktop_drop');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1]);

  tearDown(() {
    messenger.setMockMethodCallHandler(imageChannel, null);
    messenger.setMockMethodCallHandler(dropChannel, null);
  });

  group('readDraggedImage', () {
    test('devolve os bytes que o plugin manda', () async {
      messenger.setMockMethodCallHandler(imageChannel, (call) async {
        expect(call.method, 'draggedImage');
        return png;
      });
      expect(await readDraggedImage(), png);
    });

    test('sem imagem no arrasto, nulo', () async {
      messenger.setMockMethodCallHandler(imageChannel, (_) async => null);
      expect(await readDraggedImage(), isNull);
    });

    test('plugin ausente ou erro dele não derrubam o drop', () async {
      expect(await readDraggedImage(), isNull, reason: 'sem plugin');
      messenger.setMockMethodCallHandler(
        imageChannel,
        (_) async => throw PlatformException(code: 'x'),
      );
      expect(await readDraggedImage(), isNull);
    });
  });

  Future<void> say(MethodCall call) => messenger.handlePlatformMessage(
    'desktop_drop',
    const StandardMethodCodec().encodeMethodCall(call),
    (_) {},
  );

  /// O que o plugin nativo do `desktop_drop` faz ao arrastar e soltar: entra
  /// sobre a janela e chama o Dart com o que veio.
  Future<void> dropped(List<Map<String, Object?>> items) async {
    await say(const MethodCall('entered', [10.0, 10.0]));
    await say(MethodCall('performOperation_macos', items));
  }

  group('FileDropTarget', () {
    Future<void> pumpTarget(
      WidgetTester tester, {
      required void Function(List<String>) onFiles,
      void Function(Uint8List)? onImage,
    }) => tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: FileDropTarget(
          onFiles: onFiles,
          onImage: onImage,
          child: const SizedBox.expand(),
        ),
      ),
    );

    testWidgets('soltar sem arquivo e com imagem entrega o PNG', (
      tester,
    ) async {
      messenger.setMockMethodCallHandler(imageChannel, (_) async => png);
      final files = <List<String>>[];
      final images = <Uint8List>[];
      await pumpTarget(tester, onFiles: files.add, onImage: images.add);

      await dropped(const []);
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();

      expect(files, isEmpty);
      expect(images, [png]);
    });

    testWidgets('com arquivo, o arquivo vence e a imagem nem é lida', (
      tester,
    ) async {
      var asked = 0;
      messenger.setMockMethodCallHandler(imageChannel, (_) async {
        asked++;
        return png;
      });
      final files = <List<String>>[];
      final images = <Uint8List>[];
      await pumpTarget(tester, onFiles: files.add, onImage: images.add);

      await dropped([
        {'path': '/tmp/a.png', 'apple-bookmark': null, 'isDirectory': false},
      ]);
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));

      expect(files.single, ['/tmp/a.png']);
      expect(images, isEmpty);
      expect(asked, 0);
    });

    testWidgets('sem onImage, soltar sem arquivo não faz nada', (tester) async {
      var asked = 0;
      messenger.setMockMethodCallHandler(imageChannel, (_) async {
        asked++;
        return png;
      });
      final files = <List<String>>[];
      await pumpTarget(tester, onFiles: files.add);
      await dropped(const []);
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      expect(files, isEmpty);
      expect(asked, 0);
    });
  });
}
