import 'dart:async';

import 'package:egeon_deck/core/domain/entities/view_mode.dart';
import 'package:egeon_deck/features/home/domain/entities/shell_state.dart';
import 'package:egeon_deck/features/home/domain/repository/shell_repository.dart';

/// A casca falsa: o teste empurra estados e lê os gestos que a UI mandou.
class FakeShellRepository implements ShellRepository {
  final _states = StreamController<ShellState>.broadcast();
  final views = <ViewMode>[];
  var settingsOpened = 0;
  var askedAgain = 0;
  var watchers = 0;

  void push(ShellState state) => _states.add(state);

  @override
  Stream<ShellState> watch() {
    late StreamController<ShellState> controller;
    StreamSubscription<ShellState>? inner;
    controller = StreamController<ShellState>(
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
  Future<void> openSettings() async => settingsOpened++;

  @override
  Future<void> askAccessAgain() async => askedAgain++;
}
