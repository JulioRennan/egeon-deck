import 'dart:io';

import 'package:egeon_deck/core/adapters/egeon_app_launcher.dart';
import 'package:egeon_deck/core/adapters/egeon_paths.dart';
import 'package:egeon_deck/core/adapters/egeon_socket_client.dart';
import 'package:egeon_deck/core/cubits/connection_cubit.dart';

import '../../support/connection_cubit_for.dart';
import '../../support/fake_process.dart';
import '../../support/pump.dart';

import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_transport.dart';

void main() {
  final paths = EgeonPaths({'HOME': '/Users/x'});

  test('sobe, conecta e avisa; cair volta para "iniciando"', () async {
    final transport = FakeTransport();
    final cubit = connectionCubitFor(
      EgeonAppLauncher(paths: paths, probe: transport),
      EgeonSocketClient(
        transport,
        retryDelay: const Duration(milliseconds: 10),
      ),
    );
    expect(cubit.state, isA<CoreConnecting>());
    await pump();
    transport.connections.last.upgrade();
    await pump();
    expect(cubit.state, isA<CoreConnected>());

    await transport.connections.last.drop();
    await pump();
    expect(cubit.state, isNot(isA<CoreConnected>()));
    await cubit.close();
  });

  test('core caiu com a UI aberta: sobe outro', () async {
    final transport = FakeTransport();
    var launches = 0;
    final cubit = connectionCubitFor(
      EgeonAppLauncher(
        paths: paths,
        probe: transport,
        executable: '/bin/egeon-app',
        starter:
            (exe, args, {environment, mode = ProcessStartMode.normal}) async {
              launches++;
              return FakeProcess();
            },
      ),
      EgeonSocketClient(
        transport,
        retryDelay: const Duration(milliseconds: 10),
      ),
    );
    await pump();
    transport.connections.last.upgrade();
    await pump();
    expect(launches, 0);

    transport.refuse = true;
    await transport.connections.last.drop();
    await Future<void>.delayed(const Duration(milliseconds: 700));
    expect(launches, 1);
    await cubit.close();
  });
}
