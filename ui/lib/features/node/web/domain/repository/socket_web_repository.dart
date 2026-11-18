import '../../../../../core/adapters/egeon_socket_client.dart';
import '../entities/web_node_state.dart';
import 'web_repository.dart';

/// O nó web de uma bancada falando com o core Rust. O tópico é
/// `node/<bancada>/<nó>`; o endereço digitado vai cru e o core o normaliza.
class SocketWebRepository implements WebRepository {
  SocketWebRepository(this._client, this.workbenchId);

  final EgeonSocketClient _client;
  final String workbenchId;

  Future<EgeonMessage> _send(String cmd, String nodeId, EgeonMessage args) =>
      _client.request(cmd, {'workbench': workbenchId, 'node': nodeId, ...args});

  @override
  Stream<WebNodeState> watch(String nodeId) => _client
      .subscribe('node/$workbenchId/$nodeId')
      .where((event) => event['kind'] == 'web')
      .map(
        (event) => WebNodeState.fromMap(event['web']! as Map<String, Object?>),
      );

  @override
  Future<void> navigate(String nodeId, String typed) =>
      _send('web_navigate', nodeId, {'typed': typed});

  @override
  Future<void> reportNavigated(String nodeId, String url) =>
      _send('web_navigated', nodeId, {'url': url});

  @override
  Future<void> setProfile(String nodeId, String profile) =>
      _send('web_set_profile', nodeId, {'profile': profile});
}
