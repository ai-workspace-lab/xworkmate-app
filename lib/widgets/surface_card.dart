import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import '../theme/app_theme.dart';

enum SurfaceCardTone { standard, chrome }

class SurfaceCard extends StatefulWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.onTap,
    this.borderRadius = AppRadius.card,
    this.borderWidth = 1,
    this.color,
    this.tone = SurfaceCardTone.standard,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double borderRadius;
  final double borderWidth;
  final Color? color;
  final SurfaceCardTone tone;

  @override
  State<SurfaceCard> createState() => _SurfaceCardState();
}

class _SurfaceCardState extends State<SurfaceCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final baseColor = switch (widget.tone) {
      SurfaceCardTone.standard => widget.color ?? palette.surfacePrimary,
      SurfaceCardTone.chrome => widget.color ?? palette.chromeSurface,
    };
    final hoveredColor = switch (widget.tone) {
      SurfaceCardTone.standard => palette.surfaceSecondary,
      SurfaceCardTone.chrome => palette.chromeSurfacePressed,
    };
    final borderColor = switch (widget.tone) {
      SurfaceCardTone.standard => palette.strokeSoft,
      SurfaceCardTone.chrome => palette.chromeStroke,
    };
    final decoration = switch (widget.tone) {
      SurfaceCardTone.standard => BoxDecoration(
        color: (_hovered && widget.onTap != null ? hoveredColor : baseColor)
            .withValues(alpha: 0.98),
        border: Border.all(color: borderColor, width: widget.borderWidth),
        borderRadius: BorderRadius.circular(widget.borderRadius),
        boxShadow: widget.onTap != null && _hovered
            ? [palette.chromeShadowAmbient]
            : const [],
      ),
      SurfaceCardTone.chrome => BoxDecoration(
        color: (_hovered && widget.onTap != null ? hoveredColor : baseColor)
            .withValues(alpha: 0.98),
        border: Border.all(color: borderColor, width: widget.borderWidth),
        borderRadius: BorderRadius.circular(widget.borderRadius),
        boxShadow: [
          if (_hovered && widget.onTap != null) palette.chromeShadowAmbient,
        ],
      ),
    };

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        decoration: decoration,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            onTap: widget.onTap,
            child: Padding(padding: widget.padding, child: widget.child),
          ),
        ),
      ),
    );
  }
}
