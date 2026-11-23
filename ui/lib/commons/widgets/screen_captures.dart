import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// As regiões da tela que podem virar PNG por nome (`window`, `sidebar`): cada
/// uma é um `RepaintBoundary` com a chave daqui. A região só sai se estiver na
/// árvore, e a vista nativa (o web) não aparece na imagem.
class ScreenCaptures {
  final _keys = <String, GlobalKey>{};

  /// A chave a pôr no `RepaintBoundary` da região [name].
  GlobalKey keyFor(String name) => _keys.putIfAbsent(name, GlobalKey.new);

  /// O PNG da região, ou `null` se ela não está na tela.
  Future<Uint8List?> png(String name) async {
    final context = _keys[name]?.currentContext;
    final boundary = context?.findRenderObject();
    if (context == null || boundary is! RenderRepaintBoundary) return null;
    final ratio = View.of(context).devicePixelRatio;
    // Com algo animando dentro (o spinner), a região pode estar entre dois
    // quadros: o motor só captura o que já foi pintado.
    if (boundary.debugNeedsPaint) await WidgetsBinding.instance.endOfFrame;
    final image = await boundary.toImage(pixelRatio: ratio);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }
}
