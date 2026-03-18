import 'package:flutter/material.dart';

@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.canvas,
    required this.sidebar,
    required this.sidebarBorder,
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
    canvas: Color(0xFFF5F5F7),
    sidebar: Color(0xFFF1F1F3),
    sidebarBorder: Color(0xFFE5E5EA),
    surfacePrimary: Color(0xFFFFFFFF),
    surfaceSecondary: Color(0xFFF1F1F3),
    surfaceTertiary: Color(0xFFECECEF),
    stroke: Color(0xFFE5E5EA),
    strokeSoft: Color(0xFFECECEF),
    accent: Color(0xFF4C8BF5),
    accentHover: Color(0xFF5E98F6),
    accentMuted: Color(0xFFEEF4FF),
    idle: Color(0xFFA1A1A6),
    success: Color(0xFF34C759),
    warning: Color(0xFFFF9F0A),
    danger: Color(0xFFFF3B30),
    textPrimary: Color(0xFF0A0A0A),
    textSecondary: Color(0xFF6B6B6F),
    textMuted: Color(0xFFA1A1A6),
    shadow: Color(0x0A000000),
    hover: Color(0xFFE5E5EA),
  );

  static const AppPalette dark = AppPalette(
    canvas: Color(0xFF0E0F12),
    sidebar: Color(0xFF15171C),
    sidebarBorder: Color(0xFF23262D),
    surfacePrimary: Color(0xFF15171C),
    surfaceSecondary: Color(0xFF1B1E24),
    surfaceTertiary: Color(0xFF22262E),
    stroke: Color(0xFF2B3038),
    strokeSoft: Color(0xFF22262E),
    accent: Color(0xFF4C8BF5),
    accentHover: Color(0xFF6A9DF7),
    accentMuted: Color(0xFF1A2740),
    idle: Color(0xFFA1A1AA),
    success: Color(0xFF34C759),
    warning: Color(0xFFFF9F0A),
    danger: Color(0xFFFF3B30),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFFA1A1AA),
    textMuted: Color(0xFF737982),
    shadow: Color(0x52000000),
    hover: Color(0xFF1B1E24),
  );

  @override
  ThemeExtension<AppPalette> copyWith({
    Color? canvas,
    Color? sidebar,
    Color? sidebarBorder,
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
