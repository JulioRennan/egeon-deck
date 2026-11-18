import 'package:flutter/services.dart';

/// O que o menu Editar manda ao responder da janela do macOS. Existe para a
/// página web (a `WKWebView` copia, cola e desfaz pela cadeia do AppKit, não
/// por teclas do Flutter); campos de texto e terminal tratam as próprias teclas
/// em Dart, antes de o menu ver o atalho.
enum EditAction { undo, redo, cut, copy, paste, selectAll }

abstract interface class NativeEdit {
  Future<void> send(EditAction action);
}

class ChannelNativeEdit implements NativeEdit {
  const ChannelNativeEdit();

  static const _channel = MethodChannel('egeon/edit');

  @override
  Future<void> send(EditAction action) async {
    try {
      await _channel.invokeMethod<bool>('send', action.name);
    } on PlatformException {
      // Sem responder que aceite a ação, não há nada a fazer.
    } on MissingPluginException {
      // Fora do macOS não há cadeia de responders.
    }
  }
}
