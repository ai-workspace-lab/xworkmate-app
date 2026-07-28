import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../i18n/app_language.dart';
import '../../models/app_models.dart';
import '../../theme/app_palette.dart';
import 'workbench_projection.dart';

class WorkbenchPage extends StatefulWidget {
  const WorkbenchPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<WorkbenchPage> createState() => _WorkbenchPageState();
}

class _WorkbenchPageState extends State<WorkbenchPage> {
  int _tabIndex = 0;

  Future<void> _openThread(String sessionKey) async {
    await widget.controller.switchSession(sessionKey);
    widget.controller.navigateTo(WorkspaceDestination.assistant);
  }

  void _openAssistant() {
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
        return LayoutBuilder(
          builder: (context, constraints) {
            final showRightRail = constraints.maxWidth >= 1080;
            return Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _WorkbenchMain(
                      tabIndex: _tabIndex,
                      projection: projection,
                      showInlineInsights: !showRightRail,
                      onTabChanged: (index) {
                        setState(() => _tabIndex = index);
                      },
                      onQuickRecord: _openAssistant,
                      onOpenThread: _openThread,
                      onSuggestionAction: _openAssistant,
                    ),
                  ),
                  if (showRightRail) ...[
                    const SizedBox(width: 12),
                    SizedBox(
                      width: constraints.maxWidth >= 1200 ? 380 : 340,
                      child: _WorkbenchRightRail(
                        projection: projection,
                        onSuggestionAction: _openAssistant,
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _WorkbenchMain extends StatelessWidget {
  const _WorkbenchMain({
    required this.tabIndex,
    required this.projection,
    required this.showInlineInsights,
    required this.onTabChanged,
    required this.onQuickRecord,
    required this.onOpenThread,
    required this.onSuggestionAction,
  });

  final int tabIndex;
  final WorkbenchProjection projection;
  final bool showInlineInsights;
  final ValueChanged<int> onTabChanged;
  final VoidCallback onQuickRecord;
  final ValueChanged<String> onOpenThread;
  final VoidCallback onSuggestionAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _WorkbenchHero(onQuickRecord: onQuickRecord),
        const SizedBox(height: 12),
        _WorkbenchTabs(index: tabIndex, onChanged: onTabChanged),
        const SizedBox(height: 12),
        Expanded(
          child: switch (tabIndex.clamp(0, 3)) {
            0 => _WorkbenchOverview(
              projection: projection,
              showInlineInsights: showInlineInsights,
              onOpenThread: onOpenThread,
              onShowProjects: () => onTabChanged(2),
              onSuggestionAction: onSuggestionAction,
            ),
            1 => _WorkbenchTodoPage(
              items: projection.todos,
              onOpenThread: onOpenThread,
            ),
            2 => _WorkbenchProjectsPage(
              projects: projection.projects,
              onOpenThread: onOpenThread,
            ),
            _ => _WorkbenchInboxPage(
              items: projection.inbox,
              onOpenThread: onOpenThread,
            ),
          },
        ),
      ],
    );
  }
}

class _WorkbenchHero extends StatelessWidget {
  const _WorkbenchHero({required this.onQuickRecord});

  final VoidCallback onQuickRecord;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 104),
      padding: const EdgeInsets.fromLTRB(22, 18, 20, 18),
      decoration: BoxDecoration(
        color: palette.surfacePrimary,
        borderRadius: BorderRadius.circular(18),
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
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  appText(
                    '把零碎进展沉淀为清晰工作',
                    'Turn fragmented progress into clear work.',
                  ),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            key: const Key('workbench-quick-record-button'),
            onPressed: onQuickRecord,
            icon: const Icon(Icons.edit_note_rounded, size: 20),
            label: Text(appText('快速记录', 'Quick record')),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkbenchTabs extends StatelessWidget {
  const _WorkbenchTabs({required this.index, required this.onChanged});

  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final tabs = <String>[
      appText('总览', 'Overview'),
      appText('我的待办', 'My todo'),
      appText('项目 / 专项', 'Projects / topics'),
      appText('收件箱', 'Inbox'),
    ];
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.strokeSoft)),
      ),
      child: Row(
        children: List.generate(tabs.length, (tabIndex) {
          final selected = index == tabIndex;
          return InkWell(
            key: Key('workbench-tab-$tabIndex'),
            onTap: () => onChanged(tabIndex),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            child: Container(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 11),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: selected ? palette.accent : Colors.transparent,
                    width: 2.5,
                  ),
                ),
              ),
              child: Text(
                tabs[tabIndex],
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: selected ? palette.accent : palette.textSecondary,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _WorkbenchOverview extends StatelessWidget {
  const _WorkbenchOverview({
    required this.projection,
    required this.showInlineInsights,
    required this.onOpenThread,
    required this.onShowProjects,
    required this.onSuggestionAction,
  });

  final WorkbenchProjection projection;
  final bool showInlineInsights;
  final ValueChanged<String> onOpenThread;
  final VoidCallback onShowProjects;
  final VoidCallback onSuggestionAction;

  @override
  Widget build(BuildContext context) {
    final attentionItems = projection.todos.take(4).toList(growable: false);
    final projects = projection.projects.take(4).toList(growable: false);
    return ListView(
      key: const Key('workbench-overview-list'),
      children: [
        _WorkbenchSectionCard(
          title: appText('需要你处理', 'Needs your attention'),
          child: _TaskTable(items: attentionItems, onOpenThread: onOpenThread),
        ),
        const SizedBox(height: 12),
        _WorkbenchSectionCard(
          title: appText('正在推进的专项', 'Projects in progress'),
          footer: projection.projects.length > projects.length
              ? TextButton.icon(
                  onPressed: onShowProjects,
                  iconAlignment: IconAlignment.end,
                  icon: const Icon(Icons.chevron_right_rounded, size: 18),
                  label: Text(appText('查看全部专项', 'View all projects')),
                )
              : null,
          child: _ProjectTable(projects: projects, onOpenThread: onOpenThread),
        ),
        if (showInlineInsights) ...[
          const SizedBox(height: 12),
          _WorkbenchRightRail(
            projection: projection,
            onSuggestionAction: onSuggestionAction,
          ),
        ],
      ],
    );
  }
}

class _WorkbenchTodoPage extends StatelessWidget {
  const _WorkbenchTodoPage({required this.items, required this.onOpenThread});

  final List<WorkbenchItem> items;
  final ValueChanged<String> onOpenThread;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('workbench-todo-page'),
      children: [
        _PageIntro(
          title: appText('我的待办', 'My todo'),
          subtitle: appText(
            '按运行状态和最近进展汇总 TaskThread',
            'TaskThreads grouped by runtime state and recent progress.',
          ),
          countLabel: appText('${items.length} 项待处理', '${items.length} items'),
        ),
        const SizedBox(height: 12),
        _WorkbenchSectionCard(
          title: appText('全部待办', 'All todo items'),
          child: _TaskTable(
            items: items,
            onOpenThread: onOpenThread,
            showProgress: true,
          ),
        ),
      ],
    );
  }
}

class _WorkbenchProjectsPage extends StatelessWidget {
  const _WorkbenchProjectsPage({
    required this.projects,
    required this.onOpenThread,
  });

  final List<WorkbenchProject> projects;
  final ValueChanged<String> onOpenThread;

  @override
  Widget build(BuildContext context) {
    final workItemCount = projects.fold<int>(
      0,
      (sum, project) => sum + project.items.length,
    );
    return ListView(
      key: const Key('workbench-projects-page'),
      children: [
        _PageIntro(
          title: appText('项目 / 专项', 'Projects / topics'),
          subtitle: appText(
            '按真实工作目录聚合 TaskThread 与 Artifact',
            'TaskThreads and artifacts grouped by real workspace.',
          ),
          countLabel: appText(
            '${projects.length} 个专项 · $workItemCount 个工作项',
            '${projects.length} projects · $workItemCount work items',
          ),
        ),
        const SizedBox(height: 12),
        _WorkbenchSectionCard(
          title: appText('全部专项', 'All projects'),
          child: _ProjectTable(
            projects: projects,
            onOpenThread: onOpenThread,
            expanded: true,
          ),
        ),
      ],
    );
  }
}

class _WorkbenchInboxPage extends StatelessWidget {
  const _WorkbenchInboxPage({required this.items, required this.onOpenThread});

  final List<WorkbenchInboxItem> items;
  final ValueChanged<String> onOpenThread;

  @override
  Widget build(BuildContext context) {
    final artifactCount = items
        .where((item) => item.kind == WorkbenchInboxKind.artifact)
        .length;
    return ListView(
      key: const Key('workbench-inbox-page'),
      children: [
        _PageIntro(
          title: appText('工作收件箱', 'Work inbox'),
          subtitle: appText(
            '集中查看 Artifact、输入附件和待整理工作记录',
            'Artifacts, input attachments, and unorganized work notes.',
          ),
          countLabel: appText(
            '${items.length} 条记录 · $artifactCount 个产物',
            '${items.length} records · $artifactCount artifacts',
          ),
        ),
        const SizedBox(height: 12),
        _WorkbenchSectionCard(
          title: appText('最近收件', 'Recent inbox'),
          child: _InboxTable(items: items, onOpenThread: onOpenThread),
        ),
      ],
    );
  }
}

class _PageIntro extends StatelessWidget {
  const _PageIntro({
    required this.title,
    required this.subtitle,
    required this.countLabel,
  });

  final String title;
  final String subtitle;
  final String countLabel;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: palette.surfacePrimary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.strokeSoft),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          _SoftBadge(label: countLabel, color: palette.accent),
        ],
      ),
    );
  }
}

