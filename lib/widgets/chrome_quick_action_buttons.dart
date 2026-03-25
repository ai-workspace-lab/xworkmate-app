import 'package:flutter/material.dart';

import '../i18n/app_language.dart';
import '../theme/app_palette.dart';
import '../theme/app_theme.dart';

IconData chromeThemeToggleIcon(ThemeMode themeMode) {
  return switch (themeMode) {
    ThemeMode.dark => Icons.dark_mode_rounded,
    ThemeMode.light => Icons.light_mode_rounded,
    ThemeMode.system => Icons.brightness_auto_rounded,
  };
}

String chromeThemeToggleTooltip(ThemeMode themeMode) {
  return themeMode == ThemeMode.dark
      ? appText('切换浅色', 'Switch to light')
      : appText('切换深色', 'Switch to dark');
}

class ChromeIconActionButton extends StatefulWidget {
  const ChromeIconActionButton({
    super.key,
    required this.icon,
    this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String? tooltip;
  final VoidCallback onPressed;

  @override
  State<ChromeIconActionButton> createState() => _ChromeIconActionButtonState();
}

class _ChromeIconActionButtonState extends State<ChromeIconActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final resolvedBackground = _hovered
        ? palette.chromeSurfacePressed
        : palette.chromeSurface;

    return Tooltip(
      message: widget.tooltip ?? '',
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                palette.chromeHighlight.withValues(
                  alpha: _hovered ? 0.94 : 0.88,
                ),
                resolvedBackground,
              ],
            ),
            borderRadius: BorderRadius.circular(AppRadius.button),
            border: Border.all(color: palette.chromeStroke),
            boxShadow: [
              _hovered ? palette.chromeShadowLift : palette.chromeShadowAmbient,
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.button),
              onTap: widget.onPressed,
              child: Container(
                height: AppSizes.sidebarItemHeight,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                child: Center(
                  child: Icon(
                    widget.icon,
                    size: AppSizes.sidebarIconSize,
                    color: palette.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ChromeLanguageActionButton extends StatefulWidget {
  const ChromeLanguageActionButton({
    super.key,
    required this.appLanguage,
    required this.compact,
    required this.tooltip,
    required this.onPressed,
  });

  final AppLanguage appLanguage;
  final bool compact;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  State<ChromeLanguageActionButton> createState() =>
      _ChromeLanguageActionButtonState();
}

class _ChromeLanguageActionButtonState
    extends State<ChromeLanguageActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final size = widget.compact ? AppSizes.sidebarItemHeight : 44.0;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Tooltip(
        message: widget.tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.button),
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  palette.chromeHighlight.withValues(
                    alpha: _hovered ? 0.94 : 0.88,
                  ),
                  _hovered
                      ? palette.chromeSurfacePressed
                      : palette.chromeSurface,
                ],
              ),
              borderRadius: BorderRadius.circular(AppRadius.button),
              border: Border.all(color: palette.chromeStroke),
              boxShadow: [
                _hovered
                    ? palette.chromeShadowLift
                    : palette.chromeShadowAmbient,
              ],
            ),
            child: Text(
              widget.appLanguage.compactLabel,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: palette.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
