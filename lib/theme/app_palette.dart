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
    canvas: Color(0xFFF8FAFC),
    sidebar: Color(0xFFF8FAFC),
    sidebarBorder: Color(0xFFE5E7EB),
    surfacePrimary: Color(0xFFFFFFFF),
    surfaceSecondary: Color(0xFFF8FAFC),
    surfaceTertiary: Color(0xFFF1F5F9),
    stroke: Color(0xFFE5E7EB),
    strokeSoft: Color(0xFFF1F5F9),
    accent: Color(0xFF3B82F6),
    accentHover: Color(0xFF2563EB),
    accentMuted: Color(0xFFDBEAFE),
    idle: Color(0xFF94A3B8),
    success: Color(0xFF22C55E),
    warning: Color(0xFFF59E0B),
    danger: Color(0xFFEF4444),
    textPrimary: Color(0xFF111827),
    textSecondary: Color(0xFF6B7280),
    textMuted: Color(0xFF64748B),
    shadow: Color(0x0F0F172A),
    hover: Color(0xFFEFF6FF),
  );

  static const AppPalette dark = AppPalette(
    canvas: Color(0xFF0B1220),
    sidebar: Color(0xFF0F172A),
    sidebarBorder: Color(0xFF1E293B),
    surfacePrimary: Color(0xFF111827),
    surfaceSecondary: Color(0xFF0F172A),
    surfaceTertiary: Color(0xFF172033),
    stroke: Color(0xFF223046),
    strokeSoft: Color(0xFF162033),
    accent: Color(0xFF3B82F6),
    accentHover: Color(0xFF2563EB),
    accentMuted: Color(0xFF142B52),
    idle: Color(0xFF94A3B8),
    success: Color(0xFF22C55E),
    warning: Color(0xFFF59E0B),
    danger: Color(0xFFEF4444),
    textPrimary: Color(0xFFF8FAFC),
    textSecondary: Color(0xFF94A3B8),
    textMuted: Color(0xFF64748B),
    shadow: Color(0x52000000),
    hover: Color(0xFF11213A),
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