class _WorkbenchSectionCard extends StatelessWidget {
  const _WorkbenchSectionCard({
    required this.title,
    required this.child,
    this.footer,
  });

  final String title;
  final Widget child;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: palette.surfacePrimary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.strokeSoft),
        boxShadow: [palette.chromeShadowAmbient],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Divider(height: 1, color: palette.strokeSoft),
          child,
          if (footer != null) ...[
            Divider(height: 1, color: palette.strokeSoft),
            Align(alignment: Alignment.center, child: footer),
          ],
        ],
      ),
    );
  }
}

class _TaskTable extends StatelessWidget {
  const _TaskTable({
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
      return _EmptyState(
        icon: Icons.task_alt_rounded,
        title: appText('当前没有待处理事项', 'No items need attention'),
        subtitle: appText(
          '新的 TaskThread 会自动出现在这里。',
          'New TaskThreads will appear here automatically.',
        ),
      );
    }
    return Column(
      children: [
        for (var index = 0; index < items.length; index++) ...[
          _TaskRow(
            item: items[index],
            showProgress: showProgress,
            onTap: () => onOpenThread(items[index].sessionKey),
          ),
          if (index != items.length - 1)
            Divider(height: 1, color: context.palette.strokeSoft),
        ],
      ],
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({
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
    final stateVisual = _stateVisual(context, item.state);
    if (MediaQuery.sizeOf(context).width < 700) {
      return _CompactTaskRow(
        item: item,
        showProgress: showProgress,
        onTap: onTap,
      );
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          children: [
            SizedBox(
              width: 96,
              child: Row(
                children: [
                  Icon(stateVisual.icon, size: 18, color: stateVisual.color),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      stateVisual.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: stateVisual.color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: palette.surfaceSecondary,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: palette.strokeSoft),
              ),
              child: Icon(_taskIcon(item), color: palette.accent, size: 19),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _SoftBadge(
                        label: item.projectLabel,
                        color: palette.textSecondary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (showProgress) ...[
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: LinearProgressIndicator(
                              value: item.progress,
                              minHeight: 5,
                              backgroundColor: palette.surfaceTertiary,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                stateVisual.color,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${(item.progress * 100).round()}%',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: palette.textSecondary),
                        ),
                      ],
                    ),
                  ] else
                    Text(
                      _taskMeta(item),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 10,
                ),
                visualDensity: VisualDensity.compact,
              ),
              child: Text(_taskAction(item.state)),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactTaskRow extends StatelessWidget {
  const _CompactTaskRow({
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
    final stateVisual = _stateVisual(context, item.state);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(stateVisual.icon, size: 18, color: stateVisual.color),
                const SizedBox(width: 6),
                Text(
                  stateVisual.label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: stateVisual.color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                _SoftBadge(
                  label: item.projectLabel,
                  color: palette.textSecondary,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 5),
            if (showProgress)
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: item.progress,
                  minHeight: 5,
                  backgroundColor: palette.surfaceTertiary,
                  valueColor: AlwaysStoppedAnimation<Color>(stateVisual.color),
                ),
              )
            else
              Text(
                _taskMeta(item),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
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

class _ProjectTable extends StatelessWidget {
  const _ProjectTable({
    required this.projects,
    required this.onOpenThread,
    this.expanded = false,
  });

  final List<WorkbenchProject> projects;
  final ValueChanged<String> onOpenThread;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    if (projects.isEmpty) {
      return _EmptyState(
        icon: Icons.folder_open_rounded,
        title: appText('暂无正在推进的专项', 'No active projects'),
        subtitle: appText(
          '绑定工作目录后，TaskThread 会自动聚合为专项。',
          'TaskThreads group into projects by workspace.',
        ),
      );
    }
    return Column(
      children: [
        for (var index = 0; index < projects.length; index++) ...[
          _ProjectRow(
            project: projects[index],
            expanded: expanded,
            onTap: projects[index].items.isEmpty
                ? null
                : () => onOpenThread(projects[index].items.first.sessionKey),
          ),
          if (index != projects.length - 1)
            Divider(height: 1, color: context.palette.strokeSoft),
        ],
      ],
    );
  }
}

class _ProjectRow extends StatelessWidget {
  const _ProjectRow({
    required this.project,
    required this.expanded,
    required this.onTap,
  });

  final WorkbenchProject project;
  final bool expanded;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final progress = project.progress.clamp(0.0, 1.0);
    if (MediaQuery.sizeOf(context).width < 700) {
      return _CompactProjectRow(
        project: project,
        progress: progress,
        onTap: onTap,
      );
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: palette.accentMuted,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.folder_special_rounded,
                color: palette.accent,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: expanded ? 220 : 190,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    project.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    appText(
                      '${project.items.length} 个 TaskThread · ${project.artifactCount} 个 Artifact',
                      '${project.items.length} TaskThreads · ${project.artifactCount} artifacts',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: _ProjectProgress(progress: progress, compact: !expanded),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 52,
              child: Text(
                '${(progress * 100).round()}%',
                textAlign: TextAlign.right,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: palette.accent,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: palette.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _CompactProjectRow extends StatelessWidget {
  const _CompactProjectRow({
    required this.project,
    required this.progress,
    required this.onTap,
  });

  final WorkbenchProject project;
  final double progress;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.folder_special_rounded,
                  color: palette.accent,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    project.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '${(progress * 100).round()}%',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: palette.accent,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              appText(
                '${project.items.length} 个 TaskThread · ${project.artifactCount} 个 Artifact',
                '${project.items.length} TaskThreads · ${project.artifactCount} artifacts',
              ),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: palette.textSecondary),
            ),
            const SizedBox(height: 10),
            _ProjectProgress(progress: progress, compact: true),
          ],
        ),
      ),
    );
  }
}

class _ProjectProgress extends StatelessWidget {
  const _ProjectProgress({required this.progress, required this.compact});

  final double progress;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final stages = <String>[
      appText('需求确认', 'Scope'),
      appText('方案设计', 'Design'),
      appText('开发中', 'Build'),
      appText('测试', 'Test'),
      appText('上线', 'Ship'),
    ];
    final activeStage = (progress * (stages.length - 1)).round().clamp(
      0,
      stages.length - 1,
    );
    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 3,
                  backgroundColor: palette.surfaceTertiary,
                  valueColor: AlwaysStoppedAnimation<Color>(palette.accent),
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(stages.length, (index) {
                final reached = index <= activeStage;
                return Icon(
                  reached
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 13,
                  color: reached ? palette.accent : palette.surfaceTertiary,
                );
              }),
            ),
          ],
        ),
        const SizedBox(height: 5),
        if (!compact || MediaQuery.sizeOf(context).width >= 1260)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: stages
                .map(
                  (stage) => Text(
                    stage,
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: palette.textMuted),
                  ),
                )
                .toList(growable: false),
          ),
      ],
    );
  }
}

