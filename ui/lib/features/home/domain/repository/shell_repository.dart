import '../../../../core/domain/entities/view_mode.dart';
import '../entities/shell_state.dart';

/// A casca: qual bancada está na tela e em que modo. O core Rust decide; aqui
/// se pergunta e se manda o gesto.
abstract interface class ShellRepository {
  Stream<ShellState> watch();

  Future<void> setView(ViewMode mode);

  Future<void> openSettings();

  Future<void> askAccessAgain();
}
