import '../../../../../core/adapters/egeon_socket_client.dart';
import '../entities/agent_status.dart';
import '../entities/model_choice.dart';
import 'agent_repository.dart';
import '../errors/agent_error.dart';

/// O agente de uma bancada falando com o core Rust. O tópico é
/// `node/<bancada>/<nó>`: o estado inteiro a cada mudança. Um repositório por
/// bancada: ela vai em todo comando.
class SocketAgentRepository implements AgentRepository {
  SocketAgentRepository(this._client, this.workbenchId);

  final EgeonSocketClient _client;

  /// Recusa e queda do socket viram [AgentError].
  Future<EgeonMessage> _request(String cmd, [EgeonMessage args = const {}]) =>
      _client
          .request(cmd, args)
          .failingAs(refused: AgentRefused.new, offline: AgentOffline.new);
  final String workbenchId;

  @override
  Stream<AgentStatus> watch(String nodeId) => _client
      .subscribe('node/$workbenchId/$nodeId')
      .where((event) => event['kind'] == 'agent')
      .map(
        (event) => AgentStatus.fromMap(event['agent']! as Map<String, Object?>),
      );

  Future<EgeonMessage> _send(
    String cmd,
    String nodeId, [
    EgeonMessage args = const {},
  ]) => _request(cmd, {'workbench': workbenchId, 'node': nodeId, ...args});

  /// Modelo e ultracode vão em `set_node`; o esforço são as intenções do
  /// seletor, cuja regra é do core.
  @override
  Future<void> choose(String nodeId, ModelChoice choice) => switch (choice) {
    ModelPick(:final model) => _send('set_node', nodeId, {'model': model}),
    UltracodePick(:final on) => _send('set_node', nodeId, {'ultracode': on}),
    EffortMove(:final index) => _send('effort_move', nodeId, {'index': index}),
    EffortToggleAuto() => _send('effort_toggle_auto', nodeId),
    EffortSettle() => _send('effort_settle', nodeId),
  };

  @override
  Future<void> clear(String nodeId) => _send('node_clear', nodeId);

  @override
  Future<void> retry(String nodeId, {required bool now}) =>
      _send('retry', nodeId, {'now': now});
}
