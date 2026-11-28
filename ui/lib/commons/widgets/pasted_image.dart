import 'package:flutter/services.dart';

/// O que a área de transferência traz para colar como imagem: os arquivos
/// copiados no Finder ou a imagem em si (print com ⌃⇧⌘4), já em PNG. O
/// `Clipboard` do Flutter só lê texto; quem lê isto é o plugin do runner
/// (`macos/Runner/Drop`).
sealed class PastedClipboard {
  const PastedClipboard();
}

/// Arquivos copiados, todos: quem cola decide quais servem.
final class PastedFiles extends PastedClipboard {
  const PastedFiles(this.paths);
  final List<String> paths;
}

/// A imagem sem arquivo, em PNG.
final class PastedPng extends PastedClipboard {
  const PastedPng(this.bytes);
  final Uint8List bytes;
}

const _channel = MethodChannel('egeon/image-drop');

/// Nulo sem arquivo nem imagem na área de transferência, ou sem o plugin.
Future<PastedClipboard?> readPastedImage() async {
  try {
    final map = await _channel.invokeMapMethod<String, Object?>('pastedImage');
    return switch (map) {
      {'files': final List<Object?> files} => PastedFiles([
        for (final path in files)
          if (path is String) path,
      ]),
      {'png': final Uint8List png} => PastedPng(png),
      _ => null,
    };
  } on PlatformException {
    return null;
  } on MissingPluginException {
    return null;
  }
}
