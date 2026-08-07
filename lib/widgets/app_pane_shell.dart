import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import '../theme/app_theme.dart';

/// The container every full-height pane sits in.
///
/// A pane fills its slot edge to edge: one background colour, no radius, no
/// border, no outer margin. Panes are separated from each other by the 1px
/// boundary that the shell overlays on the seam, never by whitespace.
///
/// Radius, stroke and elevation belong to the *content cards* inside a pane
/// (see `SurfaceCard`) — not to the pane itself. Adding them here brings back
/// the floating-card look this container exists to remove.
class AppPaneShell extends StatelessWidget {
  const AppPaneShell({
    super.key,
    required this.child,
    this.background,
    this.padding,
  });

  final Widget child;

  /// Defaults to the primary surface. Side rails pass the recessed background
  /// so the panes read as layered rather than gapped.
  final Color? background;

  /// Defaults to [AppSpacing.paneContent] on all sides. Pass [EdgeInsets.zero]
  /// for panes that manage their own insets (e.g. a scrolling transcript that
  /// must bleed to the edge).
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background ?? context.palette.surfacePrimary,
      ),
      child: Padding(
        padding:
            padding ?? const EdgeInsets.all(AppSpacing.paneContent),
        child: child,
      ),
    );
  }
}
