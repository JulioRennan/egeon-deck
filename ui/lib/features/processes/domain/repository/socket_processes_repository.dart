import '../../../../core/adapters/egeon_socket_client.dart';
import '../entities/processes_view.dart';
import 'processes_repository.dart';
import '../errors/processes_error.dart';

/// Os processos falando com o core Rust: `processes` varre, e encerrar tem
/// ensaio (`dry_run`) que devolve a pergunta escrita e o gesto de verdade.
class SocketProcessesRepository implements ProcessesRepository {
  const SocketProcessesRepository(this._client);

  final EgeonSocketClient _client;

  /// Recusa e queda do socket viram [ProcessesError].
  Future<EgeonMessage> _request(String cmd, [EgeonMessage args = const {}]) =>
      _client
          .request(cmd, args)
          .failingAs(
            refused: ProcessesRefused.new,
            offline: ProcessesOffline.new,
          );

  @override
  Future<ProcessesView> list() async =>
      ProcessesView.fromMap(await _request('processes'));

  @override
  Future<ProcessConfirm> confirmReap() async => ProcessConfirm.fromMap(
    await _request('processes_reap', {'dry_run': true}),
  );

  /// A resposta de encerrar não é a lista: o que de fato morreu aparece na
  /// varredura seguinte, como no Swift (que relê meio segundo depois).
  @override
  Future<ProcessesView> reap() async {
    await _request('processes_reap', {'dry_run': false});
    return list();
  }

  @override
  Future<ProcessConfirm> confirmKill(List<int> pids) async =>
      ProcessConfirm.fromMap(
        await _request('processes_kill', {'pids': pids, 'dry_run': true}),
      );

  @override
  Future<ProcessesView> kill(List<int> pids) async {
    await _request('processes_kill', {'pids': pids, 'dry_run': false});
    return list();
  }
}
