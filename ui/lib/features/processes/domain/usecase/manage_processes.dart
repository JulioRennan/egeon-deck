import '../entities/processes_view.dart';
import '../repository/processes_repository.dart';

/// Os gestos da janela Processos: varrer, encerrar órfãos, encerrar escolhidos.
class ManageProcesses {
  const ManageProcesses(this._repository);
  final ProcessesRepository _repository;

  Future<ProcessesView> list() => _repository.list();
  Future<ProcessConfirm> confirmReap() => _repository.confirmReap();
  Future<ProcessesView> reap() => _repository.reap();
  Future<ProcessConfirm> confirmKill(List<int> pids) =>
      _repository.confirmKill(pids);
  Future<ProcessesView> kill(List<int> pids) => _repository.kill(pids);
}
