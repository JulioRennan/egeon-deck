import '../../adapters/egeon_app_launcher.dart';
import '../../adapters/egeon_socket_client.dart';
import 'core_repository.dart';

class SocketCoreRepository implements CoreRepository {
  const SocketCoreRepository({required this._launcher, required this._client});

  final EgeonAppLauncher _launcher;
  final EgeonSocketClient _client;

  @override
  Stream<bool> watchLink() =>
      _client.links.map((link) => link == EgeonLink.connected);

  @override
  Future<void> launch() => _launcher.ensureRunning();

  @override
  void connect() => _client.start();

  @override
  Future<void> stop() async {
    await _client.dispose();
    await _launcher.stop();
  }
}
