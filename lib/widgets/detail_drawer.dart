import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../theme/app_palette.dart';
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
      margin: const EdgeInsets.fromLTRB(0, 24, 24, 24),
      decoration: BoxDecoration(
        color: palette.surfacePrimary,
        borderRadius: BorderRadius.circular(28),
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
      margin: EdgeInsets.fromLTRB(12, mediaQuery.padding.top + 12, 12, 12),
      decoration: BoxDecoration(
        color: palette.surfacePrimary,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: palette.strokeSoft),
        boxShadow: [
          BoxShadow(
            color: palette.shadow.withValues(alpha: 0.16),
            blurRadius: 28,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: _DetailPanelContent(data: data, onClose: onClose),
      ),
    );
  }
}

class _DetailPanelContent extends StatelessWidget {
  const _DetailPanelContent({required this.data, required this.onClose});

  final DetailPanelData data;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 16, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: context.palette.accentMuted,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(data.icon, color: context.palette.accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.subtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      data.title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 10),
                    StatusBadge(status: data.status, compact: true),
                  ],
                ),
              ),
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Text(
            data.description,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: data.meta
                .map(
                  (item) => Chip(
                    label: Text(item),
                    visualDensity: VisualDensity.compact,
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 18),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
            children: [
              ...data.sections.map(
                (section) => Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: _DetailSectionCard(section: section),
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: data.actions
                    .map(
                      (action) =>
                          OutlinedButton(onPressed: () {}, child: Text(action)),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DetailSectionCard extends StatelessWidget {
  const _DetailSectionCard({required this.section});

  final DetailSection section;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surfaceSecondary,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.strokeSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(section.title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          ...section.items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      item.label,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Flexible(
                    child: Text(
                      item.value,
                      textAlign: TextAlign.right,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
