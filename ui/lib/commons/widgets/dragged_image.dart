import 'package:flutter/services.dart';

/// A imagem que está sendo arrastada, em PNG, para o arrasto que não traz
/// arquivo (um print de certos apps só deixa PNG ou TIFF na área de arrasto).
/// Quem lê é o plugin do runner (`macos/Runner/Drop`); sem plugin ou sem
/// imagem, nulo.
const _channel = MethodChannel('egeon/image-drop');

Future<Uint8List?> readDraggedImage() async {
  try {
    return await _channel.invokeMethod<Uint8List>('draggedImage');
  } on PlatformException {
    return null;
  } on MissingPluginException {
    return null;
  }
}
