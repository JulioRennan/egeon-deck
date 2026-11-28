import 'package:material_ui/material_ui.dart';

import 'egeon_colors.dart';
import 'egeon_tokens.dart';
import 'egeon_type.dart';

/// ThemeData base. Os componentes do Egeon são widgets próprios; o tema existe para que
/// o que vier do Material (diálogos do sistema, seleção de texto, scrollbars, tooltips)
/// já nasça com a cara do Egeon e sem efeitos de toque (ripple) de celular.
abstract final class EgeonTheme {
  static ThemeData dark() {
    const c = EgeonColors.dark;
    final scheme = const ColorScheme.dark().copyWith(
      primary: c.primary,
      onPrimary: c.onPrimary,
      secondary: c.accent,
      onSecondary: c.onAccent,
      error: c.danger,
      onError: c.onDanger,
      surface: c.graphite,
      onSurface: c.textPrimary,
      surfaceContainerLowest: c.obsidian,
      surfaceContainerLow: c.obsidian,
      surfaceContainer: c.graphite,
      surfaceContainerHigh: c.carbon,
      surfaceContainerHighest: c.steel,
      onSurfaceVariant: c.textSecondary,
      outline: c.lineStrong,
      outlineVariant: c.line,
      shadow: const Color(0xFF000000),
      scrim: c.scrim,
    );
    TextStyle t(TextStyle s, Color col) => s.copyWith(color: col);
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      fontFamily: EgeonType.sans,
      fontFamilyFallback: EgeonType.sansFallback,
      scaffoldBackgroundColor: c.graphite,
      canvasColor: c.graphite,
      extensions: const [EgeonColors.dark],
      // Desktop: nada de ripple, nada de densidade de toque.
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: c.steel,
      focusColor: c.accentSoft,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.standard,
      textTheme: TextTheme(
        displaySmall: t(EgeonType.display, c.textPrimary),
        titleLarge: t(EgeonType.title, c.textPrimary),
        titleMedium: t(EgeonType.heading, c.textPrimary),
        bodyLarge: t(EgeonType.body, c.textPrimary),
        bodyMedium: t(EgeonType.body, c.textPrimary),
        bodySmall: t(EgeonType.small, c.textSecondary),
        labelLarge: t(EgeonType.label, c.textPrimary),
        labelMedium: t(EgeonType.small, c.textSecondary),
        labelSmall: t(EgeonType.caption, c.textMuted),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: c.accent,
        selectionColor: c.termSelection,
        selectionHandleColor: c.accent,
      ),
      dividerTheme: DividerThemeData(
        color: c.lineSubtle,
        thickness: 1,
        space: 1,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll(6),
        radius: const Radius.circular(3),
        thumbColor: WidgetStateProperty.resolveWith(
          (s) =>
              s.contains(WidgetState.hovered) ? c.controlBorder : c.lineStrong,
        ),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 500),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        textStyle: EgeonType.caption.copyWith(
          color: c.textPrimary,
          fontWeight: FontWeight.w400,
        ),
        decoration: BoxDecoration(
          color: c.carbon,
          borderRadius: BorderRadius.circular(EgeonRadius.sm),
          border: Border.all(color: c.line),
          boxShadow: EgeonShadow.float,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.carbon,
        elevation: 0,
        menuPadding: const EdgeInsets.all(6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(EgeonRadius.lg),
          side: BorderSide(color: c.line),
        ),
        textStyle: EgeonType.small.copyWith(color: c.textPrimary),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.carbon,
        elevation: 0,
        barrierColor: c.scrim,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(EgeonRadius.xl),
          side: BorderSide(color: c.line),
        ),
        titleTextStyle: EgeonType.title.copyWith(color: c.textPrimary),
        contentTextStyle: EgeonType.body.copyWith(color: c.textSecondary),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: c.carbon,
        constraints: const BoxConstraints(minHeight: EgeonSize.controlMd),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: EgeonSpace.s3,
          vertical: 8,
        ),
        hintStyle: EgeonType.body.copyWith(color: c.textMuted),
        // Uma borda só: o estado troca a cor, nunca soma um contorno.
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(EgeonRadius.md),
          borderSide: BorderSide(color: c.lineStrong),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(EgeonRadius.md),
          borderSide: BorderSide(color: c.accent, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(EgeonRadius.md),
          borderSide: BorderSide(color: c.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(EgeonRadius.md),
          borderSide: BorderSide(color: c.danger, width: 2),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(EgeonRadius.md),
          borderSide: BorderSide(color: c.line),
        ),
      ),
    );
  }
}
