import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_palette.dart';

// Default theme token set: simple
class SimpleSpacing {
  SimpleSpacing._();

  static const double page = 0.0;
  static const double compact = 6.0;
  static const double section = 8.0;
  static const double xxs = 4.0;
  static const double xs = compact;
  static const double sm = section;
  static const double md = section;
  static const double lg = section;
  static const double xl = 12.0;
}

class SimpleRadius {
  SimpleRadius._();

  static const double card = 6.0;
  static const double button = 8.0;
  static const double input = 8.0;
  static const double chip = 999.0;
  static const double badge = 999.0;
  static const double dialog = 5.0;
  static const double sidebar = 8.0;
  static const double icon = 8.0;
}

class SimpleTypography {
  SimpleTypography._();

  static const double displaySize = 28.0;
  static const FontWeight displayWeight = FontWeight.w600;
  static const double displayHeight = 32 / 28;

  static const double titleSize = 20.0;
  static const FontWeight titleWeight = FontWeight.w600;
  static const double titleHeight = 24 / 20;

  static const double sectionSize = 13.0;
  static const FontWeight sectionWeight = FontWeight.w600;
  static const double sectionHeight = 14 / 13;

  static const double bodySize = 13.0;
  static const FontWeight bodyWeight = FontWeight.w400;
  static const double bodyHeight = 15 / 13;

  static const double compactBodySize = 13.0;
  static const FontWeight compactBodyWeight = FontWeight.w400;
  static const double compactBodyHeight = 15 / 13;

  static const double emphasizedBodySize = 13.0;
  static const FontWeight emphasizedBodyWeight = FontWeight.w600;
  static const double emphasizedBodyHeight = 14 / 13;

  static const double captionSize = 12.0;
  static const FontWeight captionWeight = FontWeight.w400;
  static const double captionHeight = 16 / 12;
}

class SimpleSizes {
  SimpleSizes._();

  static const double sidebarItemHeight = 40.0;
  static const double sidebarIconSize = 20.0;
  static const double sidebarTextSize = 13.0;
  static const double sidebarExpandedWidth = 212.0;
  static const double sidebarCollapsedWidth = 72.0;

  static const double textareaHeight = 36.0;
  static const double toolbarHeight = 40.0;

  static const double inputHeight = 36.0;
  static const double buttonHeightDesktop = 16.0;
  static const double buttonHeightMobile = 16.0;
}

class AppSpacing {
  AppSpacing._();

  static const double page = SimpleSpacing.page;
  static const double compact = SimpleSpacing.compact;
  static const double section = SimpleSpacing.section;
  static const double xxs = SimpleSpacing.xxs;
  static const double xs = SimpleSpacing.xs;
  static const double sm = SimpleSpacing.sm;
  static const double md = SimpleSpacing.md;
  static const double lg = SimpleSpacing.lg;
  static const double xl = SimpleSpacing.xl;
}

class AppRadius {
  AppRadius._();

  static const double card = SimpleRadius.card;
  static const double button = SimpleRadius.button;
  static const double input = SimpleRadius.input;
  static const double chip = SimpleRadius.chip;
  static const double badge = SimpleRadius.badge;
  static const double dialog = SimpleRadius.dialog;
  static const double sidebar = SimpleRadius.sidebar;
  static const double icon = SimpleRadius.icon;
}

class AppTypography {
  AppTypography._();

  static const double displaySize = SimpleTypography.displaySize;
  static const FontWeight displayWeight = SimpleTypography.displayWeight;
  static const double displayHeight = SimpleTypography.displayHeight;

  static const double titleSize = SimpleTypography.titleSize;
  static const FontWeight titleWeight = SimpleTypography.titleWeight;
  static const double titleHeight = SimpleTypography.titleHeight;

  static const double sectionSize = SimpleTypography.sectionSize;
  static const FontWeight sectionWeight = SimpleTypography.sectionWeight;
  static const double sectionHeight = SimpleTypography.sectionHeight;

  static const double bodySize = SimpleTypography.bodySize;
  static const FontWeight bodyWeight = SimpleTypography.bodyWeight;
  static const double bodyHeight = SimpleTypography.bodyHeight;

  static const double compactBodySize = SimpleTypography.compactBodySize;
  static const FontWeight compactBodyWeight =
      SimpleTypography.compactBodyWeight;
  static const double compactBodyHeight = SimpleTypography.compactBodyHeight;

  static const double emphasizedBodySize = SimpleTypography.emphasizedBodySize;
  static const FontWeight emphasizedBodyWeight =
      SimpleTypography.emphasizedBodyWeight;
  static const double emphasizedBodyHeight =
      SimpleTypography.emphasizedBodyHeight;

  static const double captionSize = SimpleTypography.captionSize;
  static const FontWeight captionWeight = SimpleTypography.captionWeight;
  static const double captionHeight = SimpleTypography.captionHeight;
}

class AppSizes {
  AppSizes._();

  static const double sidebarItemHeight = SimpleSizes.sidebarItemHeight;
  static const double sidebarIconSize = SimpleSizes.sidebarIconSize;
  static const double sidebarTextSize = SimpleSizes.sidebarTextSize;
  static const double sidebarExpandedWidth = SimpleSizes.sidebarExpandedWidth;
  static const double sidebarCollapsedWidth = SimpleSizes.sidebarCollapsedWidth;

  static const double textareaHeight = SimpleSizes.textareaHeight;
  static const double toolbarHeight = SimpleSizes.toolbarHeight;

  static const double inputHeight = SimpleSizes.inputHeight;
  static const double buttonHeightDesktop = SimpleSizes.buttonHeightDesktop;
  static const double buttonHeightMobile = SimpleSizes.buttonHeightMobile;
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
          side: BorderSide(color: palette.strokeSoft),
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
            horizontal: AppSpacing.sm,
            vertical: 0,
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
            horizontal: AppSpacing.sm,
            vertical: 0,
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
          minimumSize: Size(
            0,
            isDesktop
                ? AppSizes.buttonHeightDesktop
                : AppSizes.buttonHeightMobile,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xs,
            vertical: 0,
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
        isDense: true,
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
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.compact,
        ),
        constraints: const BoxConstraints(minHeight: AppSizes.inputHeight),
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
              vertical: AppSpacing.compact,
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
          letterSpacing: 0,
          height: AppTypography.sectionHeight,
          color: palette.textPrimary,
        ),
      ),
      titleMedium: withUiFont(
        base.titleMedium?.copyWith(
          fontSize: AppTypography.sectionSize,
          fontWeight: AppTypography.sectionWeight,
          letterSpacing: 0,
          height: AppTypography.sectionHeight,
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
          fontSize: AppTypography.sectionSize,
          fontWeight: AppTypography.emphasizedBodyWeight,
          height: AppTypography.sectionHeight,
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
