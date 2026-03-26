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
    canvas: Color(0xFFFAF8F4),
    sidebar: Color(0xFFF6F2EC),
    sidebarBorder: Color(0x147E7061),
    chromeBackground: Color(0xFFF6F2EC),
    chromeSurface: Color(0xFFFFFDF9),
    chromeSurfacePressed: Color(0xFFF8F4EE),
    chromeHighlight: Color(0xFFFFFEFB),
    chromeStroke: Color(0x1F7E7061),
    chromeInset: Color(0xFFF3EEE7),
    chromeShadowAmbient: BoxShadow(
      color: Color(0x0A2E2418),
      blurRadius: 16,
      offset: Offset(0, 3),
      spreadRadius: -14,
    ),
    chromeShadowLift: BoxShadow(
      color: Color(0x122E2418),
      blurRadius: 20,
      offset: Offset(0, 8),
      spreadRadius: -12,
    ),
    surfacePrimary: Color(0xFFFFFDF9),
    surfaceSecondary: Color(0xFFF8F4EE),
    surfaceTertiary: Color(0xFFF1EAE1),
    stroke: Color(0x1F7E7061),
    strokeSoft: Color(0x147E7061),
    accent: Color(0xFF635BFF),
    accentHover: Color(0xFF564EF0),
    accentMuted: Color(0xFFECE9FF),
    idle: Color(0xFF9D968C),
    success: Color(0xFF2F7D57),
    warning: Color(0xFF8A5A1F),
    danger: Color(0xFFB65C4A),
    textPrimary: Color(0xFF24211D),
    textSecondary: Color(0xFF6E675F),
    textMuted: Color(0xFF9D968C),
    shadow: Color(0x102E2418),
    hover: Color(0xFFF3EEE7),
  );

  static const AppPalette dark = AppPalette(
    canvas: Color(0xFF171513),
    sidebar: Color(0xFF1D1A17),
    sidebarBorder: Color(0x14EEE3D6),
    chromeBackground: Color(0xFF1D1A17),
    chromeSurface: Color(0xFF24201C),
    chromeSurfacePressed: Color(0xFF2B2621),
    chromeHighlight: Color(0xFF2E2822),
    chromeStroke: Color(0x1FEEE3D6),
    chromeInset: Color(0xFF23201C),
    chromeShadowAmbient: BoxShadow(
      color: Color(0x22000000),
      blurRadius: 22,
      offset: Offset(0, 8),
      spreadRadius: -14,
    ),
    chromeShadowLift: BoxShadow(
      color: Color(0x2B000000),
      blurRadius: 20,
      offset: Offset(0, 8),
      spreadRadius: -12,
    ),
    surfacePrimary: Color(0xFF24201C),
    surfaceSecondary: Color(0xFF2B2621),
    surfaceTertiary: Color(0xFF342E28),
    stroke: Color(0x1FEEE3D6),
    strokeSoft: Color(0x14EEE3D6),
    accent: Color(0xFF8A83FF),
    accentHover: Color(0xFF9A94FF),
    accentMuted: Color(0x2E8A83FF),
    idle: Color(0xFF958B80),
    success: Color(0xFF66B78B),
    warning: Color(0xFFD3A86C),
    danger: Color(0xFFE58C79),
    textPrimary: Color(0xFFF1E9DF),
    textSecondary: Color(0xFFC6BAAD),
    textMuted: Color(0xFF958B80),
    shadow: Color(0x52000000),
    hover: Color(0xFF2B2621),
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