class _InboxTable extends StatelessWidget {
  const _InboxTable({required this.items, required this.onOpenThread});

  final List<WorkbenchInboxItem> items;
  final ValueChanged<String> onOpenThread;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return _EmptyState(
        icon: Icons.inbox_rounded,
        title: appText('收件箱是空的', 'Your inbox is empty'),
        subtitle: appText(
          'TaskThread 的 Artifact、输入附件和工作记录会汇总到这里。',
          'Artifacts, attachments, and work notes will appear here.',
        ),
      );
    }
    return Column(
      children: [
        for (var index = 0; index < items.length; index++) ...[
          _InboxRow(
            item: items[index],
            onTap: () => onOpenThread(items[index].sessionKey),
          ),
          if (index != items.length - 1)
            Divider(height: 1, color: context.palette.strokeSoft),
        ],
      ],
    );
  }
}

class _InboxRow extends StatelessWidget {
  const _InboxRow({required this.item, required this.onTap});

  final WorkbenchInboxItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final visual = switch (item.kind) {
      WorkbenchInboxKind.artifact => (
        Icons.description_rounded,
        appText('产物', 'Artifact'),
        palette.accent,
      ),
      WorkbenchInboxKind.attachment => (
        Icons.attach_file_rounded,
        appText('附件', 'Attachment'),
        palette.success,
      ),
      WorkbenchInboxKind.note => (
        Icons.sticky_note_2_rounded,
        appText('记录', 'Note'),
        palette.warning,
      ),
    };
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: visual.$3.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(visual.$1, color: visual.$3, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${item.sourceTitle} · ${item.subtitle} · ${_relativeTime(item.updatedAtMs)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _SoftBadge(label: visual.$2, color: visual.$3),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded, color: palette.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _WorkbenchRightRail extends StatelessWidget {
  const _WorkbenchRightRail({
    required this.projection,
    required this.onSuggestionAction,
  });

  final WorkbenchProjection projection;
  final VoidCallback onSuggestionAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _InsightPanel(projection: projection),
        const SizedBox(height: 12),
        _WeeklyRhythmCard(projection: projection),
        const SizedBox(height: 12),
        _SuggestionPanel(projection: projection, onAction: onSuggestionAction),
      ],
    );
  }
}

