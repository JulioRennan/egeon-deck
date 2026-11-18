import 'package:flutter/painting.dart';

import 'app_colors.dart';

/// Tipografia e medidas compartilhadas. Sem Material: o visual é desenhado
/// sobre `WidgetsApp`.
abstract final class AppTheme {
  static const textStyle = TextStyle(
    color: AppColors.text,
    fontSize: 13,
    fontFamily: '.AppleSystemUIFont',
    decoration: TextDecoration.none,
  );

  static const terminalFontFamily = 'Menlo';
  static const terminalFontFamilyFallback = ['Monaco', 'Courier New'];
  static const terminalFontSize = 13.0;
}
