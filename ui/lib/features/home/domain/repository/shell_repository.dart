import '../../../../core/domain/entities/view_mode.dart';
import '../entities/shell_snapshot.dart';

/// A casca: qual bancada está na tela e em que modo. O core Rust decide; aqui
/// se pergunta e se manda o gesto.
abstract interface class ShellRepository {
  Stream<ShellSnapshot> watch();

  Future<void> setView(ViewMode mode);

  /// Põe a bancada na tela (a mesma troca de aba que o core já faz).
  Future<void> activate(String benchId);

  Future<void> openSettings();

  Future<void> askAccessAgain();
}
