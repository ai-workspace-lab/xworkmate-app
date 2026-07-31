import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../i18n/app_language.dart';
import '../../models/app_models.dart';
import '../../theme/app_palette.dart';
import '../workbench/workbench_projection.dart';

/// A touch-first view of the desktop workbench. It deliberately keeps the
/// desktop's data model, while reducing its three columns to one clear action
/// stream for a phone-sized screen.
class MobileWorkbenchPage extends StatefulWidget {
  const MobileWorkbenchPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<MobileWorkbenchPage> createState() => _MobileWorkbenchPageState();
}

class _MobileWorkbenchPageState extends State<MobileWorkbenchPage> {
  _MobileWorkbenchTab _tab = _MobileWorkbenchTab.overview;

  Future<void> _openThread(String sessionKey) async {
    await widget.controller.switchSession(sessionKey);
    widget.controller.navigateTo(WorkspaceDestination.assistant);
  }

  void _openQuickRecord() {
    widget.controller.navigateTo(WorkspaceDestination.assistant);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final projection = buildWorkbenchProjection(
          sessions: widget.controller.assistantSessions,
          threadForSession: widget.controller.taskThreadForSessionInternal,
        );
        return SafeArea(
          bottom: false,
          child: Container(
            key: const Key('mobile-workbench-page'),
            color: context.palette.canvas,
            child: CustomScrollView(
              key: const Key('mobile-workbench-scroll-view'),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate.fixed([
                      _MobileWorkbenchHeader(onQuickRecord: _openQuickRecord),
                      const SizedBox(height: 16),
                      _MobileWorkbenchTabs(
                        tab: _tab,
                        onChanged: (tab) => setState(() => _tab = tab),
                      ),
                      const SizedBox(height: 16),
                      _MobileWorkbenchContent(
                        tab: _tab,
                        projection: projection,
                        onOpenThread: _openThread,
                      ),
                    ]),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

enum _MobileWorkbenchTab { overview, todo, projects, inbox }

extension on _MobileWorkbenchTab {
  String get label => switch (this) {
    _MobileWorkbenchTab.overview => appText('总览', 'Overview'),
    _MobileWorkbenchTab.todo => appText('待办', 'To do'),
    _MobileWorkbenchTab.projects => appText('项目', 'Projects'),
    _MobileWorkbenchTab.inbox => appText('收件箱', 'Inbox'),
  };

  String get keyName => switch (this) {
    _MobileWorkbenchTab.overview => 'overview',
    _MobileWorkbenchTab.todo => 'todo',
    _MobileWorkbenchTab.projects => 'projects',
    _MobileWorkbenchTab.inbox => 'inbox',
  };
}

class _MobileWorkbenchHeader extends StatelessWidget {
  const _MobileWorkbenchHeader({required this.onQuickRecord});

  final VoidCallback onQuickRecord;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 17, 12, 17),
      decoration: BoxDecoration(
        color: palette.surfacePrimary,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.strokeSoft),
        boxShadow: [palette.chromeShadowAmbient],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  appText('工作台', 'Workbench'),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  appText('把进展变成下一步行动', 'Turn progress into next actions.'),
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: palette.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            key: const Key('mobile-workbench-quick-record'),
            onPressed: onQuickRecord,
            style: FilledButton.styleFrom(
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.symmetric(horizontal: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Icon(Icons.edit_note_rounded),
          ),
        ],
      ),
    );
  }
}

class _MobileWorkbenchTabs extends StatelessWidget {
  const _MobileWorkbenchTabs({required this.tab, required this.onChanged});

