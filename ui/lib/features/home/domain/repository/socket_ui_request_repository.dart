import '../../../../core/adapters/egeon_socket_client.dart';
import '../entities/ui_request.dart';
import 'ui_request_repository.dart';

/// Os pedidos chegam como efeito no tópico `app`; a resposta vai de volta como
/// comando. O argumento é `request`, e não `id`, que é o do próprio comando.
class SocketUiRequestRepository implements UiRequestRepository {
  const SocketUiRequestRepository(this._client);

  final EgeonSocketClient _client;

  @override
  Stream<UiRequest> watch() => _client
      .subscribe('app')
      .where((event) => event['effect'] == 'ui_request')
      .map(UiRequest.fromMap);

  @override
  Stream<void> activations() =>
      _client.subscribe('app').where((event) => event['effect'] == 'activate');

  @override
  Future<void> reply(Object request, UiReply reply) async {
    await _client.request('ui_reply', {
      'request': request,
      'value': reply.value,
    });
  }
}