class _InsightPanel extends StatelessWidget {
  const _InsightPanel({required this.projection});

  final WorkbenchProjection projection;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: palette.surfacePrimary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.strokeSoft),
        boxShadow: [palette.chromeShadowAmbient],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            appText('工作洞察', 'Work insights'),
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Text(
            appText('工作负载趋势（近 7 天）', 'Workload trend (last 7 days)'),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: palette.textSecondary),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 235,
            child: CustomPaint(
              painter: _WorkloadChartPainter(
                series: projection.workloadSeries,
                accent: palette.accent,
                grid: palette.strokeSoft,
                labelColor: palette.textMuted,
                localeIsChinese: activeAppLanguage == AppLanguage.zh,
              ),
              size: Size.infinite,
            ),
          ),
        ],
      ),
    );
  }
}

class _WeeklyRhythmCard extends StatelessWidget {
  const _WeeklyRhythmCard({required this.projection});

  final WorkbenchProjection projection;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final planned = math.max(projection.todos.length, 1);
    final progressed = projection.todos
        .where((item) => item.progress >= 0.4)
        .length;
    final progress = projection.items.isEmpty
        ? 0.0
        : projection.items.fold<double>(0, (sum, item) => sum + item.progress) /
              projection.items.length;
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final sunday = monday.add(const Duration(days: 6));
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: palette.surfacePrimary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.strokeSoft),
        boxShadow: [palette.chromeShadowAmbient],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  appText('本周节奏', 'Weekly rhythm'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '${monday.month}/${monday.day} – ${sunday.month}/${sunday.day}',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: palette.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 17),
          _RhythmMetric(
            label: appText('计划工作项', 'Planned items'),
            value: '$planned',
            progress: 1,
            color: palette.accent,
          ),
          const SizedBox(height: 16),
          _RhythmMetric(
            label: appText('已有进展', 'Progressed'),
            value: '$progressed',
            progress: (progressed / planned).clamp(0.0, 1.0),
            color: palette.success,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  appText('整体进度', 'Overall progress'),
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: palette.textSecondary),
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
        ],
      ),
    );
  }
}

