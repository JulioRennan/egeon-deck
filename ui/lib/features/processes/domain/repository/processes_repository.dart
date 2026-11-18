import '../entities/processes_view.dart';

abstract interface class ProcessesRepository {
  /// A lista agora (o core varre os processos).
  Future<ProcessesView> list();

  /// A pergunta de encerrar os órfãos, escrita pelo core.
  Future<ProcessConfirm> confirmReap();

  /// Encerra os órfãos (SIGTERM) e devolve a lista nova.
  Future<ProcessesView> reap();

  /// A pergunta de encerrar os [pids], escrita pelo core: ela avisa de quantos
  /// ainda são de terminal aberto.
  Future<ProcessConfirm> confirmKill(List<int> pids);

  /// Encerra os [pids] (SIGTERM) e devolve a lista nova.
  Future<ProcessesView> kill(List<int> pids);
}
