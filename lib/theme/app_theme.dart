import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_palette.dart';

class AppSpacing {
  AppSpacing._();

  static const double xxs = 4.0;
  static const double xs = 8.0;
  static const double sm = 12.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
}

class AppRadius {
  AppRadius._();

  static const double card = 16.0;
  static const double button = 12.0;
  static const double input = 16.0;
  static const double chip = 999.0;
  static const double badge = 999.0;
  static const double dialog = 16.0;
  static const double sidebar = 20.0;
  static const double icon = 12.0;
}

class AppTypography {
  AppTypography._();

  static const double displaySize = 28.0;
  static const FontWeight displayWeight = FontWeight.w600;
  static const double displayHeight = 32 / 28;

  static const double titleSize = 20.0;
  static const FontWeight titleWeight = FontWeight.w600;
  static const double titleHeight = 24 / 20;

  static const double sectionSize = 16.0;
  static const FontWeight sectionWeight = FontWeight.w600;
  static const double sectionHeight = 20 / 16;

  static const double bodySize = 14.0;
  static const FontWeight bodyWeight = FontWeight.w400;
  static const double bodyHeight = 20 / 14;

  static const double compactBodySize = 13.0;
  static const FontWeight compactBodyWeight = FontWeight.w400;
  static const double compactBodyHeight = 15 / 13;

  static const double emphasizedBodySize = 14.0;
  static const FontWeight emphasizedBodyWeight = FontWeight.w600;
  static const double emphasizedBodyHeight = 14 / 14;

  static const double captionSize = 12.0;
  static const FontWeight captionWeight = FontWeight.w400;
  static const double captionHeight = 16 / 12;
}

class AppSizes {
  AppSizes._();

  static const double sidebarItemHeight = 40.0;
  static const double sidebarIconSize = 20.0;
  static const double sidebarTextSize = 13.0;
  static const double sidebarExpandedWidth = 212.0;
  static const double sidebarCollapsedWidth = 72.0;

  static const double textareaHeight = 48.0;
  static const double toolbarHeight = 40.0;

  static const double buttonHeightDesktop = 40.0;
  static const double buttonHeightMobile = 40.0;
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
            alpha: brightness == Brightness.dark ? 0.62 : 0.12,
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
    final tunedTextTheme = _textTheme(base.textTheme, palette: palette);

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
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: palette.surfaceSecondary,
        selectedColor: palette.surfacePrimary,
        secondarySelectedColor: palette.surfacePrimary,
        disabledColor: palette.surfaceSecondary,
        side: BorderSide.none,
        checkmarkColor: Colors.transparent,
        labelStyle: tunedTextTheme.labelMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.chip),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: palette.accent,
          foregroundColor: Colors.white,
          shadowColor: palette.shadow,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          textStyle: tunedTextTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          minimumSize: Size(
            0,
            isDesktop
                ? AppSizes.buttonHeightDesktop
                : AppSizes.buttonHeightMobile,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: palette.surfaceSecondary,
          foregroundColor: palette.textPrimary,
          shadowColor: palette.shadow,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          textStyle: tunedTextTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          minimumSize: Size(
            0,
            isDesktop
                ? AppSizes.buttonHeightDesktop
                : AppSizes.buttonHeightMobile,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
          side: BorderSide.none,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: palette.textPrimary,
          textStyle: tunedTextTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w500,
          ),
          minimumSize: Size(0, isDesktop ? 32 : 34),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
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
          surfaceTintColor: Colors.transparent,
          minimumSize: const Size(40, 40),
          padding: const EdgeInsets.all(10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.icon),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.surfacePrimary,
        hintStyle: tunedTextTheme.bodyMedium?.copyWith(
          color: palette.textMuted,
        ),
        labelStyle: tunedTextTheme.bodyMedium?.copyWith(
          color: palette.textMuted,
        ),
        floatingLabelStyle: tunedTextTheme.bodyMedium?.copyWith(
          color: palette.textSecondary,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: const BorderSide(color: Colors.transparent),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: const BorderSide(color: Colors.transparent),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: BorderSide(color: palette.accent.withValues(alpha: 0.18)),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          side: const WidgetStatePropertyAll(BorderSide.none),
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
        backgroundColor: palette.surfacePrimary,
        contentTextStyle: TextStyle(color: palette.textPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.dialog),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: palette.surfacePrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.dialog),
        ),
      ),
    );
  }

  static TextTheme _textTheme(TextTheme base, {required AppPalette palette}) {
    TextStyle withUiFont(TextStyle? style) {
      return (style ?? const TextStyle()).copyWith(
        fontFamily: null,
        fontFamilyFallback: const <String>[],
        package: null,
      );
    }

    return base.copyWith(
      displaySmall: withUiFont(
        base.displaySmall?.copyWith(
          fontSize: AppTypography.displaySize,
          fontWeight: AppTypography.displayWeight,
          letterSpacing: -0.32,
          height: AppTypography.displayHeight,
          color: palette.textPrimary,
        ),
      ),
      headlineSmall: withUiFont(
        base.headlineSmall?.copyWith(
          fontSize: AppTypography.titleSize,
          fontWeight: AppTypography.titleWeight,
          letterSpacing: -0.18,
          height: AppTypography.titleHeight,
          color: palette.textPrimary,
        ),
      ),
      titleLarge: withUiFont(
        base.titleLarge?.copyWith(
          fontSize: AppTypography.sectionSize,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.08,
          height: AppTypography.sectionHeight,
          color: palette.textPrimary,
        ),
      ),
      titleMedium: withUiFont(
        base.titleMedium?.copyWith(
          fontSize: AppTypography.emphasizedBodySize,
          fontWeight: AppTypography.sectionWeight,
          letterSpacing: -0.04,
          height: AppTypography.emphasizedBodyHeight,
          color: palette.textPrimary,
        ),
      ),
      titleSmall: withUiFont(
        base.titleSmall?.copyWith(
          fontSize: AppTypography.bodySize,
          fontWeight: FontWeight.w600,
          height: AppTypography.bodyHeight,
          color: palette.textPrimary,
        ),
      ),
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
          fontSize: AppTypography.compactBodySize,
          fontWeight: AppTypography.compactBodyWeight,
          height: AppTypography.compactBodyHeight,
          color: palette.textSecondary,
        ),
      ),
      bodySmall: withUiFont(
        base.bodySmall?.copyWith(
          fontSize: AppTypography.captionSize,
          fontWeight: AppTypography.captionWeight,
          height: AppTypography.captionHeight,
          color: palette.textMuted,
        ),
      ),
      labelLarge: withUiFont(
        base.labelLarge?.copyWith(
          fontSize: AppTypography.emphasizedBodySize,
          fontWeight: AppTypography.emphasizedBodyWeight,
          height: AppTypography.emphasizedBodyHeight,
          color: palette.textPrimary,
        ),
      ),
      labelMedium: withUiFont(
        base.labelMedium?.copyWith(
          fontSize: AppTypography.captionSize,
          fontWeight: FontWeight.w500,
          height: AppTypography.captionHeight,
          color: palette.textSecondary,
        ),
      ),
      labelSmall: withUiFont(
        base.labelSmall?.copyWith(
          fontSize: AppTypography.captionSize,
          fontWeight: FontWeight.w400,
          height: AppTypography.captionHeight,
          color: palette.textMuted,
        ),
      ),
    );
  }
}
