import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import '../theme/app_theme.dart';
import 'app_pane_shell.dart';
import 'top_bar.dart';

class DesktopWorkspaceScaffold extends StatelessWidget {
  const DesktopWorkspaceScaffold({
    super.key,
    required this.child,
    this.breadcrumbs = const <AppBreadcrumbItem>[],
    this.eyebrow,
    this.title,
    this.subtitle,
    this.toolbar,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final List<AppBreadcrumbItem> breadcrumbs;
  final String? eyebrow;
  final String? title;
  final String? subtitle;
  final Widget? toolbar;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final hasHeader =
        breadcrumbs.isNotEmpty ||
        (title != null && title!.trim().isNotEmpty) ||
        (subtitle != null && subtitle!.trim().isNotEmpty) ||
        toolbar != null;

    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasHeader)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.paneContent,
                AppSpacing.paneContent,
                AppSpacing.paneContent,
                AppSpacing.xl,
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 920;
                  final header = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (breadcrumbs.isNotEmpty) ...[
                        AppBreadcrumbs(items: breadcrumbs),
                        const SizedBox(height: 10),
                      ],
                      if (eyebrow != null && eyebrow!.trim().isNotEmpty) ...[
                        Text(
                          eyebrow!,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: palette.textMuted,
                                letterSpacing: 0.32,
                              ),
                        ),
                        const SizedBox(height: 6),
                      ],
                      if (title != null && title!.trim().isNotEmpty)
                        Text(
                          title!,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle!,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: palette.textSecondary),
                        ),
                      ],
                    ],
                  );

                  if (compact || toolbar == null) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        header,
                        if (toolbar != null) ...[
                          const SizedBox(height: 8),
                          toolbar!,
                        ],
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: header),
                      const SizedBox(width: 8),
                      Flexible(child: toolbar!),
                    ],
                  );
                },
              ),
            ),
          // The work surface is a pane, not a card: it fills its column edge to
          // edge with no radius and no border. Boundaries between panes are
          // drawn by the overlaid PaneResizeHandle in the shell.
          Expanded(child: AppPaneShell(padding: EdgeInsets.zero, child: child)),
        ],
      ),
    );
  }
}
