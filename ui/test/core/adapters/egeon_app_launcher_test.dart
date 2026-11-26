import 'dart:io';

import 'package:egeon_deck/core/adapters/egeon_app_launcher.dart';
import 'package:egeon_deck/core/adapters/egeon_paths.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_process.dart';
import '../../support/fake_transport.dart';

void main() {
  final paths = EgeonPaths(
    {'HOME': '/Users/x', 'EGEON_HOME': '/tmp/h'},
    release: true,
    executable:
        '/Applications/EgeonDeck Next.app/Contents/MacOS/EgeonDeck Next',
  );

  test('core já atendendo: não lança outro', () async {
    var launched = false;
    final process = FakeProcess();
    final launcher = EgeonAppLauncher(
      paths: paths,
      probe: FakeTransport(),
      executable: '/bin/egeon-app',
      starter:
          (exe, args, {environment, mode = ProcessStartMode.normal}) async {
            launched = true;
            return process;
          },
    );
    expect(await launcher.ensureRunning(), isFalse);
    expect(launched, isFalse);

    // O core era de outro: o ⌘Q da UI não encerra nada.
    await launcher.stop();
    expect(process.killed, isFalse);
  });

  test('sem core: lança com EGEON_HOME e mata o filho no stop', () async {
    final process = FakeProcess();
    String? exe;
    List<String>? arguments;
    ProcessStartMode? startMode;
    Map<String, String>? env;
    final launcher = EgeonAppLauncher(
      paths: paths,
      probe: FakeTransport()..refuse = true,
      executable: '/bin/egeon-app',
      environment: {'PATH': '/bin'},
      starter: (e, args, {environment, mode = ProcessStartMode.normal}) async {
        exe = e;
        arguments = args;
        startMode = mode;
        env = environment;
        return process;
      },
    );
    expect(await launcher.ensureRunning(), isTrue);
    expect(exe, '/bin/egeon-app');
    // stdin em cano + a opção que faz o core sair quando o cano fecha.
    expect(arguments, ['--exit-with-stdin']);
    expect(startMode, ProcessStartMode.normal);
    expect(env!['EGEON_HOME'], '/tmp/h');
    expect(env!['PATH'], '/bin');
    expect(env!['EGEON_FLAVOR'], 'stable');

    await launcher.stop();
    expect(process.killed, isTrue);
  });

  test('o dev passa o flavor ao core', () async {
    Map<String, String>? env;
    final launcher = EgeonAppLauncher(
      paths: EgeonPaths({'HOME': '/Users/x', 'EGEON_FLAVOR': 'dev'}),
      probe: FakeTransport()..refuse = true,
      executable: '/bin/egeon-app',
      environment: const {},
      starter: (e, args, {environment, mode = ProcessStartMode.normal}) async {
        env = environment;
        return FakeProcess();
      },
    );
    await launcher.ensureRunning();
    expect(env!['EGEON_FLAVOR'], 'dev');
    expect(env!['EGEON_HOME'], '/Users/x/.egeon-next-dev');
  });

  test('EGEON_APP_BIN indica o executável', () {
    final launcher = EgeonAppLauncher(
      paths: paths,
      probe: FakeTransport(),
      environment: {'EGEON_APP_BIN': '/opt/egeon-app'},
    );
    expect(launcher.locate(), '/opt/egeon-app');
  });

  group('locate', () {
    late Directory bundle;

    setUp(() => bundle = Directory.systemTemp.createTempSync('egeon-bundle'));
    tearDown(() => bundle.deleteSync(recursive: true));

    EgeonAppLauncher launcherAt(String uiExecutable) => EgeonAppLauncher(
      paths: paths,
      probe: FakeTransport(),
      environment: const {},
      uiExecutable: uiExecutable,
    );

    test('bundle do Linux: o egeon-app ao lado do executável da UI', () {
      // build/linux/x64/release/bundle/{egeon_deck, egeon-app, lib/, data/}
      File('${bundle.path}/egeon-app').writeAsStringSync('');
      expect(
        launcherAt('${bundle.path}/egeon_deck').locate(),
        '${bundle.path}/egeon-app',
      );
    });

    test('Windows: o egeon-app.exe ao lado do egeon_deck.exe', () {
      File('${bundle.path}/egeon-app.exe').writeAsStringSync('');
      final launcher = EgeonAppLauncher(
        paths: paths,
        probe: FakeTransport(),
        environment: const {},
        uiExecutable: '${bundle.path}/egeon_deck.exe',
        windows: true,
      );
      expect(launcher.locate(), '${bundle.path}/egeon-app.exe');
    });

    test('Windows não toma o egeon-app sem .exe por irmão', () {
      File('${bundle.path}/egeon-app').writeAsStringSync('');
      final launcher = EgeonAppLauncher(
        paths: paths,
        probe: FakeTransport(),
        environment: const {},
        uiExecutable: '${bundle.path}/egeon_deck.exe',
        windows: true,
      );
      expect(launcher.locate(), isNot('${bundle.path}/egeon-app'));
    });

    test('EGEON_APP_BIN vence o irmão do executável', () {
      File('${bundle.path}/egeon-app').writeAsStringSync('');
      final launcher = EgeonAppLauncher(
        paths: paths,
        probe: FakeTransport(),
        environment: const {'EGEON_APP_BIN': '/opt/egeon-app'},
        uiExecutable: '${bundle.path}/egeon_deck',
      );
      expect(launcher.locate(), '/opt/egeon-app');
    });
  });
}
