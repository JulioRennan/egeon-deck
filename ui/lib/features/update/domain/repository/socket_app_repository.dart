import '../../../../core/adapters/egeon_socket_client.dart';
import '../entities/app_effect.dart';
import '../entities/app_state.dart';
import 'app_repository.dart';

/// O app falando com o core Rust pelo tópico `app` (decisão 34): o estado vem
/// inteiro sem `effect`, e os efeitos chegam no mesmo tópico.
class SocketAppRepository implements AppRepository {
  const SocketAppRepository(this._client);

  final EgeonSocketClient _client;

  @override
  Stream<AppState> watch() => _client
      .subscribe('app')
      .where((event) => event['effect'] == null)
      .map(AppState.fromMap);

  @override
  Stream<AppEffect> effects() => _client
      .subscribe('app')
      .where((event) => event['effect'] != null)
      .map(AppEffect.tryParse)
      .where((effect) => effect != null)
      .cast<AppEffect>();

  @override
  Future<void> answerUpdate({
    required String version,
    required bool accept,
    required bool auto,
  }) async {
    await _client.request('update_answer', {
      'version': version,
      'accept': accept,
      'auto': auto,
    });
  }

  @override
  Future<void> setUpdateAuto({required bool on}) async {
    await _client.request('update_auto', {'on': on});
  }

  @override
  Future<void> pressUpdateMenu() async {
    await _client.request('update_menu');
  }

  @override
  Future<void> setReaperEnabled({required bool on}) async {
    await _client.request('reaper_enabled', {'on': on});
  }
}