  final _MobileWorkbenchTab tab;
  final ValueChanged<_MobileWorkbenchTab> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _MobileWorkbenchTab.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final candidate = _MobileWorkbenchTab.values[index];
          final selected = candidate == tab;
          return Semantics(
            selected: selected,
            button: true,
            child: InkWell(
              key: Key('mobile-workbench-tab-${candidate.keyName}'),
              onTap: () => onChanged(candidate),
              borderRadius: BorderRadius.circular(14),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(horizontal: 17),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? palette.accent : palette.surfacePrimary,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected ? palette.accent : palette.strokeSoft,
                  ),
                ),
                child: Text(
                  candidate.label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: selected ? Colors.white : palette.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MobileWorkbenchContent extends StatelessWidget {
  const _MobileWorkbenchContent({
    required this.tab,
    required this.projection,
    required this.onOpenThread,
  });

  final _MobileWorkbenchTab tab;
  final WorkbenchProjection projection;
  final ValueChanged<String> onOpenThread;

  @override
  Widget build(BuildContext context) {
    return switch (tab) {
      _MobileWorkbenchTab.overview => _MobileWorkbenchOverview(
        projection: projection,
        onOpenThread: onOpenThread,
      ),
      _MobileWorkbenchTab.todo => _MobileWorkbenchList(
        key: const Key('mobile-workbench-tab-content-todo'),
        title: appText('我的待办', 'My to do'),
        subtitle: appText('按最近进展排序', 'Sorted by latest progress'),
        child: _MobileTaskList(
          items: projection.todos,
          onOpenThread: onOpenThread,
          showProgress: true,
        ),
      ),
      _MobileWorkbenchTab.projects => _MobileWorkbenchList(
        key: const Key('mobile-workbench-tab-content-projects'),
        title: appText('项目 / 专项', 'Projects'),
        subtitle: appText('按工作目录聚合', 'Grouped by workspace'),
        child: _MobileProjectList(
          projects: projection.projects,
          onOpenThread: onOpenThread,
        ),
      ),
      _MobileWorkbenchTab.inbox => _MobileWorkbenchList(
        key: const Key('mobile-workbench-tab-content-inbox'),
        title: appText('工作收件箱', 'Work inbox'),
        subtitle: appText('最近的产物、附件与记录', 'Recent artifacts, files, and notes'),
        child: _MobileInboxList(
          items: projection.inbox,
          onOpenThread: onOpenThread,
        ),
      ),
    };
  }
}

class _MobileWorkbenchOverview extends StatelessWidget {
  const _MobileWorkbenchOverview({
    required this.projection,
    required this.onOpenThread,
  });

  final WorkbenchProjection projection;
  final ValueChanged<String> onOpenThread;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('mobile-workbench-tab-content-overview'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MobileSnapshot(projection: projection),
        const SizedBox(height: 20),
        _MobileSection(
          title: appText('需要你处理', 'Needs your attention'),
          subtitle: appText('优先处理正在推进的任务', 'Focus on what is moving now'),
          child: _MobileTaskList(
            items: projection.todos.take(3).toList(growable: false),
            onOpenThread: onOpenThread,
          ),
        ),
        const SizedBox(height: 20),
        _MobileSection(
          title: appText('正在推进的专项', 'Projects in progress'),
          subtitle: appText('工作目录中的连续进展', 'Ongoing progress in your workspace'),
          child: _MobileProjectList(
            projects: projection.projects.take(3).toList(growable: false),
            onOpenThread: onOpenThread,
          ),
        ),
        if (projection.inbox.isNotEmpty) ...[
          const SizedBox(height: 20),
          _MobileSection(
            title: appText('最近收件', 'Recent inbox'),
            child: _MobileInboxList(
              items: projection.inbox.take(2).toList(growable: false),
              onOpenThread: onOpenThread,
            ),
          ),
        ],
      ],
    );
  }
}

class _MobileSnapshot extends StatelessWidget {
  const _MobileSnapshot({required this.projection});

  final WorkbenchProjection projection;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final totalProgress = projection.items.isEmpty
        ? 0.0
        : projection.items.fold<double>(0, (sum, item) => sum + item.progress) /
              projection.items.length;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.accentMuted,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          _SnapshotMetric(
            label: appText('待处理', 'To do'),
            value: '${projection.todos.length}',
            color: palette.accent,
          ),
          _SnapshotDivider(color: palette.strokeSoft),
          _SnapshotMetric(
            label: appText('项目', 'Projects'),
            value: '${projection.projects.length}',
            color: palette.success,
          ),
          _SnapshotDivider(color: palette.strokeSoft),
          _SnapshotMetric(
            label: appText('进度', 'Progress'),
            value: '${(totalProgress * 100).round()}%',
            color: palette.warning,
          ),
        ],
      ),
    );
  }
}

class _SnapshotMetric extends StatelessWidget {
  const _SnapshotMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: context.palette.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SnapshotDivider extends StatelessWidget {
  const _SnapshotDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 32, color: color);
  }
}

