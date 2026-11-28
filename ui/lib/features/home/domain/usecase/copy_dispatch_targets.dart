import '../../../../core/adapters/clipboard_writer.dart';
import '../repository/menu_repository.dart';

/// "Copiar alvos de dispatch": o core diz os endereços, a área de
/// transferência os recebe.
class CopyDispatchTargets {
  const CopyDispatchTargets(this._menu, this._clipboard);

  final MenuRepository _menu;
  final ClipboardWriter _clipboard;

  Future<void> call() async => _clipboard.write(await _menu.dispatchTargets());
}
