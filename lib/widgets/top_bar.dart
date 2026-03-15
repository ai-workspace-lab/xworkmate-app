import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import '../theme/app_theme.dart';

class TopBar extends StatelessWidget {
  const TopBar({
    super.key,
    required this.title,
    required this.subtitle,
    this.breadcrumbs = const <AppBreadcrumbItem>[],
    this.trailing,
  });

  final String title;
  final String subtitle;
  final List<AppBreadcrumbItem> breadcrumbs;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (breadcrumbs.isNotEmpty) ...[
                AppBreadcrumbs(items: breadcrumbs),
                const SizedBox(height: AppSpacing.sm),
              ],
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: AppSpacing.xs),
              Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
              if (trailing != null) ...[
                const SizedBox(height: AppSpacing.md),
                trailing!,
              ],
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (breadcrumbs.isNotEmpty) ...[
                    AppBreadcrumbs(items: breadcrumbs),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  Text(title, style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: AppSpacing.xs),
                  Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: AppSpacing.lg),
              Flexible(child: trailing!),
            ],
          ],
        );
      },
    );
  }
}

class AppBreadcrumbItem {
  const AppBreadcrumbItem({
    required this.label,
    this.onTap,
    this.icon,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
}

class AppBreadcrumbs extends StatelessWidget {
  const AppBreadcrumbs({super.key, required this.items});

  final List<AppBreadcrumbItem> items;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var index = 0; index < items.length; index++) ...[
          if (index > 0)
            Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: palette.textMuted,
            ),
          _BreadcrumbChip(
            key: ValueKey<String>('workspace-breadcrumb-$index'),
            item: items[index],
            textStyle: theme.textTheme.labelLarge?.copyWith(
              color: items[index].onTap != null
                  ? palette.textPrimary
                  : palette.textSecondary,
              fontWeight: index == items.length - 1
                  ? FontWeight.w700
                  : FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

class _BreadcrumbChip extends StatelessWidget {
  const _BreadcrumbChip({
    super.key,
    required this.item,
    required this.textStyle,
  });

  final AppBreadcrumbItem item;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (item.icon != null) ...[
          Icon(item.icon, size: 15, color: textStyle?.color),
          const SizedBox(width: 6),
        ],
        Text(item.label, style: textStyle),
      ],
    );

    final body = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: item.onTap != null
            ? palette.surfaceSecondary
            : palette.surfacePrimary,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.strokeSoft),
      ),
      child: content,
    );

    if (item.onTap == null) {
      return body;
    }

    return InkWell(
      onTap: item.onTap,
      borderRadius: BorderRadius.circular(999),
      child: body,
    );
  }
}
