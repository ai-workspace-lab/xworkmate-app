import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../i18n/app_language.dart';
import '../../models/app_models.dart';
import '../../runtime/runtime_models.dart';
import '../../theme/app_palette.dart';

class WorkbenchPage extends StatefulWidget {
  const WorkbenchPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<WorkbenchPage> createState() => _WorkbenchPageState();
}

class _WorkbenchPageState extends State<WorkbenchPage> {
  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        final palette = context.palette;
        final theme = Theme.of(context);
        final sessions = controller.assistantSessions;
        final taskThreads = sessions
            .map((session) => controller.taskThreadForSessionInternal(session.key))
            .whereType<TaskThread>()
            .toList(growable: false);
        final activeCount = sessions.length;
        final syncingCount = taskThreads
            .where((thread) {
              final status = thread.lastArtifactSyncStatus?.trim().toLowerCase() ?? '';
              return status == 'running' || status == 'syncing' || status == 'queued';
            })
            .length;
        final failedCount = taskThreads
            .where((thread) {
              final status = thread.lastArtifactSyncStatus?.trim().toLowerCase() ?? '';
              return status == 'failed' || status == 'interrupted';
            })
            .length;
        final artifactCount = taskThreads.fold<int>(
          0,
          (sum, thread) => sum + thread.lastTaskArtifactRelativePaths.length,
        );
        final selectedTab = _tabIndex.clamp(0, 3);

        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _WorkbenchHero(
                      title: appText('工作台', 'Workbench'),
                      subtitle: appText(
                        '把零碎进展沉淀为清晰工作',
                        'Turn fragmented progress into clear work.',
                      ),
                      onQuickRecord: () {
                        controller.navigateTo(WorkspaceDestination.assistant);
                      },
                    ),
                    const SizedBox(height: 14),
                    _WorkbenchTabs(
                      index: selectedTab,
                      onChanged: (index) => setState(() => _tabIndex = index),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: switch (selectedTab) {
                        0 => _WorkbenchOverview(
                          sessions: sessions,
                          taskThreads: taskThreads,
                          palette: palette,
                          theme: theme,
                          activeCount: activeCount,
                          syncingCount: syncingCount,
                          failedCount: failedCount,
                          artifactCount: artifactCount,
                        ),
                        1 => _WorkbenchTodoList(
                          sessions: sessions,
                          taskThreads: taskThreads,
                        ),
                        2 => _WorkbenchProjectList(taskThreads: taskThreads),
                        _ => _WorkbenchInbox(taskThreads: taskThreads),
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 340,
                child: Column(
                  children: [
                    _WorkbenchInsightCard(
                      title: appText('工作洞察', 'Work insights'),
                      child: _WorkloadTrendCard(taskThreads: taskThreads),
                    ),
                    const SizedBox(height: 12),
                    _WorkbenchInsightCard(
                      title: appText('AI 整理建议', 'AI organization suggestions'),
                      child: _WorkbenchSuggestionList(
                        sessions: sessions,
                        taskThreads: taskThreads,
                        onConfirm: () => controller.navigateTo(
                          WorkspaceDestination.assistant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _WorkbenchHero extends StatelessWidget {
  const _WorkbenchHero({
    required this.title,
    required this.subtitle,
    required this.onQuickRecord,
  });

  final String title;
  final String subtitle;
  final VoidCallback onQuickRecord;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: palette.surfacePrimary,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.strokeSoft),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(subtitle, style: theme.textTheme.bodyMedium?.copyWith(color: palette.textSecondary)),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: onQuickRecord,
            icon: const Icon(Icons.edit_note_rounded),
            label: Text(appText('快速记录', 'Quick record')),
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
    final tabs = <String>[
      appText('总览', 'Overview'),
      appText('我的待办', 'My todo'),
      appText('项目 / 专项', 'Projects / topics'),
      appText('收件箱', 'Inbox'),
    ];
    return Row(
      children: List.generate(tabs.length, (i) {
        final selected = index == i;
        return Padding(
          padding: const EdgeInsets.only(right: 12),
          child: TextButton(
            onPressed: () => onChanged(i),
            child: Text(
              tabs[i],
              style: TextStyle(fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
            ),
          ),
        );
      }),
    );
  }
}

class _WorkbenchOverview extends StatelessWidget {
  const _WorkbenchOverview({
    required this.sessions,
    required this.taskThreads,
    required this.palette,
    required this.theme,
    required this.activeCount,
    required this.syncingCount,
    required this.failedCount,
    required this.artifactCount,
  });

  final List<GatewaySessionSummary> sessions;
  final List<TaskThread> taskThreads;
  final AppPalette palette;
  final ThemeData theme;
  final int activeCount;
  final int syncingCount;
  final int failedCount;
  final int artifactCount;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _StatCard(label: appText('活跃任务', 'Active tasks'), value: '$activeCount', caption: appText('当前可见会话数', 'Visible sessions'), icon: Icons.task_alt_rounded),
            _StatCard(label: appText('同步中', 'Syncing'), value: '$syncingCount', caption: appText('产物同步进行中', 'Artifacts syncing'), icon: Icons.sync_rounded),
            _StatCard(label: appText('异常', 'Blocked'), value: '$failedCount', caption: appText('需要回看', 'Needs attention'), icon: Icons.report_gmailerrorred_rounded),
            _StatCard(label: appText('产物', 'Artifacts'), value: '$artifactCount', caption: appText('已记录文件产物', 'Recorded files'), icon: Icons.folder_copy_rounded),
          ],
        ),
        const SizedBox(height: 12),
        _WorkbenchSectionCard(
          title: appText('需要你处理', 'Needs your attention'),
          child: _WorkbenchTaskList(taskThreads: taskThreads.take(4).toList(growable: false)),
        ),
        const SizedBox(height: 12),
        _WorkbenchSectionCard(
          title: appText('正在推进的专项', 'In progress projects'),
          child: _WorkbenchProjectList(taskThreads: taskThreads),
        ),
      ],
    );
  }
}

class _WorkbenchTaskList extends StatelessWidget {
  const _WorkbenchTaskList({required this.taskThreads});

  final List<TaskThread> taskThreads;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    if (taskThreads.isEmpty) {
      return Text(appText('当前没有待处理事项。', 'No items yet.'), style: theme.textTheme.bodyMedium?.copyWith(color: palette.textSecondary));
    }
    return Column(
      children: taskThreads
          .map(
            (thread) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.check_box_outline_blank_rounded),
              title: Text(thread.title.trim().isEmpty ? thread.threadId : thread.title),
              subtitle: Text(thread.lastArtifactSyncStatus?.trim().isEmpty == true ? appText('无状态', 'No status') : thread.lastArtifactSyncStatus!.trim()),
              trailing: const Icon(Icons.chevron_right_rounded),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _WorkbenchTodoList extends StatelessWidget {
  const _WorkbenchTodoList({
    required this.sessions,
    required this.taskThreads,
  });

  final List<GatewaySessionSummary> sessions;
  final List<TaskThread> taskThreads;

  @override
  Widget build(BuildContext context) {
    return _WorkbenchSectionCard(
      title: appText('我的待办', 'My todo'),
      child: _WorkbenchTaskList(taskThreads: taskThreads),
    );
  }
}

class _WorkbenchProjectList extends StatelessWidget {
  const _WorkbenchProjectList({required this.taskThreads});

  final List<TaskThread> taskThreads;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    if (taskThreads.isEmpty) {
      return Text(appText('暂无专项。', 'No projects yet.'), style: theme.textTheme.bodyMedium?.copyWith(color: palette.textSecondary));
    }
    return Column(
      children: taskThreads
          .take(3)
          .map(
            (thread) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: palette.surfaceSecondary,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: palette.strokeSoft),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(thread.title.trim().isEmpty ? thread.threadId : thread.title, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 4),
                    Text(
                      appText('对应 TaskThread 与 Artifact 已接入。', 'TaskThread and Artifact are connected.'),
                      style: theme.textTheme.bodySmall?.copyWith(color: palette.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _WorkbenchInbox extends StatelessWidget {
  const _WorkbenchInbox({required this.taskThreads});

  final List<TaskThread> taskThreads;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    return _WorkbenchSectionCard(
      title: appText('工作收件箱', 'Work inbox'),
      child: taskThreads.isEmpty
          ? Text(appText('暂时没有收件。', 'No inbox items yet.'), style: theme.textTheme.bodyMedium?.copyWith(color: palette.textSecondary))
          : Column(
              children: taskThreads.take(5).map((thread) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.inbox_rounded),
                title: Text(thread.title.trim().isEmpty ? thread.threadId : thread.title),
                subtitle: Text(appText('可整理为待办、专项或学习候选。', 'Can be organized into todos, projects, or learning candidates.')),
              )).toList(growable: false),
            ),
    );
  }
}

class _WorkbenchInsightCard extends StatelessWidget {
  const _WorkbenchInsightCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _WorkbenchSectionCard(title: title, child: child);
  }
}

class _WorkbenchSectionCard extends StatelessWidget {
  const _WorkbenchSectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surfacePrimary,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.strokeSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.caption,
    required this.icon,
  });

  final String label;
  final String value;
  final String caption;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    return Container(
      width: 220,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.surfacePrimary,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.strokeSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: palette.accent),
          const SizedBox(height: 10),
          Text(value, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(label, style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(caption, style: theme.textTheme.bodySmall?.copyWith(color: palette.textSecondary)),
        ],
      ),
    );
  }
}

