import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../i18n/app_language.dart';
import '../models/app_models.dart';
import '../theme/app_palette.dart';
import 'surface_card.dart';

class AssistantFocusPanel extends StatelessWidget {
  const AssistantFocusPanel({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    final favorites = controller.assistantNavigationDestinations;
    final available = kAssistantNavigationDestinationCandidates
        .where((item) => !favorites.contains(item))
        .toList(growable: false);

    return SurfaceCard(
      borderRadius: 16,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  appText('关注入口', 'Focused navigation'),
                  key: const Key('assistant-focus-panel-title'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  appText(
                    '把常看的功能菜单放到这里。左侧菜单点亮星标，也会加入这个关注面板。',
                    'Pin the destinations you care about here. Starred menu items also appear in this focused panel.',
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: palette.textSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: palette.strokeSoft),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
              children: [
                Text(
                  appText('已关注', 'Following'),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: palette.textMuted,
                  ),
                ),
                const SizedBox(height: 8),
                if (favorites.isEmpty)
                  _AssistantFocusEmptyState(
                    message: appText(
                      '还没有关注入口。给左侧菜单点星标，或从下面添加。',
                      'No focused entries yet. Star a menu item on the left or add one below.',
                    ),
                  )
                else
                  ...favorites.map(
                    (destination) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _AssistantFocusTile(
                        destination: destination,
                        selected: controller.destination == destination,
                        onOpen: () => controller.navigateTo(destination),
                        onToggleFavorite: () async {
                          await controller.toggleAssistantNavigationDestination(
                            destination,
                          );
                        },
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                Text(
                  appText('添加入口', 'Add destinations'),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: palette.textMuted,
                  ),
                ),
                const SizedBox(height: 8),
                if (available.isEmpty)
                  _AssistantFocusEmptyState(
                    message: appText(
                      '候选菜单都已经加入关注入口了。',
                      'All available destinations are already pinned.',
                    ),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: available
                        .map(
                          (destination) => ActionChip(
                            key: ValueKey<String>(
                              'assistant-focus-add-${destination.name}',
                            ),
                            avatar: Icon(destination.icon, size: 16),
                            label: Text(destination.label),
                            onPressed: () async {
                              await controller
                                  .toggleAssistantNavigationDestination(
                                    destination,
                                  );
                            },
                          ),
                        )
                        .toList(growable: false),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AssistantFocusTile extends StatelessWidget {
  const _AssistantFocusTile({
    required this.destination,
    required this.selected,
    required this.onOpen,
    required this.onToggleFavorite,
  });

  final WorkspaceDestination destination;
  final bool selected;
  final VoidCallback onOpen;
  final Future<void> Function() onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;

    return Material(
      color: selected
          ? palette.accentMuted.withValues(alpha: 0.5)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        key: ValueKey<String>('assistant-focus-item-${destination.name}'),
        borderRadius: BorderRadius.circular(14),
        onTap: onOpen,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? palette.accent : palette.strokeSoft,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: palette.surfaceSecondary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  destination.icon,
                  size: 18,
                  color: selected ? palette.accent : palette.textSecondary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      destination.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      destination.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: palette.textSecondary,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: ValueKey<String>(
                  'assistant-focus-remove-${destination.name}',
                ),
                tooltip: appText('取消关注', 'Remove from focused panel'),
                onPressed: () async {
                  await onToggleFavorite();
                },
                icon: Icon(Icons.star_rounded, color: palette.accent),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AssistantFocusEmptyState extends StatelessWidget {
  const _AssistantFocusEmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.surfaceSecondary,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.strokeSoft),
      ),
      child: Text(
        message,
        style: theme.textTheme.bodySmall?.copyWith(
          color: palette.textSecondary,
          height: 1.35,
        ),
      ),
    );
  }
}
