import 'package:egeon_deck/core/adapters/app_windows.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// O canal do pacote `desktop_multi_window`, falso: anota o que pediram e
/// responde com as janelas que "existem".
const _plugin = MethodChannel('mixin.one/desktop_multi_window');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<MethodCall> calls;
  late List<Map<String, String>> existing;

  setUp(() {
    calls = [];
    existing = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_plugin, (call) async {
          calls.add(call);
          return switch (call.method) {
            'getAllWindows' => existing,
            'createWindow' => 'nova',
            _ => null,
          };
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_plugin, null),
  );

  const processes = WindowArguments(
    kind: WindowKind.processes,
    title: 'Processos do Egeon Deck',
  );

  test('os argumentos vão e voltam pelo main do motor novo', () {
    final back = WindowArguments.fromEntrypoint([
      'multi_window',
      'id',
      processes.encode(),
    ]);
    expect(back?.kind, WindowKind.processes);
    expect(back?.title, 'Processos do Egeon Deck');
    expect(WindowArguments.fromEntrypoint(const []), isNull);
    expect(WindowArguments.decode(''), isNull);
    expect(WindowArguments.decode('{"kind":"outra","title":"x"}'), isNull);
  });

  test('sem janela de Processos aberta, cria uma', () async {
    existing = [
      {'windowId': 'principal', 'windowArgument': ''},
    ];
    await const MultiWindowAppWindows().open(processes);
    final create = calls.singleWhere((c) => c.method == 'createWindow');
    final arguments = (create.arguments as Map)['arguments'] as String;
    expect(WindowArguments.decode(arguments)?.kind, WindowKind.processes);
  });

  test('já aberta, traz a mesma para a frente em vez de outra', () async {
    existing = [
      {'windowId': 'principal', 'windowArgument': ''},
      {'windowId': 'p1', 'windowArgument': processes.encode()},
    ];
    await const MultiWindowAppWindows().open(processes);
    expect(calls.map((c) => c.method), isNot(contains('createWindow')));
    final show = calls.singleWhere((c) => c.method == 'window_show');
    expect((show.arguments as Map)['windowId'], 'p1');
  });

  group('present', () {
    const channel = MethodChannel('egeon/window');
    late List<MethodCall> presented;

    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    Future<void> present() => const ChannelCurrentWindow().present(
      title: 'Processos',
      size: const Size(900, 600),
      minSize: const Size(700, 400),
      autosave: 'processes',
    );

    test(
      'manda título, tamanho, mínimo e o nome da posição lembrada',
      () async {
        presented = [];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              presented.add(call);
              return null;
            });
        await present();
        expect(presented.single.arguments, {
          'title': 'Processos',
          'width': 900.0,
          'height': 600.0,
          'minWidth': 700.0,
          'minHeight': 400.0,
          'autosave': 'processes',
        });
      },
    );

    test('canal ainda não registrado pelo runner: tenta de novo', () async {
      var attempts = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            attempts++;
            if (attempts < 3) throw MissingPluginException();
            return null;
          });
      await present();
      expect(attempts, 3);
    });
  });
}
