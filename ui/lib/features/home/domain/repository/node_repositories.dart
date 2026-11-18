import '../../../../core/adapters/egeon_socket_client.dart';
import '../../../node/agent/domain/repository/agent_repository.dart';
import '../../../node/agent/domain/repository/socket_agent_repository.dart';
import '../../../node/queue/domain/repository/queue_repository.dart';
import '../../../node/queue/domain/repository/socket_queue_repository.dart';
import '../../../node/web/domain/repository/socket_web_repository.dart';
import '../../../node/web/domain/repository/web_repository.dart';

/// Os repositórios dos nós de uma bancada. Cada comando leva a bancada, então
/// há um conjunto por bancada — o canvas os cria ao nascer e os descarta ao
/// trocar de bancada.
abstract interface class NodeRepositories {
  AgentRepository agent(String workbenchId);

  QueueRepository queue(String workbenchId);

  WebRepository web(String workbenchId);
}

/// Os nós falando com o core Rust pelo cliente único do socket.
class SocketNodeRepositories implements NodeRepositories {
  const SocketNodeRepositories(this._client);

  final EgeonSocketClient _client;

  @override
  AgentRepository agent(String workbenchId) =>
      SocketAgentRepository(_client, workbenchId);

  @override
  QueueRepository queue(String workbenchId) =>
      SocketQueueRepository(_client, workbenchId);

  @override
  WebRepository web(String workbenchId) =>
      SocketWebRepository(_client, workbenchId);
}
