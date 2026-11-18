import 'package:flutter/painting.dart';

/// Paleta do app. O tema é sempre escuro: não há variante clara.
abstract final class AppColors {
  static const background = Color(0xFF171717);
  static const text = Color(0xFFE6E6E6);
  static const textMuted = Color(0xFF8A8A8A);

  static const tabsBar = Color(0xFF121212);

  /// O canvas: fundo, grid, ligações e controles flutuantes.
  static const canvasBackground = Color(0xFF0F121A);
  static const edgeLineSolid = Color(0xFF666666);

  static const terminalBackground = Color(0xFF1A1A1A);
  static const terminalForeground = Color(0xFFD8D8D8);
  static const terminalCursor = Color(0xFFD8D8D8);

  /// Os avisos de estado das bancadas (ADR-024): laranja pede você, verde terminou.
  static const attention = Color(0xFFFF9F0A);
  static const done = Color(0xFF30D158);
  static const accent = Color(0xFF0A84FF);

  /// Branco com a opacidade pedida: é como o legado pinta fundo, texto e fio.
  static Color white(double opacity) => Color.fromRGBO(255, 255, 255, opacity);
  static Color black(double opacity) => Color.fromRGBO(0, 0, 0, opacity);
}