class _MobileWorkbenchList extends StatelessWidget {
  const _MobileWorkbenchList({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _MobileSection(title: title, subtitle: subtitle, child: child);
  }
}

class _MobileSection extends StatelessWidget {
  const _MobileSection({
    required this.title,
    this.subtitle,
    required this.child,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 3),
          Text(
            subtitle!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: context.palette.textSecondary,
            ),
          ),
        ],
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}

class _MobileTaskList extends StatelessWidget {
  const _MobileTaskList({
    required this.items,
    required this.onOpenThread,
    this.showProgress = false,
  });

  final List<WorkbenchItem> items;
  final ValueChanged<String> onOpenThread;
  final bool showProgress;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return _MobileEmptyCard(
        icon: Icons.task_alt_rounded,
        title: appText('目前没有待处理事项', 'Nothing needs attention'),
        subtitle: appText('新的工作会自动出现在这里。', 'New work will appear here.'),
      );
    }
    return _MobileSurface(
      child: Column(
        children: [
          for (var index = 0; index < items.length; index++) ...[
            _MobileTaskTile(
              item: items[index],
              showProgress: showProgress,
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

class _MobileTaskTile extends StatelessWidget {
  const _MobileTaskTile({
    required this.item,
    required this.showProgress,
    required this.onTap,
  });

  final WorkbenchItem item;
  final bool showProgress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final visual = _taskVisual(context, item.state);
    return InkWell(
      key: Key('mobile-workbench-task-${item.sessionKey}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: visual.color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(visual.icon, color: visual.color, size: 20),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: palette.textMuted,
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.projectLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: visual.color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    item.preview.isEmpty ? visual.label : item.preview,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                  if (showProgress) ...[
                    const SizedBox(height: 9),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: item.progress,
                        minHeight: 5,
                        backgroundColor: palette.surfaceTertiary,
                        valueColor: AlwaysStoppedAnimation<Color>(visual.color),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileProjectList extends StatelessWidget {
  const _MobileProjectList({
    required this.projects,
    required this.onOpenThread,
  });

  final List<WorkbenchProject> projects;
  final ValueChanged<String> onOpenThread;

  @override
  Widget build(BuildContext context) {
    if (projects.isEmpty) {
      return _MobileEmptyCard(
        icon: Icons.folder_open_rounded,
        title: appText('暂无项目进展', 'No projects yet'),
        subtitle: appText('绑定工作目录后会自动聚合。', 'Workspace work groups here.'),
      );
    }
    return _MobileSurface(
      child: Column(
        children: [
          for (var index = 0; index < projects.length; index++) ...[
            _MobileProjectTile(
              project: projects[index],
              onTap: () => onOpenThread(projects[index].items.first.sessionKey),
            ),
            if (index < projects.length - 1)
              Divider(height: 1, color: context.palette.strokeSoft),
          ],
        ],
      ),
    );
  }
}

class _MobileProjectTile extends StatelessWidget {
  const _MobileProjectTile({required this.project, required this.onTap});

  final WorkbenchProject project;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final progress = project.progress.clamp(0.0, 1.0);
    return InkWell(
      key: Key('mobile-workbench-project-${project.label}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: palette.accentMuted,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.folder_special_rounded,
                    color: palette.accent,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        project.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        appText(
                          '${project.items.length} 个工作项 · ${project.artifactCount} 个产物',
                          '${project.items.length} items · ${project.artifactCount} artifacts',
                        ),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: palette.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${(progress * 100).round()}%',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: palette.accent,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 5,
                backgroundColor: palette.surfaceTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileInboxList extends StatelessWidget {
  const _MobileInboxList({required this.items, required this.onOpenThread});

  final List<WorkbenchInboxItem> items;
  final ValueChanged<String> onOpenThread;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return _MobileEmptyCard(
        icon: Icons.inbox_rounded,
        title: appText('收件箱是空的', 'Your inbox is empty'),
        subtitle: appText('产物和附件会集中显示在这里。', 'Artifacts and files appear here.'),
      );
    }
    return _MobileSurface(
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

class _MobileSurface extends StatelessWidget {
  const _MobileSurface({required this.child});

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

class _MobileEmptyCard extends StatelessWidget {
  const _MobileEmptyCard({
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
    return _MobileSurface(
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

({IconData icon, String label, Color color}) _taskVisual(
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
