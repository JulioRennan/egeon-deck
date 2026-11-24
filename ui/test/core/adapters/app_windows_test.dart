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
}
