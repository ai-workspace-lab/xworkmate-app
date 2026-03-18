import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_palette.dart';

/// Design tokens for the XWorkmate design system.
/// Follows a modern AI developer tool design language with:
/// - 8px grid spacing
/// - Compact, neutral, professional aesthetic
/// - Consistent border radii
class AppSpacing {
  AppSpacing._();

  // 8px grid system
  static const double xxs = 4.0;
  static const double xs = 8.0;
  static const double sm = 12.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
}

class AppRadius {
  AppRadius._();

  static const double card = 6.0;
  static const double button = 6.0;
  static const double input = 6.0;
  static const double chip = 999.0;
  static const double badge = 999.0;
  static const double dialog = 10.0;
  static const double sidebar = 8.0;
  static const double icon = 6.0;
}

class AppTypography {
  AppTypography._();

  // H1 - 22px weight 600
  static const double h1Size = 22.0;
  static const FontWeight h1Weight = FontWeight.w600;
  static const double h1Height = 1.25;

  // H2 - 18px weight 600
  static const double h2Size = 18.0;
  static const FontWeight h2Weight = FontWeight.w600;
  static const double h2Height = 1.3;

  // Body - 14px weight 400
  static const double bodySize = 14.0;
  static const FontWeight bodyWeight = FontWeight.w400;
  static const double bodyHeight = 1.4;

  // Meta - 12px weight 400
  static const double metaSize = 12.0;
  static const FontWeight metaWeight = FontWeight.w400;
  static const double metaHeight = 1.45;
}

class AppSizes {
  AppSizes._();

  // Sidebar
  static const double sidebarItemHeight = 36.0;
  static const double sidebarIconSize = 18.0;
  static const double sidebarTextSize = 14.0;
  static const double sidebarExpandedWidth = 204.0;
  static const double sidebarCollapsedWidth = 72.0;

  // Input area
  static const double textareaHeight = 48.0;
  static const double toolbarHeight = 36.0;

  // Buttons
  static const double buttonHeightDesktop = 34.0;
  static const double buttonHeightMobile = 36.0;
}

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
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(color: palette.strokeSoft),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: palette.surfaceSecondary,
        side: BorderSide(color: palette.strokeSoft),
        labelStyle: tunedTextTheme.labelMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.chip),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          textStyle: tunedTextTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w500,
          ),
          minimumSize: Size(
            0,
            isDesktop
                ? AppSizes.buttonHeightDesktop
                : AppSizes.buttonHeightMobile,
          ),
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.textPrimary,
          textStyle: tunedTextTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w500,
          ),
          minimumSize: Size(
            0,
            isDesktop
                ? AppSizes.buttonHeightDesktop
                : AppSizes.buttonHeightMobile,
          ),
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
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
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: palette.textSecondary,
          backgroundColor: palette.surfaceSecondary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.icon),
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
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: BorderSide(color: palette.strokeSoft),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: BorderSide(color: palette.strokeSoft),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
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
            EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.chip),
            ),
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.dialog),
        ),
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
      // H1: 22px weight 600
      displaySmall: withUiFont(
        base.displaySmall?.copyWith(
          fontSize: AppTypography.h1Size,
          fontWeight: AppTypography.h1Weight,
          letterSpacing: -0.24,
          height: AppTypography.h1Height,
        ),
      ),
      headlineSmall: withUiFont(
        base.headlineSmall?.copyWith(
          fontSize: AppTypography.h1Size,
          fontWeight: AppTypography.h1Weight,
          letterSpacing: -0.24,
          height: AppTypography.h1Height,
        ),
      ),
      // H2: 18px weight 600
      titleLarge: withUiFont(
        base.titleLarge?.copyWith(
          fontSize: AppTypography.h2Size,
          fontWeight: AppTypography.h2Weight,
          letterSpacing: -0.16,
          height: AppTypography.h2Height,
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
      // Body: 14px weight 400
      bodyLarge: withUiFont(
        base.bodyLarge?.copyWith(
          fontSize: AppTypography.bodySize,
          fontWeight: AppTypography.bodyWeight,
          height: AppTypography.bodyHeight,
          color: palette.textPrimary,
        ),
      ),
      bodyMedium: withUiFont(
        base.bodyMedium?.copyWith(
          fontSize: AppTypography.bodySize,
          fontWeight: AppTypography.bodyWeight,
          height: AppTypography.bodyHeight,
          color: palette.textSecondary,
        ),
      ),
      // Meta: 12px weight 400
      bodySmall: withUiFont(
        base.bodySmall?.copyWith(
          fontSize: AppTypography.metaSize,
          fontWeight: AppTypography.metaWeight,
          height: AppTypography.metaHeight,
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
