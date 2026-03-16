import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../theme/app_palette.dart';
import '../theme/app_theme.dart';
import 'status_badge.dart';

class DetailDrawer extends StatelessWidget {
  const DetailDrawer({super.key, required this.data, required this.onClose});

  final DetailPanelData data;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      width: 360,
      margin: const EdgeInsets.fromLTRB(0, AppSpacing.lg, AppSpacing.lg, AppSpacing.lg),
      decoration: BoxDecoration(
        color: palette.surfacePrimary,
        borderRadius: BorderRadius.circular(AppRadius.dialog),
        border: Border.all(color: palette.strokeSoft),
        boxShadow: [
          BoxShadow(
            color: palette.shadow.withValues(alpha: 0.14),
            blurRadius: 28,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: _DetailPanelContent(data: data, onClose: onClose),
    );
  }
}

class DetailSheet extends StatelessWidget {
  const DetailSheet({super.key, required this.data, required this.onClose});

  final DetailPanelData data;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final mediaQuery = MediaQuery.of(context);

    return Container(
      margin: EdgeInsets.fromLTRB(AppSpacing.sm, mediaQuery.padding.top + AppSpacing.sm, AppSpacing.sm, AppSpacing.sm),
      decoration: BoxDecoration(
        color: palette.surfacePrimary,
        borderRadius: BorderRadius.circular(AppRadius.dialog),
        border: Border.all(color: palette.strokeSoft),
      ),
      constraints: const BoxConstraints(maxWidth: 480),
      child: _DetailPanelContent(data: data, onClose: onClose),
    );
  }
}

class _DetailPanelContent extends StatelessWidget {
  const _DetailPanelContent({required this.data, required this.onClose});

  final DetailPanelData data;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: palette.accentMuted,
                  borderRadius: BorderRadius.circular(AppRadius.button),
                ),
                child: Icon(data.icon, color: palette.accent, size: 22),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(data.title, style: theme.textTheme.headlineSmall),
                    const SizedBox(height: AppSpacing.xxs),
                    if (data.status != null)
                      StatusBadge(status: data.status!, compact: true),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded),
                iconSize: 20,
                style: IconButton.styleFrom(
                  foregroundColor: palette.textSecondary,
                  backgroundColor: palette.surfaceSecondary,
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: palette.strokeSoft),
        if (data.subtitle != null && data.subtitle!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Text(
              data.subtitle!,
              style: theme.textTheme.bodySmall,
            ),
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
            children: [
              if (data.description.isNotEmpty)
                Text(data.description, style: theme.textTheme.bodyMedium),
              if (data.meta.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xxs,
                  children: data.meta.map((item) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.xxs),
                      decoration: BoxDecoration(
                        color: palette.surfaceSecondary,
                        borderRadius: BorderRadius.circular(AppRadius.badge),
                      ),
                      child: Text(
                        item,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: palette.textSecondary,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
              if (data.actions.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: data.actions.map((action) {
                    return TextButton(
                      onPressed: () {},
                      child: Text(action),
                    );
                  }).toList(),
                ),
              ],
              ...data.sections.map((section) {
                return Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.md),
                  child: _DetailSection(section: section),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.section});

  final DetailSection section;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          section.title,
          style: theme.textTheme.labelLarge?.copyWith(
            color: palette.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        ...section.items.map((item) {
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 80,
                  child: Text(
                    item.label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: palette.textMuted,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    item.value,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}
