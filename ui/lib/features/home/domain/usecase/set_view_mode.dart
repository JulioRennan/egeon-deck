import '../../../../core/domain/entities/view_mode.dart';
import '../repository/shell_repository.dart';

class SetViewMode {
  const SetViewMode(this._repository);

  final ShellRepository _repository;

  Future<void> call(ViewMode mode) => _repository.setView(mode);
}
