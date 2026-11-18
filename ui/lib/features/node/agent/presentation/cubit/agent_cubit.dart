import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/agent_status.dart';
import '../../domain/entities/model_choice.dart';
import '../../domain/usecase/choose_agent_option.dart';
import '../../domain/usecase/clear_agent.dart';
import '../../domain/usecase/watch_agent.dart';
import 'agent_state.dart';

/// Um cubit por agente. É dono da assinatura da faixa do cabeçalho: abre ao
/// nascer e cancela no `close()`. O core manda o estado inteiro a cada
/// mudança — a UI não aplica diferença.
class AgentCubit extends Cubit<AgentState> {
  AgentCubit({
    required this.nodeId,
    required WatchAgent watch,
    required this._choose,
    required this._clear,
  }) : super(const AgentState()) {
    _subscription = watch(nodeId).listen(_onStatus);
  }

  final String nodeId;
  final ChooseAgentOption _choose;
  final ClearAgent _clear;
  StreamSubscription<AgentStatus>? _subscription;

  void _onStatus(AgentStatus status) => emit(AgentState(status: status));

  void chooseModel(String? model) => _fire(_choose(nodeId, ModelPick(model)));

  void moveEffort(int index) => _fire(_choose(nodeId, EffortMove(index)));

  void toggleEffortAuto() => _fire(_choose(nodeId, const EffortToggleAuto()));

  void settleEffort() => _fire(_choose(nodeId, const EffortSettle()));

  void setUltracode({required bool on}) =>
      _fire(_choose(nodeId, UltracodePick(on: on)));

  void clearConversation() => _fire(_clear(nodeId));

  /// Comando é "mande e siga": o estado que o core mandar a seguir já
  /// corrige a tela se ele recusar.
  void _fire(Future<void> future) => unawaited(future.catchError((_) {}));

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }
}