class _WorkloadTrendCard extends StatelessWidget {
  const _WorkloadTrendCard({required this.taskThreads});

  final List<TaskThread> taskThreads;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    final series = <double>[
      for (var i = 0; i < 7; i++) (taskThreads.length * 2.0) + i * 1.3 + 6,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(appText('近 7 天负载趋势', 'Workload trend (last 7 days)'), style: theme.textTheme.bodyMedium),
        const SizedBox(height: 12),
        SizedBox(
          height: 140,
          child: CustomPaint(
            painter: _SimpleLinePainter(series: series, color: palette.accent),
            size: Size.infinite,
          ),
        ),
      ],
    );
  }
}

class _WorkbenchSuggestionList extends StatelessWidget {
  const _WorkbenchSuggestionList({
    required this.sessions,
    required this.taskThreads,
    required this.onConfirm,
  });

  final List<GatewaySessionSummary> sessions;
  final List<TaskThread> taskThreads;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    final suggestions = <(String, String, IconData, VoidCallback)>[
      (
        appText('建议归类为待办', 'Suggest as todo'),
        appText('把最近的碎片输入汇总成下一步动作。', 'Turn recent fragments into next actions.'),
        Icons.checklist_rounded,
        onConfirm,
      ),
      (
        appText('建议创建专项', 'Suggest a project'),
        appText('把连续工作串成一个专项卡片。', 'Group ongoing work into a project card.'),
        Icons.folder_special_rounded,
        onConfirm,
      ),
    ];
    return Column(
      children: suggestions
          .map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: palette.surfaceSecondary,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: palette.strokeSoft),
                ),
                child: Row(
                  children: [
                    Icon(item.$3, color: palette.accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.$1, style: theme.textTheme.titleSmall),
                          const SizedBox(height: 2),
                          Text(item.$2, style: theme.textTheme.bodySmall?.copyWith(color: palette.textSecondary)),
                        ],
                      ),
                    ),
                    TextButton(onPressed: item.$4, child: Text(appText('确认', 'Confirm'))),
                  ],
                ),
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _SimpleLinePainter extends CustomPainter {
  _SimpleLinePainter({required this.series, required this.color});

  final List<double> series;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (series.isEmpty) {
      return;
    }
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;
    final min = series.reduce((a, b) => a < b ? a : b);
    final max = series.reduce((a, b) => a > b ? a : b);
    double norm(double value) {
      final span = (max - min).abs() < 0.01 ? 1.0 : (max - min);
      return (value - min) / span;
    }
    final points = <Offset>[];
    for (var i = 0; i < series.length; i++) {
      final x = series.length == 1 ? size.width / 2 : (size.width / (series.length - 1)) * i;
      final y = size.height - (norm(series[i]) * (size.height - 12)) - 6;
      points.add(Offset(x, y));
    }
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    final area = Path()
      ..addPath(path, Offset.zero)
      ..lineTo(points.last.dx, size.height)
      ..lineTo(points.first.dx, size.height)
      ..close();
    canvas.drawPath(area, fillPaint);
    canvas.drawPath(path, paint);
    for (final point in points) {
      canvas.drawCircle(point, 4, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _SimpleLinePainter oldDelegate) {
    return oldDelegate.series != series || oldDelegate.color != color;
  }
}
