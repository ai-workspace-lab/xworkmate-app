import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_palette.dart';

class AppTheme {
  static ThemeData light() =>
      _theme(brightness: Brightness.light, palette: AppPalette.light);

  static ThemeData dark() =>
      _theme(brightness: Brightness.dark, palette: AppPalette.dark);

  static ThemeData _theme({
    required Brightness brightness,
    required AppPalette palette,
  }) {
    final platform = defaultTargetPlatform;
    final isDesktop =
        platform == TargetPlatform.macOS ||
        platform == TargetPlatform.windows ||
        platform == TargetPlatform.linux;
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: palette.accent,
          brightness: brightness,
          surface: palette.surfacePrimary,
        ).copyWith(
          primary: palette.accent,
          onPrimary: Colors.white,
          secondary: palette.accent,
          onSecondary: Colors.white,
          tertiary: palette.success,
          onTertiary: Colors.white,
          error: palette.danger,
          onError: Colors.white,
          surface: palette.surfacePrimary,
          onSurface: palette.textPrimary,
          surfaceContainerHighest: palette.surfaceSecondary,
          outline: palette.stroke,
          outlineVariant: palette.strokeSoft,
          inverseSurface: palette.textPrimary,
          onInverseSurface: palette.surfacePrimary,
          shadow: palette.shadow,
          scrim: Colors.black.withValues(
            alpha: brightness == Brightness.dark ? 0.62 : 0.14,
          ),
        );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      typography: Typography.material2021(platform: platform),
      colorScheme: colorScheme,
      scaffoldBackgroundColor: palette.canvas,
      extensions: [palette],
    );
    final tunedTextTheme = _textTheme(
      base.textTheme,
      palette: palette,
      isDesktop: isDesktop,
    );

    return base.copyWith(
      splashFactory: NoSplash.splashFactory,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: isDesktop
          ? const VisualDensity(horizontal: -1, vertical: -1)
          : VisualDensity.standard,
      dividerColor: palette.strokeSoft,
      hoverColor: palette.hover,
      textTheme: tunedTextTheme,
      primaryTextTheme: tunedTextTheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: palette.surfacePrimary,
        margin: EdgeInsets.zero,
        shadowColor: palette.shadow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: palette.strokeSoft),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: palette.surfaceSecondary,
        side: BorderSide(color: palette.strokeSoft),
        labelStyle: tunedTextTheme.labelMedium,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          textStyle: tunedTextTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w500,
          ),
          minimumSize: Size(0, isDesktop ? 34 : 36),
          padding: EdgeInsets.symmetric(
            horizontal: isDesktop ? 12 : 14,
            vertical: isDesktop ? 8 : 9,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.textPrimary,
          textStyle: tunedTextTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w500,
          ),
          minimumSize: Size(0, isDesktop ? 34 : 36),
          padding: EdgeInsets.symmetric(
            horizontal: isDesktop ? 12 : 14,
            vertical: isDesktop ? 8 : 9,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          side: BorderSide(color: palette.strokeSoft),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: palette.textPrimary,
          textStyle: tunedTextTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w500,
          ),
          minimumSize: Size(0, isDesktop ? 32 : 34),
          padding: EdgeInsets.symmetric(
            horizontal: isDesktop ? 10 : 12,
            vertical: isDesktop ? 8 : 9,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: palette.textSecondary,
          backgroundColor: palette.surfaceSecondary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: palette.strokeSoft),
          ),
          minimumSize: const Size(34, 34),
          padding: const EdgeInsets.all(8),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.surfaceSecondary,
        hintStyle: tunedTextTheme.bodyMedium?.copyWith(
          color: palette.textMuted,
        ),
        labelStyle: tunedTextTheme.bodyMedium?.copyWith(
          color: palette.textMuted,
        ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: isDesktop ? 16 : 18,
          vertical: isDesktop ? 12 : 13,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: palette.strokeSoft),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: palette.strokeSoft),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: palette.accent.withValues(alpha: 0.42)),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          side: WidgetStatePropertyAll(BorderSide(color: palette.strokeSoft)),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return palette.surfacePrimary;
            }
            return palette.surfaceSecondary;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return palette.textPrimary;
            }
            return palette.textSecondary;
          }),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          textStyle: WidgetStatePropertyAll(
            tunedTextTheme.labelLarge?.copyWith(fontWeight: FontWeight.w500),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: palette.surfaceTertiary,
        contentTextStyle: TextStyle(color: palette.textPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  static TextTheme _textTheme(
    TextTheme base, {
    required AppPalette palette,
    required bool isDesktop,
  }) {
    final fallbackFonts = switch (defaultTargetPlatform) {
      TargetPlatform.macOS || TargetPlatform.iOS => const <String>[
        '.SF NS Text',
        '.SF Pro Text',
        'PingFang SC',
        'Helvetica Neue',
      ],
      _ => const <String>['Inter', 'Noto Sans CJK SC', 'PingFang SC'],
    };

    TextStyle withUiFont(TextStyle? style) {
      return (style ?? const TextStyle()).copyWith(
        fontFamilyFallback: fallbackFonts,
        package: null,
      );
    }

    return base.copyWith(
      displaySmall: withUiFont(
        base.displaySmall?.copyWith(
          fontSize: isDesktop ? 22 : 24,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.24,
          height: 1.25,
        ),
      ),
      headlineSmall: withUiFont(
        base.headlineSmall?.copyWith(
          fontSize: isDesktop ? 22 : 24,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.24,
          height: 1.25,
        ),
      ),
      titleLarge: withUiFont(
        base.titleLarge?.copyWith(
          fontSize: isDesktop ? 18 : 19,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.16,
          height: 1.3,
        ),
      ),
      titleMedium: withUiFont(
        base.titleMedium?.copyWith(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.08,
          height: 1.35,
        ),
      ),
      titleSmall: withUiFont(
        base.titleSmall?.copyWith(
          fontSize: isDesktop ? 14 : 15,
          fontWeight: FontWeight.w500,
          height: 1.4,
        ),
      ),
      bodyLarge: withUiFont(
        base.bodyLarge?.copyWith(
          fontSize: isDesktop ? 14 : 15,
          fontWeight: FontWeight.w400,
          height: 1.4,
          color: palette.textPrimary,
        ),
      ),
      bodyMedium: withUiFont(
        base.bodyMedium?.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          height: 1.4,
          color: palette.textSecondary,
        ),
      ),
      bodySmall: withUiFont(
        base.bodySmall?.copyWith(
          fontSize: isDesktop ? 12 : 13,
          fontWeight: FontWeight.w400,
          height: 1.45,
          color: palette.textMuted,
        ),
      ),
      labelLarge: withUiFont(
        base.labelLarge?.copyWith(
          fontSize: isDesktop ? 13 : 14,
          fontWeight: FontWeight.w500,
          height: 1.2,
        ),
      ),
      labelMedium: withUiFont(
        base.labelMedium?.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          height: 1.2,
        ),
      ),
      labelSmall: withUiFont(
        base.labelSmall?.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          height: 1.2,
        ),
      ),
    );
  }
}
