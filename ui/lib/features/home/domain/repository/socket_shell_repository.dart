import '../../../../core/adapters/organization_feed.dart';
import '../../../../core/domain/entities/view_mode.dart';
import '../entities/shell_state.dart';
import 'shell_repository.dart';

/// A casca falando com o core Rust: a bancada na tela é a da aba ativa.
class SocketShellRepository implements ShellRepository {
  const SocketShellRepository(this._feed);

  final OrganizationFeed _feed;

  @override
  Stream<ShellState> watch() => _feed.watch().map(ShellState.fromOrganization);

  @override
  Future<void> setView(ViewMode mode) async {
    final bench = _feed.last?.activeBench;
    if (bench == null) return;
    await _feed.command('set_workbench', {
      'workbench': bench.id,
      'view': mode.wire,
    });
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
    await _feed.command(command, {'workbench': bench.id});
  }
}