class _RhythmMetric extends StatelessWidget {
  const _RhythmMetric({
    required this.label,
    required this.value,
    required this.progress,
    required this.color,
  });

  final String label;
  final String value;
  final double progress;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: palette.textSecondary),
              ),
            ),
            Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: palette.surfaceTertiary,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

class _SuggestionPanel extends StatelessWidget {
  const _SuggestionPanel({required this.projection, required this.onAction});

  final WorkbenchProjection projection;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final latestInbox = projection.inbox.isEmpty
        ? null
        : projection.inbox.first;
    final firstProject = projection.projects.isEmpty
        ? null
        : projection.projects.first;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surfacePrimary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.strokeSoft),
        boxShadow: [palette.chromeShadowAmbient],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.lightbulb_outline_rounded,
                color: palette.warning,
                size: 20,
              ),
              const SizedBox(width: 7),
              Text(
                appText('AI 整理建议', 'AI organization suggestions'),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _SuggestionTile(
            icon: Icons.description_outlined,
            title: latestInbox == null
                ? appText('建议归类为待办', 'Organize as todo')
                : appText('建议整理最近收件', 'Organize latest inbox item'),
            subtitle: latestInbox == null
                ? appText(
                    '把最近的碎片输入汇总成下一步动作。',
                    'Turn recent fragments into next actions.',
                  )
                : latestInbox.title,
            actionLabel: appText('确认', 'Confirm'),
            color: palette.accent,
            onAction: onAction,
          ),
          const SizedBox(height: 10),
          _SuggestionTile(
            icon: Icons.task_alt_rounded,
            title: firstProject == null
                ? appText('建议创建专项', 'Create a project')
                : appText('建议补充下一步任务', 'Add a next action'),
            subtitle: firstProject == null
                ? appText(
                    '把连续工作串成一个专项卡片。',
                    'Group ongoing work into a project card.',
                  )
                : firstProject.label,
            actionLabel: appText('创建', 'Create'),
            color: palette.success,
            onAction: onAction,
          ),
          const SizedBox(height: 4),
          Text(
            appText(
              '基于当前 TaskThread 与 Artifact 智能建议',
              'Suggestions based on current TaskThreads and artifacts.',
            ),
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: palette.textMuted),
          ),
        ],
      ),
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  const _SuggestionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.color,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final Color color;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 10, 8, 10),
      decoration: BoxDecoration(
        color: palette.surfaceSecondary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.strokeSoft),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          TextButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }
}

