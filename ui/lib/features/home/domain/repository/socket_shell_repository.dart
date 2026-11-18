import '../../../../core/adapters/organization_feed.dart';
import '../../../../core/domain/entities/view_mode.dart';
import '../entities/shell_snapshot.dart';
import 'shell_repository.dart';
import '../../../../core/adapters/egeon_socket_client.dart';
import '../errors/home_error.dart';

/// A casca falando com o core Rust: a bancada na tela é a da aba ativa.
class SocketShellRepository implements ShellRepository {
  const SocketShellRepository(this._feed);

  final OrganizationFeed _feed;

  /// Recusa e queda do socket viram [HomeError].
  Future<EgeonMessage> _command(String cmd, [EgeonMessage args = const {}]) =>
      _feed
          .command(cmd, args)
          .failingAs(refused: HomeRefused.new, offline: HomeOffline.new);

  @override
  Stream<ShellSnapshot> watch() =>
      _feed.watch().map(ShellSnapshot.fromOrganization);

  @override
  Future<void> setView(ViewMode mode) async {
    final bench = _feed.last?.activeBench;
    if (bench == null) return;
    await _command('set_workbench', {'workbench': bench.id, 'view': mode.wire});
  }

  /// Os dois botões da cortina "sem acesso" valem para a bancada na tela. O
  /// resultado chega pela releitura do estado: a cortina some quando a pasta
  /// abre.
  @override
  Future<void> openSettings() => _access('access_open_settings');

  @override
  Future<void> askAccessAgain() => _access('access_ask_again');

  Future<void> _access(String command) async {
    final bench = _feed.last?.activeBench;
    if (bench == null) return;
    await _command(command, {'workbench': bench.id});
  }
}
