import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/app_effect.dart';
import '../../domain/entities/app_state.dart';
import '../../domain/usecase/answer_app.dart';
import '../../domain/usecase/watch_app.dart';

/// O cubit do app: a atualização (item de menu, aviso) e a limpeza de órfãos.
/// É dono das duas assinaturas do tópico `app` — estado e efeitos — e as
/// cancela no `close()`. Os efeitos não passam pelo estado: são avisos de uma
/// vez só, e o hospedeiro os desenha.
class UpdateCubit extends Cubit<AppState> {
  UpdateCubit({required WatchApp watch, required this._answer})
    : super(const AppState()) {
    _stateSubscription = watch.state().listen(emit);
    _effectSubscription = watch.effects().listen(_effects.add);
  }

  final AnswerApp _answer;
  final _effects = StreamController<AppEffect>.broadcast();
  StreamSubscription<AppState>? _stateSubscription;
  StreamSubscription<AppEffect>? _effectSubscription;

  Stream<AppEffect> get effects => _effects.stream;

  /// Clique no item de menu: procurar, ou o que o estado fizer dele (reiniciar
  /// para atualizar).
  void pressMenu() => _fire(_answer.pressUpdateMenu());

  void setUpdateAuto({required bool on}) =>
      _fire(_answer.setUpdateAuto(on: on));

  void setReaperEnabled({required bool on}) =>
      _fire(_answer.setReaperEnabled(on: on));

  /// A resposta ao aviso de versão nova.
  void answer({
    required String version,
    required bool accept,
    required bool auto,
  }) =>
      _fire(_answer.answerUpdate(version: version, accept: accept, auto: auto));

  /// Comando é "mande e siga": o estado que o core mandar a seguir corrige a
  /// tela se ele recusar.
  void _fire(Future<void> future) => unawaited(future.catchError((_) {}));

  @override
  Future<void> close() async {
    await _stateSubscription?.cancel();
    await _effectSubscription?.cancel();
    await _effects.close();
    return super.close();
  }
}
