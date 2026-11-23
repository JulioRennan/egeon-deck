import 'dart:ui' show ImageFilter;

import 'package:flutter/painting.dart';

/// Vidro das peças que flutuam (barra de ações, painel de consumo, menus, popovers).
abstract final class EgeonGlass {
  static const background = Color(0x9E0D0F11);
  static const border = Color(0x0FFFFFFF);
  static const highlight = Color(0x08FFFFFF);

  /// CSS blur(20px) é desvio-padrão, igual ao sigma do Flutter.
  static const blurSigma = 20.0;
  static const _sat = 1.3;
  static const _r = 0.2126, _g = 0.7152, _b = 0.0722;
  static final ImageFilter filter = ImageFilter.compose(
    outer: const ColorFilter.matrix(<double>[
      _r * (1 - _sat) + _sat,
      _g * (1 - _sat),
      _b * (1 - _sat),
      0,
      0,
      _r * (1 - _sat),
      _g * (1 - _sat) + _sat,
      _b * (1 - _sat),
      0,
      0,
      _r * (1 - _sat),
      _g * (1 - _sat),
      _b * (1 - _sat) + _sat,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
    ]),
    inner: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
  );
}
