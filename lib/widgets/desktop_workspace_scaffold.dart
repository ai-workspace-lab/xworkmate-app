import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

class DesktopWorkspaceScaffold extends StatelessWidget {
  const DesktopWorkspaceScaffold({
    super.key,
    required this.child,
    this.eyebrow,
    this.title,
    this.subtitle,
    this.toolbar,
    this.padding = const EdgeInsets.fromLTRB(16, 16, 16, 0),
  });

  final Widget child;
  final String? eyebrow;
  final String? title;
  final String? subtitle;
  final Widget? toolbar;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final hasHeader =
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
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 920;
                  final header = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (eyebrow != null && eyebrow!.trim().isNotEmpty) ...[
                        Text(
                          eyebrow!,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: palette.textMuted,
                                letterSpacing: 0.2,
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
                          const SizedBox(height: 12),
                          toolbar!,
                        ],
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: header),
                      const SizedBox(width: 20),
                      Flexible(child: toolbar!),
                    ],
                  );
                },
              ),
            ),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: palette.surfacePrimary,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: palette.shadow.withValues(alpha: 0.06),
                    blurRadius: 16,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
