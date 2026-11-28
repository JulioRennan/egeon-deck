import 'dart:async';

import 'package:egeon_deck/features/node/agent/domain/entities/agent_status.dart';
import 'package:egeon_deck/features/node/agent/domain/entities/context_reading.dart';
import 'package:egeon_deck/features/node/agent/domain/entities/effort_dial_view.dart';
import 'package:egeon_deck/features/node/agent/domain/entities/model_choice.dart';
import 'package:egeon_deck/features/node/agent/domain/repository/agent_repository.dart';

/// Um agente falso: o teste empurra o estado que o core mandaria e lê o que a
/// UI devolveu. A regra do seletor de esforço é do core, então aqui ela não
/// existe — quem quer ver o "…" empurra um estado com ele.
class FakeAgentRepository implements AgentRepository {
  FakeAgentRepository({AgentStatus? status}) : _status = status ?? sample;

  static const sample = AgentStatus(
    modelTitle: 'Opus 5.5',
    models: [
      ModelEntry(
        label: 'Opus 5.5',
        value: 'claude-opus-5-5',
        group: ModelGroup.featured,
        selected: true,
      ),
      ModelEntry(
        label: 'Sonnet 5.5',
        value: 'claude-sonnet-5-5',
        group: ModelGroup.featured,
      ),
      ModelEntry(label: 'opus', value: 'opus', group: ModelGroup.alias),
      ModelEntry(label: 'padrão do CLI', group: ModelGroup.standard),
    ],
    offersModel: true,
    dial: EffortDialView(
      levels: ['low', 'medium', 'high', 'xhigh', 'max'],
      markIndex: 1,
      auto: true,
      label: 'medium',
    ),
    ultracode: Ultracode(on: false, available: true),
    context: ContextReading(used: 170500, window: 1000000),
  );

  AgentStatus _status;

  /// Um estado que a UI não consegue ler: a assinatura só erra.
  Object? failure;
  final _changes = StreamController<void>.broadcast();
  final choices = <ModelChoice>[];
  var cleared = 0;

  /// O core mandou um estado novo.
  void push(AgentStatus status) {
    _status = status;
    _changes.add(null);
  }

  @override
  Stream<AgentStatus> watch(String nodeId) {
    late final StreamController<AgentStatus> controller;
    StreamSubscription<void>? changes;
    controller = StreamController<AgentStatus>(
      onListen: () {
        if (failure != null) {
          controller.addError(failure!);
        } else {
          controller.add(_status);
        }
        changes = _changes.stream.listen((_) => controller.add(_status));
      },
      onCancel: () => changes?.cancel(),
    );
    return controller.stream;
  }

  @override
  Future<void> choose(String nodeId, ModelChoice choice) async =>
      choices.add(choice);

  @override
  Future<void> clear(String nodeId) async => cleared++;

  /// Os pedidos de "tentar agora" (true) e "cancelar tentativa" (false).
  final retries = <bool>[];

  @override
  Future<void> retry(String nodeId, {required bool now}) async =>
      retries.add(now);
}
