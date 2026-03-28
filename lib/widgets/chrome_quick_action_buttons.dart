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
    this.favorite = false,
    this.showFavoriteToggle = false,
    this.favoriteButtonKey,
    this.onToggleFavorite,
  });

  final IconData icon;
  final String? tooltip;
  final VoidCallback onPressed;
  final bool favorite;
  final bool showFavoriteToggle;
  final Key? favoriteButtonKey;
  final Future<void> Function()? onToggleFavorite;

  @override
  State<ChromeIconActionButton> createState() =>
      ChromeIconActionButtonStateInternal();
}

class ChromeIconActionButtonStateInternal
    extends State<ChromeIconActionButton> {
  bool hoveredInternal = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final resolvedBackground = hoveredInternal
        ? palette.chromeSurfacePressed
        : palette.chromeSurface;

    final button = Tooltip(
      message: widget.tooltip ?? '',
      child: MouseRegion(
        onEnter: (_) => setState(() => hoveredInternal = true),
        onExit: (_) => setState(() => hoveredInternal = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                palette.chromeHighlight.withValues(
                  alpha: hoveredInternal ? 0.94 : 0.88,
                ),
                resolvedBackground,
              ],
            ),
            borderRadius: BorderRadius.circular(AppRadius.button),
            border: Border.all(color: palette.chromeStroke),
            boxShadow: [
              hoveredInternal
                  ? palette.chromeShadowLift
                  : palette.chromeShadowAmbient,
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

    return ChromeQuickActionFavoriteFrameInternal(
      favorite: widget.favorite,
      showFavoriteToggle: widget.showFavoriteToggle,
      favoriteButtonKey: widget.favoriteButtonKey,
      onToggleFavorite: widget.onToggleFavorite,
      child: button,
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
    this.favorite = false,
    this.showFavoriteToggle = false,
    this.favoriteButtonKey,
    this.onToggleFavorite,
  });

  final AppLanguage appLanguage;
  final bool compact;
  final String tooltip;
  final VoidCallback onPressed;
  final bool favorite;
  final bool showFavoriteToggle;
  final Key? favoriteButtonKey;
  final Future<void> Function()? onToggleFavorite;

  @override
  State<ChromeLanguageActionButton> createState() =>
      ChromeLanguageActionButtonStateInternal();
}

class ChromeLanguageActionButtonStateInternal
    extends State<ChromeLanguageActionButton> {
  bool hoveredInternal = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final size = widget.compact ? AppSizes.sidebarItemHeight : 44.0;

    final button = MouseRegion(
      onEnter: (_) => setState(() => hoveredInternal = true),
      onExit: (_) => setState(() => hoveredInternal = false),
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
                    alpha: hoveredInternal ? 0.94 : 0.88,
                  ),
                  hoveredInternal
                      ? palette.chromeSurfacePressed
                      : palette.chromeSurface,
                ],
              ),
              borderRadius: BorderRadius.circular(AppRadius.button),
              border: Border.all(color: palette.chromeStroke),
              boxShadow: [
                hoveredInternal
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

    return ChromeQuickActionFavoriteFrameInternal(
      favorite: widget.favorite,
      showFavoriteToggle: widget.showFavoriteToggle,
      favoriteButtonKey: widget.favoriteButtonKey,
      onToggleFavorite: widget.onToggleFavorite,
      child: button,
    );
  }
}

class ChromeQuickActionFavoriteFrameInternal extends StatelessWidget {
  const ChromeQuickActionFavoriteFrameInternal({
    super.key,
    required this.favorite,
    required this.showFavoriteToggle,
    required this.child,
    this.favoriteButtonKey,
    this.onToggleFavorite,
  });

  final bool favorite;
  final bool showFavoriteToggle;
  final Widget child;
  final Key? favoriteButtonKey;
  final Future<void> Function()? onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    if (!showFavoriteToggle) {
      return child;
    }
    final palette = context.palette;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          top: -4,
          right: -4,
          child: Tooltip(
            message: favorite
                ? appText('取消关注', 'Remove from focused panel')
                : appText('加入关注', 'Add to focused panel'),
            child: Material(
              color: palette.surfacePrimary,
              shape: const CircleBorder(),
              child: InkWell(
                key: favoriteButtonKey,
                customBorder: const CircleBorder(),
                onTap: () {
                  onToggleFavorite?.call();
                },
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: Icon(
                    favorite ? Icons.star_rounded : Icons.star_outline_rounded,
                    size: 14,
                    color: favorite ? palette.accent : palette.textMuted,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
