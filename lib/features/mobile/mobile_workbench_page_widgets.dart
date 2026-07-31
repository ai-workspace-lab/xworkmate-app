import 'package:flutter/material.dart';

import '../../i18n/app_language.dart';
import '../../theme/app_palette.dart';
import '../workbench/workbench_projection.dart';

class MobileWorkbenchInboxList extends StatelessWidget {
  const MobileWorkbenchInboxList({
    super.key,
    required this.items,
    required this.onOpenThread,
  });

  final List<WorkbenchInboxItem> items;
  final ValueChanged<String> onOpenThread;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return MobileWorkbenchEmptyCard(
        icon: Icons.inbox_rounded,
        title: appText('收件箱是空的', 'Your inbox is empty'),
        subtitle: appText('产物和附件会集中显示在这里。', 'Artifacts and files appear here.'),
      );
    }
    return MobileWorkbenchSurface(
      child: Column(
        children: [
          for (var index = 0; index < items.length; index++) ...[
            _MobileInboxTile(
              item: items[index],
              onTap: () => onOpenThread(items[index].sessionKey),
            ),
            if (index < items.length - 1)
              Divider(height: 1, color: context.palette.strokeSoft),
          ],
        ],
      ),
    );
  }
}

class _MobileInboxTile extends StatelessWidget {
  const _MobileInboxTile({required this.item, required this.onTap});

  final WorkbenchInboxItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final visual = switch (item.kind) {
      WorkbenchInboxKind.artifact => (
        Icons.description_rounded,
        palette.accent,
      ),
      WorkbenchInboxKind.attachment => (
        Icons.attach_file_rounded,
        palette.success,
      ),
      WorkbenchInboxKind.note => (Icons.sticky_note_2_rounded, palette.warning),
    };
    return InkWell(
      key: Key('mobile-workbench-inbox-${item.sessionKey}-${item.title}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: visual.$2.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(visual.$1, color: visual.$2, size: 20),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.sourceTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: palette.textMuted),
          ],
        ),
      ),
    );
  }
}

class MobileWorkbenchSurface extends StatelessWidget {
  const MobileWorkbenchSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: palette.surfacePrimary,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.strokeSoft),
        boxShadow: [palette.chromeShadowAmbient],
      ),
      child: child,
    );
  }
}

class MobileWorkbenchEmptyCard extends StatelessWidget {
  const MobileWorkbenchEmptyCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return MobileWorkbenchSurface(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(icon, size: 28, color: palette.accent),
            const SizedBox(height: 9),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: palette.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

({IconData icon, String label, Color color}) mobileWorkbenchTaskVisual(
  BuildContext context,
  WorkbenchItemState state,
) {
  final palette = context.palette;
  return switch (state) {
    WorkbenchItemState.blocked => (
      icon: Icons.error_outline_rounded,
      label: appText('需要处理', 'Needs attention'),
      color: palette.danger,
    ),
    WorkbenchItemState.syncing => (
      icon: Icons.sync_rounded,
      label: appText('正在同步', 'Syncing'),
      color: palette.warning,
    ),
    WorkbenchItemState.running => (
      icon: Icons.play_circle_outline_rounded,
      label: appText('进行中', 'In progress'),
      color: palette.accent,
    ),
    WorkbenchItemState.ready => (
      icon: Icons.radio_button_checked_rounded,
      label: appText('待处理', 'To do'),
      color: palette.accent,
    ),
    WorkbenchItemState.completed => (
      icon: Icons.check_circle_outline_rounded,
      label: appText('已完成', 'Done'),
      color: palette.success,
    ),
  };
}
