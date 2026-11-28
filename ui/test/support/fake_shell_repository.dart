import 'dart:async';

import 'package:egeon_deck/core/domain/entities/view_mode.dart';
import 'package:egeon_deck/features/home/domain/entities/shell_snapshot.dart';
import 'package:egeon_deck/features/home/domain/errors/home_error.dart';
import 'package:egeon_deck/features/home/domain/repository/shell_repository.dart';

/// A casca falsa: o teste empurra estados e lê os gestos que a UI mandou.
class FakeShellRepository implements ShellRepository {
  final _states = StreamController<ShellSnapshot>.broadcast();
  final views = <ViewMode>[];
  final activated = <String>[];

  /// Faz `activate` ser recusado, como o core que não aceita a troca.
  var refuseActivate = false;
  var settingsOpened = 0;
  var askedAgain = 0;
  var watchers = 0;

  void push(ShellSnapshot state) => _states.add(state);

  @override
  Stream<ShellSnapshot> watch() {
    late StreamController<ShellSnapshot> controller;
    StreamSubscription<ShellSnapshot>? inner;
    controller = StreamController<ShellSnapshot>(
      onListen: () {
        watchers++;
        inner = _states.stream.listen(controller.add);
      },
      onCancel: () {
        watchers--;
        return inner?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  Future<void> setView(ViewMode mode) async => views.add(mode);

  @override
  Future<void> activate(String benchId) async {
    activated.add(benchId);
    if (refuseActivate) throw const HomeRefused('recusado');
  }

  @override
  Future<void> openSettings() async => settingsOpened++;

  @override
  Future<void> askAccessAgain() async => askedAgain++;
}
