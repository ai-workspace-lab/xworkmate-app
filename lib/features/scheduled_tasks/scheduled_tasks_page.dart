import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../i18n/app_language.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import 'scheduled_tasks_controller.dart';
import 'scheduled_tasks_models.dart';

class ScheduledTasksPage extends StatefulWidget {
  const ScheduledTasksPage({
    super.key,
    required this.controller,
    this.leading,
  });

  final AppController controller;
  final Widget? leading;

  @override
  State<ScheduledTasksPage> createState() => _ScheduledTasksPageState();
}

class _ScheduledTasksPageState extends State<ScheduledTasksPage> {
  late final ScheduledTasksController _tasksController;

  @override
  void initState() {
    super.initState();
    _tasksController = widget.controller.scheduledTasksController;
    _tasksController.addListener(_onTasksChanged);
    _tasksController.startScheduler();
  }

  @override
  void dispose() {
    _tasksController.stopScheduler();
    _tasksController.removeListener(_onTasksChanged);
    super.dispose();
  }

  void _onTasksChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    final tasks = _tasksController.tasks;

    return Scaffold(
      backgroundColor: palette.canvas,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context, palette, theme),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                children: [
                  _buildMetricsRow(context, palette, theme),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        appText('聚合任务会话配置', 'Aggregated task sessions configuration'),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: palette.textPrimary,
                        ),
                      ),
                      TextButton.icon(
                        key: const Key('scheduled-tasks-refresh-all-button'),
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: Text(appText('全部对账与巡检', 'Sync & audit all')),
                        onPressed: () async {
                          for (final t in tasks) {
                            if (t.enabled) {
                              await _tasksController.runTaskNow(t.id, selectSession: false);
                            }
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  for (final task in tasks) ...[
                    _ScheduledTaskCard(
                      task: task,
                      controller: _tasksController,
                      onRunNow: (selectSession) =>
                          _tasksController.runTaskNow(task.id, selectSession: selectSession),
                    ),
                    const SizedBox(height: 16),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, AppPalette palette, ThemeData theme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showAllBadges = constraints.maxWidth >= 720;
        final showOneBadge = constraints.maxWidth >= 540;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              if (widget.leading != null) ...[
                widget.leading!,
                const SizedBox(width: 12),
              ],
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: palette.surfacePrimary,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: palette.strokeSoft),
                ),
                child: Icon(
                  Icons.access_time_rounded,
                  size: 22,
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      appText('定时任务', 'Scheduled Tasks'),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      appText(
                        '多源 Agent 聚合调度、QMD 记忆周期对账与历史会话激活',
                        'Multi-agent task aggregation, periodic QMD sync, and active task sessions',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (showAllBadges) ...[
                _StatusChip(
                  label: 'AI Gateway :4000',
                  color: palette.success,
                ),
                const SizedBox(width: 8),
                _StatusChip(
                  label: 'QMD :8181',
                  color: palette.accent,
                ),
                const SizedBox(width: 8),
                _StatusChip(
                  label: 'DSH :3000',
                  color: palette.textSecondary,
                ),
              ] else if (showOneBadge) ...[
                _StatusChip(
                  label: 'AI Gateway',
                  color: palette.success,
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildMetricsRow(BuildContext context, AppPalette palette, ThemeData theme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 640;
        final totalCount = _tasksController.totalCount;
        final activeCount = _tasksController.activeCount;
        final lastRun = _tasksController.lastRunAt;
        final lastRunStr = lastRun != null
            ? '${lastRun.hour.toString().padLeft(2, '0')}:${lastRun.minute.toString().padLeft(2, '0')}:${lastRun.second.toString().padLeft(2, '0')}'
            : appText('未执行', 'Never');

        final cards = [
          _MetricCard(
            title: appText('任务总数', 'Total Tasks'),
            value: '$totalCount',
            subtitle: appText('预置 4 类聚合驱动', '4 Preset drivers'),
            icon: Icons.checklist_rounded,
          ),
          _MetricCard(
            title: appText('活跃调度', 'Active Schedulers'),
            value: '$activeCount',
            subtitle: appText('自动周期执行中', 'Running periodically'),
            icon: Icons.bolt_rounded,
          ),
          _MetricCard(
            title: appText('最近对账', 'Last Execution'),
            value: lastRunStr,
            subtitle: appText('本地与 QMD 权威状态', 'Authoritative sync state'),
            icon: Icons.update_rounded,
          ),
          _MetricCard(
            title: appText('聚合目标', 'Target Agents'),
            value: '4 Agents',
            subtitle: 'QMD · Codex · Gemini · Grok',
            icon: Icons.hub_outlined,
          ),
        ];

        if (isNarrow) {
          return Column(
            children: [
              for (final card in cards) ...[
                card,
                const SizedBox(height: 10),
              ],
            ],
          );
        }

        return Row(
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              Expanded(child: cards[i]),
              if (i < cards.length - 1) const SizedBox(width: 12),
            ],
          ],
        );
      },
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: palette.surfacePrimary,
        borderRadius: BorderRadius.circular(AppRadius.badge),
        border: Border.all(color: palette.strokeSoft),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: palette.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.surfacePrimary,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: palette.strokeSoft),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: palette.surfaceSecondary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 20, color: palette.textPrimary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: palette.textMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: palette.textPrimary,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    color: palette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScheduledTaskCard extends StatelessWidget {
  const _ScheduledTaskCard({
    required this.task,
    required this.controller,
    required this.onRunNow,
  });

  final ScheduledTaskConfig task;
  final ScheduledTasksController controller;
  final Future<void> Function(bool selectSession) onRunNow;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);

    return Container(
      key: Key('scheduled-task-card-${task.id}'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: palette.surfacePrimary,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: task.enabled ? palette.strokeSoft : palette.strokeSoft.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: palette.surfaceSecondary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  task.type.icon,
                  size: 20,
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          task.title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: palette.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: palette.surfaceSecondary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            task.sourceAgent,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: palette.textSecondary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: palette.surfaceSecondary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            task.targetModel,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: palette.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      task.description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                key: Key('scheduled-task-switch-${task.id}'),
                value: task.enabled,
                onChanged: (val) => controller.toggleTask(task.id, val),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    appText('执行周期:', 'Interval:'),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<int>(
                    key: Key('scheduled-task-interval-${task.id}'),
                    value: task.intervalMinutes,
                    isDense: true,
                    underline: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(value: 15, child: Text('15 分钟 (15m)')),
                      DropdownMenuItem(value: 30, child: Text('30 分钟 (30m)')),
                      DropdownMenuItem(value: 60, child: Text('1 小时 (1h)')),
                      DropdownMenuItem(value: 360, child: Text('6 小时 (6h)')),
                      DropdownMenuItem(value: 1440, child: Text('每天 (24h)')),
                    ],
                    onChanged: task.enabled
                        ? (val) {
                            if (val != null) {
                              controller.updateTaskInterval(task.id, val);
                            }
                          }
                        : null,
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (task.lastStatus != null) ...[
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          task.lastError != null
                              ? Icons.error_outline_rounded
                              : Icons.check_circle_outline_rounded,
                          size: 15,
                          color: task.lastError != null
                              ? palette.danger
                              : palette.success,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          task.lastStatus!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: task.lastError != null
                                ? palette.danger
                                : palette.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                  OutlinedButton.icon(
                    key: Key('scheduled-task-run-bg-${task.id}'),
                    icon: const Icon(Icons.sync_rounded, size: 15),
                    label: Text(appText('后台执行', 'Run background')),
                    onPressed: () => onRunNow(false),
                  ),
                  FilledButton.icon(
                    key: Key('scheduled-task-run-open-${task.id}'),
                    icon: Icon(
                      task.type == ScheduledTaskType.qmdSync
                          ? Icons.sync_rounded
                          : Icons.open_in_new_rounded,
                      size: 15,
                    ),
                    label: Text(
                      task.type == ScheduledTaskType.qmdSync
                          ? appText('立即同步', 'Sync now')
                          : appText('立即执行并进入会话', 'Run & Open Session'),
                    ),
                    onPressed: () => onRunNow(true),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
