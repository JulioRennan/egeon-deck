import '../../../../core/adapters/event_parsing.dart';
import '../../../../core/adapters/egeon_socket_client.dart';
import '../entities/usage_view.dart';
import 'usage_repository.dart';

/// O consumo de uma bancada falando com o core Rust: o tópico
/// `workbench/<id>/usage` traz a pastilha e o painel prontos, inteiros a cada
/// mudança.
class SocketUsageRepository implements UsageRepository {
  const SocketUsageRepository(this._client);

  final EgeonSocketClient _client;

  @override
  Stream<UsageView> watch(String workbenchId) => _client
      .subscribe('workbench/$workbenchId/usage')
      .parsed(
        'workbench/$workbenchId/usage',
        UsageView.fromMap,
        fallback: (_) => const UsageView(),
      );
}
