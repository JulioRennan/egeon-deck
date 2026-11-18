import 'package:flutter/painting.dart';

/// A cor de cada tipo de trecho de código. O core é quem classifica; aqui só
/// se pinta pelo `kind`.
abstract final class CodePalette {
  static const _plain = Color(0xFFE6E6E6);

  static Color of(String kind, {Color base = _plain}) => switch (kind) {
    'keyword' => const Color.fromRGBO(204, 148, 245, 1),
    'type' => const Color.fromRGBO(140, 217, 217, 1),
    'string' => const Color.fromRGBO(222, 199, 153, 1),
    'comment' => const Color.fromRGBO(122, 122, 122, 1),
    'number' => const Color.fromRGBO(230, 173, 122, 1),
    'tag' => const Color.fromRGBO(115, 191, 250, 1),
    'attribute' => const Color.fromRGBO(158, 209, 158, 1),
    _ => base,
  };
}