class _SoftBadge extends StatelessWidget {
  const _SoftBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 150),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Center(
        child: Column(
          children: [
            Icon(icon, color: palette.textMuted, size: 28),
            const SizedBox(height: 8),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
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

class _WorkloadChartPainter extends CustomPainter {
  _WorkloadChartPainter({
    required this.series,
    required this.accent,
    required this.grid,
    required this.labelColor,
    required this.localeIsChinese,
  });

  final List<double> series;
  final Color accent;
  final Color grid;
  final Color labelColor;
  final bool localeIsChinese;

  @override
  void paint(Canvas canvas, Size size) {
    if (series.isEmpty) {
      return;
    }
    const left = 30.0;
    const top = 8.0;
    const right = 4.0;
    const bottom = 26.0;
    final chartWidth = math.max(1, size.width - left - right);
    final chartHeight = math.max(1, size.height - top - bottom);
    final maxValue = math.max(
      4.0,
      series.fold<double>(0, math.max).ceilToDouble(),
    );
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var index = 0; index <= 4; index++) {
      final y = top + (chartHeight / 4) * index;
      canvas.drawLine(Offset(left, y), Offset(left + chartWidth, y), gridPaint);
      _drawText(
        canvas,
        ((maxValue / 4) * (4 - index)).round().toString(),
        Offset(0, y - 7),
        labelColor,
      );
    }

    final points = <Offset>[];
    for (var index = 0; index < series.length; index++) {
      final x = left + (chartWidth / (series.length - 1)) * index;
      final y = top + chartHeight * (1 - series[index] / maxValue);
      points.add(Offset(x, y));
    }
    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      linePath.lineTo(point.dx, point.dy);
    }
    final areaPath = Path.from(linePath)
      ..lineTo(points.last.dx, top + chartHeight)
      ..lineTo(points.first.dx, top + chartHeight)
      ..close();
    canvas.drawPath(
      areaPath,
      Paint()
        ..color = accent.withValues(alpha: 0.13)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      linePath,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    for (final point in points) {
      canvas.drawCircle(point, 3.6, Paint()..color = accent);
    }

    final today = DateTime.now();
    for (var index = 0; index < series.length; index++) {
      final day = today.subtract(Duration(days: series.length - 1 - index));
      final label = localeIsChinese
          ? '${day.month}/${day.day}'
          : '${day.month}/${day.day}';
      final painter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(color: labelColor, fontSize: 9),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final x = left + (chartWidth / (series.length - 1)) * index;
      painter.paint(
        canvas,
        Offset(
          (x - painter.width / 2).clamp(0, size.width - painter.width),
          top + chartHeight + 8,
        ),
      );
    }
  }

  void _drawText(Canvas canvas, String value, Offset offset, Color color) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(color: color, fontSize: 9),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _WorkloadChartPainter oldDelegate) {
    return oldDelegate.series != series ||
        oldDelegate.accent != accent ||
        oldDelegate.grid != grid ||
        oldDelegate.labelColor != labelColor ||
        oldDelegate.localeIsChinese != localeIsChinese;
  }
}

({String label, Color color, IconData icon}) _stateVisual(
  BuildContext context,
  WorkbenchItemState state,
) {
  final palette = context.palette;
  return switch (state) {
    WorkbenchItemState.blocked => (
      label: appText('被阻塞', 'Blocked'),
      color: palette.danger,
      icon: Icons.error_outline_rounded,
    ),
    WorkbenchItemState.syncing => (
      label: appText('待整理', 'Syncing'),
      color: palette.warning,
      icon: Icons.sync_rounded,
    ),
    WorkbenchItemState.running => (
      label: appText('进行中', 'Running'),
      color: palette.accent,
      icon: Icons.timelapse_rounded,
    ),
    WorkbenchItemState.ready => (
      label: appText('待处理', 'Todo'),
      color: palette.accent,
      icon: Icons.radio_button_unchecked_rounded,
    ),
    WorkbenchItemState.completed => (
      label: appText('已完成', 'Done'),
      color: palette.success,
      icon: Icons.check_circle_outline_rounded,
    ),
  };
}

IconData _taskIcon(WorkbenchItem item) {
  if (item.artifactPaths.isNotEmpty) {
    final extension = item.artifactPaths.first
        .split('.')
        .last
        .trim()
        .toLowerCase();
    return switch (extension) {
      'xlsx' || 'xls' || 'csv' => Icons.table_chart_rounded,
      'pdf' => Icons.picture_as_pdf_rounded,
      'png' || 'jpg' || 'jpeg' || 'webp' => Icons.image_rounded,
      _ => Icons.description_rounded,
    };
  }
  if (item.attachmentNames.isNotEmpty) {
    return Icons.attach_file_rounded;
  }
  return Icons.task_alt_rounded;
}

String _taskMeta(WorkbenchItem item) {
  final parts = <String>[
    if (item.preview.trim().isNotEmpty) item.preview.trim(),
    if (item.artifactPaths.isNotEmpty)
      appText(
        '${item.artifactPaths.length} 个 Artifact',
        '${item.artifactPaths.length} artifacts',
      ),
    _relativeTime(item.updatedAtMs),
  ];
  return parts.join(' · ');
}

String _taskAction(WorkbenchItemState state) {
  return switch (state) {
    WorkbenchItemState.blocked => appText('查看阻塞', 'Review'),
    WorkbenchItemState.syncing => appText('AI 整理', 'Organize'),
    WorkbenchItemState.running => appText('继续处理', 'Continue'),
    WorkbenchItemState.ready => appText('去处理', 'Open'),
    WorkbenchItemState.completed => appText('查看', 'View'),
  };
}

String _relativeTime(double milliseconds) {
  if (milliseconds <= 0) {
    return appText('暂无时间', 'No timestamp');
  }
  final time = DateTime.fromMillisecondsSinceEpoch(milliseconds.round());
  final difference = DateTime.now().difference(time);
  if (difference.isNegative || difference.inMinutes < 1) {
    return appText('刚刚', 'Just now');
  }
  if (difference.inMinutes < 60) {
    return appText(
      '${difference.inMinutes} 分钟前',
      '${difference.inMinutes}m ago',
    );
  }
  if (difference.inHours < 24) {
    return appText('${difference.inHours} 小时前', '${difference.inHours}h ago');
  }
  if (difference.inDays < 7) {
    return appText('${difference.inDays} 天前', '${difference.inDays}d ago');
  }
  return '${time.month}/${time.day}';
}
