import 'package:flutter/material.dart';

@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.canvas,
    required this.sidebar,
    required this.sidebarBorder,
    required this.chromeBackground,
    required this.chromeSurface,
    required this.chromeSurfacePressed,
    required this.chromeHighlight,
    required this.chromeStroke,
    required this.chromeInset,
    required this.chromeShadowAmbient,
    required this.chromeShadowLift,
    required this.surfacePrimary,
    required this.surfaceSecondary,
    required this.surfaceTertiary,
    required this.stroke,
    required this.strokeSoft,
    required this.accent,
    required this.accentHover,
    required this.accentMuted,
    required this.idle,
    required this.success,
    required this.warning,
    required this.danger,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.shadow,
    required this.hover,
  });

  final Color canvas;
  final Color sidebar;
  final Color sidebarBorder;
  final Color chromeBackground;
  final Color chromeSurface;
  final Color chromeSurfacePressed;
  final Color chromeHighlight;
  final Color chromeStroke;
  final Color chromeInset;
  final BoxShadow chromeShadowAmbient;
  final BoxShadow chromeShadowLift;
  final Color surfacePrimary;
  final Color surfaceSecondary;
  final Color surfaceTertiary;
  final Color stroke;
  final Color strokeSoft;
  final Color accent;
  final Color accentHover;
  final Color accentMuted;
  final Color idle;
  final Color success;
  final Color warning;
  final Color danger;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color shadow;
  final Color hover;

  static const AppPalette light = AppPalette(
    canvas: Color(0xFFF8F9FA),
    sidebar: Color(0xFFF2F5F8),
    sidebarBorder: Color(0x24A6B4C8),
    chromeBackground: Color(0xFFF2F5F8),
    chromeSurface: Color(0xFFFFFFFF),
    chromeSurfacePressed: Color(0xFFF2F5F8),
    chromeHighlight: Color(0xFFFBFCFD),
    chromeStroke: Color(0x2EA6B4C8),
    chromeInset: Color(0xFFE9EEF4),
    chromeShadowAmbient: BoxShadow(
      color: Color(0x120058BD),
      blurRadius: 24,
      offset: Offset(0, 8),
      spreadRadius: -18,
    ),
    chromeShadowLift: BoxShadow(
      color: Color(0x160058BD),
      blurRadius: 26,
      offset: Offset(0, 10),
      spreadRadius: -18,
    ),
    surfacePrimary: Color(0xFFFFFFFF),
    surfaceSecondary: Color(0xFFF2F5F8),
    surfaceTertiary: Color(0xFFE9EEF4),
    stroke: Color(0x2EA6B4C8),
    strokeSoft: Color(0x24A6B4C8),
    accent: Color(0xFF0058BD),
    accentHover: Color(0xFF004DA8),
    accentMuted: Color(0xFFE8F0FB),
    idle: Color(0xFF98A1B2),
    success: Color(0xFF34A853),
    warning: Color(0xFF8F4A00),
    danger: Color(0xFFC3655C),
    textPrimary: Color(0xFF1C1B1F),
    textSecondary: Color(0xFF667085),
    textMuted: Color(0xFF98A1B2),
    shadow: Color(0x120058BD),
    hover: Color(0xFFEFF3F8),
  );

  static const AppPalette dark = AppPalette(
    canvas: Color(0xFF141422),
    sidebar: Color(0xFF171C28),
    sidebarBorder: Color(0x30CAC4D0),
    chromeBackground: Color(0xFF171C28),
    chromeSurface: Color(0xFF1E2433),
    chromeSurfacePressed: Color(0xFF262D3F),
    chromeHighlight: Color(0xFF22293A),
    chromeStroke: Color(0x36CAC4D0),
    chromeInset: Color(0xFF1A2130),
    chromeShadowAmbient: BoxShadow(
      color: Color(0x2A4B8FE8),
      blurRadius: 24,
      offset: Offset(0, 8),
      spreadRadius: -18,
    ),
    chromeShadowLift: BoxShadow(
      color: Color(0x324B8FE8),
      blurRadius: 28,
      offset: Offset(0, 10),
      spreadRadius: -18,
    ),
    surfacePrimary: Color(0xFF171C28),
    surfaceSecondary: Color(0xFF1E2433),
    surfaceTertiary: Color(0xFF262D3F),
    stroke: Color(0x36CAC4D0),
    strokeSoft: Color(0x2ACAC4D0),
    accent: Color(0xFF4B8FE8),
    accentHover: Color(0xFF5B9BF0),
    accentMuted: Color(0xFF1C3355),
    idle: Color(0xFF8B95A8),
    success: Color(0xFF5CB978),
    warning: Color(0xFFE0AE5A),
    danger: Color(0xFFEF9A9A),
    textPrimary: Color(0xFFE6E1E5),
    textSecondary: Color(0xFFB0B8C8),
    textMuted: Color(0xFF8B95A8),
    shadow: Color(0x5A000000),
    hover: Color(0xFF22293A),
  );

  @override
  ThemeExtension<AppPalette> copyWith({
    Color? canvas,
    Color? sidebar,
    Color? sidebarBorder,
    Color? chromeBackground,
    Color? chromeSurface,
    Color? chromeSurfacePressed,
    Color? chromeHighlight,
    Color? chromeStroke,
    Color? chromeInset,
    BoxShadow? chromeShadowAmbient,
    BoxShadow? chromeShadowLift,
    Color? surfacePrimary,
    Color? surfaceSecondary,
    Color? surfaceTertiary,
    Color? stroke,
    Color? strokeSoft,
    Color? accent,
    Color? accentHover,
    Color? accentMuted,
    Color? idle,
    Color? success,
    Color? warning,
    Color? danger,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? shadow,
    Color? hover,
  }) {
    return AppPalette(
      canvas: canvas ?? this.canvas,
      sidebar: sidebar ?? this.sidebar,
      sidebarBorder: sidebarBorder ?? this.sidebarBorder,
      chromeBackground: chromeBackground ?? this.chromeBackground,
      chromeSurface: chromeSurface ?? this.chromeSurface,
      chromeSurfacePressed: chromeSurfacePressed ?? this.chromeSurfacePressed,
      chromeHighlight: chromeHighlight ?? this.chromeHighlight,
      chromeStroke: chromeStroke ?? this.chromeStroke,
      chromeInset: chromeInset ?? this.chromeInset,
      chromeShadowAmbient: chromeShadowAmbient ?? this.chromeShadowAmbient,
      chromeShadowLift: chromeShadowLift ?? this.chromeShadowLift,
      surfacePrimary: surfacePrimary ?? this.surfacePrimary,
      surfaceSecondary: surfaceSecondary ?? this.surfaceSecondary,
      surfaceTertiary: surfaceTertiary ?? this.surfaceTertiary,
      stroke: stroke ?? this.stroke,
      strokeSoft: strokeSoft ?? this.strokeSoft,
      accent: accent ?? this.accent,
      accentHover: accentHover ?? this.accentHover,
      accentMuted: accentMuted ?? this.accentMuted,
      idle: idle ?? this.idle,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      shadow: shadow ?? this.shadow,
      hover: hover ?? this.hover,
    );
  }

  @override
  ThemeExtension<AppPalette> lerp(
    covariant ThemeExtension<AppPalette>? other,
    double t,
  ) {
    if (other is! AppPalette) {
      return this;
    }

    return AppPalette(
      canvas: Color.lerp(canvas, other.canvas, t) ?? canvas,
      sidebar: Color.lerp(sidebar, other.sidebar, t) ?? sidebar,
      sidebarBorder:
          Color.lerp(sidebarBorder, other.sidebarBorder, t) ?? sidebarBorder,
      chromeBackground:
          Color.lerp(chromeBackground, other.chromeBackground, t) ??
          chromeBackground,
      chromeSurface:
          Color.lerp(chromeSurface, other.chromeSurface, t) ?? chromeSurface,
      chromeSurfacePressed:
          Color.lerp(chromeSurfacePressed, other.chromeSurfacePressed, t) ??
          chromeSurfacePressed,
      chromeHighlight:
          Color.lerp(chromeHighlight, other.chromeHighlight, t) ??
          chromeHighlight,
      chromeStroke:
          Color.lerp(chromeStroke, other.chromeStroke, t) ?? chromeStroke,
      chromeInset: Color.lerp(chromeInset, other.chromeInset, t) ?? chromeInset,
      chromeShadowAmbient:
          BoxShadow.lerp(chromeShadowAmbient, other.chromeShadowAmbient, t) ??
          chromeShadowAmbient,
      chromeShadowLift:
          BoxShadow.lerp(chromeShadowLift, other.chromeShadowLift, t) ??
          chromeShadowLift,
      surfacePrimary:
          Color.lerp(surfacePrimary, other.surfacePrimary, t) ?? surfacePrimary,
      surfaceSecondary:
          Color.lerp(surfaceSecondary, other.surfaceSecondary, t) ??
          surfaceSecondary,
      surfaceTertiary:
          Color.lerp(surfaceTertiary, other.surfaceTertiary, t) ??
          surfaceTertiary,
      stroke: Color.lerp(stroke, other.stroke, t) ?? stroke,
      strokeSoft: Color.lerp(strokeSoft, other.strokeSoft, t) ?? strokeSoft,
      accent: Color.lerp(accent, other.accent, t) ?? accent,
      accentHover: Color.lerp(accentHover, other.accentHover, t) ?? accentHover,
      accentMuted: Color.lerp(accentMuted, other.accentMuted, t) ?? accentMuted,
      idle: Color.lerp(idle, other.idle, t) ?? idle,
      success: Color.lerp(success, other.success, t) ?? success,
      warning: Color.lerp(warning, other.warning, t) ?? warning,
      danger: Color.lerp(danger, other.danger, t) ?? danger,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t) ?? textPrimary,
      textSecondary:
          Color.lerp(textSecondary, other.textSecondary, t) ?? textSecondary,
      textMuted: Color.lerp(textMuted, other.textMuted, t) ?? textMuted,
      shadow: Color.lerp(shadow, other.shadow, t) ?? shadow,
      hover: Color.lerp(hover, other.hover, t) ?? hover,
    );
  }
}

extension AppPaletteBuildContext on BuildContext {
  AppPalette get palette => Theme.of(this).extension<AppPalette>()!;
}
