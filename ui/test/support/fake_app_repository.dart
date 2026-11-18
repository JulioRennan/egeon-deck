import 'dart:async';

import 'package:egeon_deck/features/update/domain/entities/app_effect.dart';
import 'package:egeon_deck/features/update/domain/entities/app_state.dart';
import 'package:egeon_deck/features/update/domain/repository/app_repository.dart';

/// O tópico `app` de mentira: o teste empurra estado e efeitos e lê as
/// respostas.
class FakeAppRepository implements AppRepository {
  final _states = StreamController<AppState>.broadcast();
  final _effects = StreamController<AppEffect>.broadcast();
  final answers = <({String version, bool accept, bool auto})>[];
  final autos = <bool>[];
  final reapers = <bool>[];
  var menuPresses = 0;

  void push(AppState state) => _states.add(state);

  void effect(AppEffect effect) => _effects.add(effect);

  @override
  Stream<AppState> watch() => _states.stream;

  @override
  Stream<AppEffect> effects() => _effects.stream;

  @override
  Future<void> answerUpdate({
    required String version,
    required bool accept,
    required bool auto,
  }) async => answers.add((version: version, accept: accept, auto: auto));

  @override
  Future<void> setUpdateAuto({required bool on}) async => autos.add(on);

  @override
  Future<void> pressUpdateMenu() async => menuPresses++;

  @override
  Future<void> setReaperEnabled({required bool on}) async => reapers.add(on);
}
