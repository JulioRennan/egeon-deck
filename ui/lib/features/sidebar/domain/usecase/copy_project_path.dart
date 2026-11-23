import '../../../../core/adapters/clipboard_writer.dart';

/// "Copiar caminho" do projeto: o caminho vai para a área de transferência.
class CopyProjectPath {
  const CopyProjectPath(this._clipboard);

  final ClipboardWriter _clipboard;

  Future<void> call(String path) async => _clipboard.write(path);
}
