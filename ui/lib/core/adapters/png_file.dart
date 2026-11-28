import 'dart:io';
import 'dart:typed_data';

/// Grava o PNG no caminho que o core mandou, criando as pastas. É o único lugar
/// que escreve imagem em disco.
Future<void> writePng(String path, Uint8List bytes) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes);
}
