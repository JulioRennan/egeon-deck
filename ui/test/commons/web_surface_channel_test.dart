import 'package:egeon_deck/commons/widgets/web_surface.dart';
import 'package:egeon_deck/commons/widgets/web_surface_channel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// O lado Dart do plugin do runner, contra um canal falso: o que vai e o que
/// volta, e que nada fica retido depois do dispose.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('egeon/web');
  final calls = <MethodCall>[];
  var nextId = 7;
  final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]);

  setUp(() {
    calls.clear();
    nextId = 7;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return switch (call.method) {
            'create' => nextId++,
            'snapshot' => png,
            _ => null,
          };
        });
  });

  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  /// O que o runner faz quando a página muda: chama `state` no Dart.
  Future<void> nativeSays(Map<String, Object?> state) =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            'egeon/web',
            const StandardMethodCodec().encodeMethodCall(
              MethodCall('state', state),
            ),
            (_) {},
          );

  test('cria a página com o perfil e o UUID do data store', () async {
    final surface = ChannelWebSurface(profile: 'trabalho', profileId: 'AAAA');
    await surface.load('https://docs.rs');
    expect(calls.first.method, 'create');
    expect(calls.first.arguments, {'profile': 'trabalho', 'profileId': 'AAAA'});
    expect(calls[1].method, 'load');
    expect(calls[1].arguments, {'id': 7, 'url': 'https://docs.rs'});
    surface.dispose();
  });

  test('o UUID do data store sempre vai: o perfil não se inventa', () async {
    final surface = ChannelWebSurface(profile: 'pessoal', profileId: 'UUID-A');
    await surface.reload();
    expect(calls.first.arguments, {
      'profile': 'pessoal',
      'profileId': 'UUID-A',
    });
    surface.dispose();
  });

  test('voltar, avançar e recarregar vão com o id da página', () async {
    final surface = ChannelWebSurface(profile: 'p', profileId: 'UUID-P');
    await surface.goBack();
    await surface.goForward();
    await surface.reload();
    expect(calls.skip(1).map((c) => (c.method, (c.arguments as Map)['id'])), [
      ('goBack', 7),
      ('goForward', 7),
      ('reload', 7),
    ]);
    surface.dispose();
  });

  test('o estado que o runner manda vira WebPageState, por página', () async {
    final a = ChannelWebSurface(profile: 'p', profileId: 'UUID-P');
    final b = ChannelWebSurface(profile: 'q', profileId: 'UUID-Q');
    await a.reload();
    await b.reload();
    final seenA = <WebPageState>[];
    final seenB = <WebPageState>[];
    a.states.listen(seenA.add);
    b.states.listen(seenB.add);

    await nativeSays({
      'id': 7,
      'url': 'https://a.com',
      'canGoBack': true,
      'canGoForward': false,
      'loading': true,
    });
    await Future<void>.delayed(Duration.zero);

    expect(seenB, isEmpty, reason: 'o estado é da página 7, não da 8');
    expect(seenA.single.url, 'https://a.com');
    expect(seenA.single.canGoBack, isTrue);
    expect(seenA.single.canGoForward, isFalse);
    expect(seenA.single.loading, isTrue);
    a.dispose();
    b.dispose();
  });

  test('a captura volta como PNG', () async {
    final surface = ChannelWebSurface(profile: 'p', profileId: 'UUID-P');
    expect(await surface.capture(), png);
    expect(calls.last.method, 'snapshot');
    surface.dispose();
  });

  test('dispose solta a página no runner e cala os estados', () async {
    final surface = ChannelWebSurface(profile: 'p', profileId: 'UUID-P');
    await surface.reload();
    final seen = <WebPageState>[];
    surface.states.listen(seen.add);

    surface.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(calls.last.method, 'dispose');
    expect((calls.last.arguments as Map)['id'], 7);

    await nativeSays({'id': 7, 'url': 'https://tarde.com'});
    await Future<void>.delayed(Duration.zero);
    expect(seen, isEmpty);
  });

  test('soltar antes de a página nascer não deixa vista retida', () async {
    final surface = ChannelWebSurface(profile: 'p', profileId: 'UUID-P');
    surface.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(calls.map((c) => c.method), ['create', 'dispose']);
  });

  test('depois do dispose, comandos não vão ao runner', () async {
    final surface = ChannelWebSurface(profile: 'p', profileId: 'UUID-P');
    await surface.reload();
    surface.dispose();
    await Future<void>.delayed(Duration.zero);
    final before = calls.length;
    await surface.load('https://x.com');
    expect(calls.length, before);
  });
}
