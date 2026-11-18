import 'dart:async';

import '../domain/entities/organization.dart';
import 'egeon_socket_client.dart';

/// A assinatura única do tópico `workspaces`, repartida entre a barra lateral,
/// as abas e a casca. O core manda o estado inteiro só ao primeiro assinante;
/// quem chega depois recebe aqui o último, sem assinar de novo.
class OrganizationFeed {
  OrganizationFeed(this._client);

  final EgeonSocketClient _client;

  late final _controller = StreamController<Organization>.broadcast(
    onListen: _attach,
    onCancel: _detach,
  );
  StreamSubscription<Organization>? _subscription;
  Organization? _last;

  /// O último estado recebido: é a base dos comandos que dependem do que está
  /// na tela (recolher é o contrário do que está).
  Organization? get last => _last;

  void _attach() {
    _subscription = _client
        .subscribe('workspaces')
        .map(Organization.fromMap)
        .listen((org) {
          _last = org;
          _controller.add(org);
        });
  }

  Future<void> _detach() async {
    await _subscription?.cancel();
    _subscription = null;
    _last = null;
  }

  /// O estado atual e, depois, cada mudança.
  Stream<Organization> watch() => Stream<Organization>.multi((out) {
    final current = _last;
    if (current != null) out.add(current);
    final inner = _controller.stream.listen(
      out.add,
      onError: out.addError,
      onDone: out.close,
    );
    out.onCancel = inner.cancel;
  });

  /// Manda o comando. A recusa do core e a queda chegam como as do cliente;
  /// quem converte é o repositório.
  Future<EgeonMessage> command(String cmd, [EgeonMessage args = const {}]) =>
      _client.request(cmd, args);
}
