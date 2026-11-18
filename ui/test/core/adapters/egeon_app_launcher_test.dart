import 'dart:io';

import 'package:egeon_deck/core/adapters/egeon_app_launcher.dart';
import 'package:egeon_deck/core/adapters/egeon_paths.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_process.dart';
import '../../support/fake_transport.dart';

void main() {
  final paths = EgeonPaths({'HOME': '/Users/x', 'EGEON_HOME': '/tmp/h'});

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

    await launcher.stop();
    expect(process.killed, isTrue);
  });

  test('EGEON_APP_BIN indica o executável', () {
    final launcher = EgeonAppLauncher(
      paths: paths,
      probe: FakeTransport(),
      environment: {'EGEON_APP_BIN': '/opt/egeon-app'},
    );
    expect(launcher.locate(), '/opt/egeon-app');
  });
}
