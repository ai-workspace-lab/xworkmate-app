import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../i18n/app_language.dart';
import '../../models/app_models.dart';
import '../../runtime/runtime_models.dart';
import '../../widgets/metric_card.dart';
import '../../widgets/section_tabs.dart';
import '../../widgets/status_badge.dart';
import '../../widgets/surface_card.dart';
import '../../widgets/top_bar.dart';

class TasksPage extends StatefulWidget {
  const TasksPage({
    super.key,
    required this.controller,
    required this.onOpenDetail,
  });

  final AppController controller;
  final ValueChanged<DetailPanelData> onOpenDetail;

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  TasksTab _tab = TasksTab.queue;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final items = controller.taskItemsForTab(_tabKey);
    final metrics = [
      MetricSummary(
        label: appText('总数', 'Total'),
        value: '${controller.tasksController.totalCount}',
        caption: appText('从会话与对话中派生', 'Derived from sessions / chat'),
        icon: Icons.layers_rounded,
      ),
      MetricSummary(
        label: appText('运行中', 'Running'),
        value: '${controller.tasksController.running.length}',
        caption: appText('当前活跃运行', 'Current active runs'),
        icon: Icons.play_circle_outline_rounded,
        status: _statusInfoForTask('Running'),
      ),
      MetricSummary(
        label: appText('失败', 'Failed'),
        value: '${controller.tasksController.failed.length}',
        caption: appText('中断或报错的运行', 'Aborted / error runs'),
        icon: Icons.error_outline_rounded,
        status: _statusInfoForTask('Failed'),
      ),
      MetricSummary(
        label: appText('计划中', 'Scheduled'),
        value: '${controller.tasksController.scheduled.length}',
        caption: appText(
          '来自 Gateway cron 调度器',
          'Loaded from the gateway cron scheduler',
        ),
        icon: Icons.event_repeat_rounded,
      ),
    ];

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(32, 32, 32, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TopBar(
                title: appText('任务', 'Tasks'),
                subtitle: appText(
                  '查看任务队列、执行状态与历史记录',
                  'Review queue, execution state, and history.',
                ),
                trailing: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 220,
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: appText('搜索任务', 'Search tasks'),
                          prefixIcon: Icon(Icons.search_rounded),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: controller.refreshSessions,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () =>
                          controller.navigateTo(WorkspaceDestination.assistant),
                      icon: const Icon(Icons.add_rounded),
                      label: Text(appText('新建任务', 'New Task')),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SectionTabs(
                items: TasksTab.values.map((item) => item.label).toList(),
                value: _tab.label,
                onChanged: (value) => setState(
                  () => _tab = TasksTab.values.firstWhere(
                    (item) => item.label == value,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth > 980
                      ? (constraints.maxWidth - 48) / 4
                      : constraints.maxWidth > 640
                      ? (constraints.maxWidth - 16) / 2
                      : constraints.maxWidth;
                  return Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: metrics
                        .map(
                          (metric) => SizedBox(
                            width: width,
                            child: MetricCard(metric: metric),
                          ),
                        )
                        .toList(),
                  );
                },
              ),
              const SizedBox(height: 24),
              if (_tab == TasksTab.scheduled && items.isEmpty)
                SurfaceCard(
                  child: Text(
                    appText(
                      '当前网关还没有计划任务。',
                      'No scheduled jobs are currently exposed by the gateway.',
                    ),
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                )
              else if (items.isEmpty)
                SurfaceCard(
                  child: Text(
                    controller.connection.status ==
                            RuntimeConnectionStatus.connected
                        ? appText('当前页签暂无任务。', 'No tasks in this tab.')
                        : appText(
                            '连接 Gateway 后，这里会显示真实的队列、运行中、历史和失败任务。',
                            'Connect a gateway to load live queue, running, history, and failed tasks.',
                          ),
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                )
              else
                ...items.map(
                  (task) => Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: SurfaceCard(
                      onTap: () => widget.onOpenDetail(_taskDetail(task)),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          if (constraints.maxWidth < 820) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  task.title,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  task.summary,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                const SizedBox(height: 14),
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 12,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    StatusBadge(
                                      status: _statusInfoForTask(task.status),
                                    ),
                                    Text(task.owner),
                                    Text(task.startedAtLabel),
                                    const Icon(Icons.chevron_right_rounded),
                                  ],
                                ),
                              ],
                            );
                          }

                          return Row(
                            children: [
                              Expanded(
                                flex: 4,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      task.title,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      task.summary,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: StatusBadge(
                                    status: _statusInfoForTask(task.status),
                                  ),
                                ),
                              ),
                              Expanded(flex: 2, child: Text(task.owner)),
                              Expanded(
                                flex: 2,
                                child: Text(task.startedAtLabel),
                              ),
                              const Icon(Icons.chevron_right_rounded),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  appText(
                    '点击任务项后会打开详情侧栏',
                    'Click a task to open the detail drawer.',
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  DetailPanelData _taskDetail(DerivedTaskItem task) {
    return DetailPanelData(
      title: task.title,
      subtitle: appText('会话派生任务', 'Session-derived Task'),
      icon: Icons.layers_rounded,
      status: _statusInfoForTask(task.status),
      description: task.summary,
      meta: [task.surface, task.sessionKey],
      actions: [appText('打开会话', 'Open Session'), appText('刷新', 'Refresh')],
      sections: [
        DetailSection(
          title: appText('任务', 'Task'),
          items: [
            DetailItem(label: appText('负责人', 'Owner'), value: task.owner),
            DetailItem(
              label: appText('状态', 'Status'),
              value: _statusLabel(task.status),
            ),
            DetailItem(
              label: appText('开始时间', 'Started'),
              value: task.startedAtLabel,
            ),
            DetailItem(
              label: appText('更新时间', 'Updated'),
              value: task.durationLabel,
            ),
            DetailItem(
              label: appText('会话 Key', 'Session Key'),
              value: task.sessionKey,
            ),
          ],
        ),
      ],
    );
  }

  String get _tabKey => switch (_tab) {
    TasksTab.queue => 'Queue',
    TasksTab.running => 'Running',
    TasksTab.history => 'History',
    TasksTab.failed => 'Failed',
    TasksTab.scheduled => 'Scheduled',
  };
}

StatusInfo _statusInfoForTask(String status) => switch (status) {
  'Running' => StatusInfo(appText('运行中', 'Running'), StatusTone.accent),
  'Failed' => StatusInfo(appText('失败', 'Failed'), StatusTone.danger),
  'Queued' => StatusInfo(appText('排队中', 'Queued'), StatusTone.neutral),
  'Scheduled' => StatusInfo(appText('计划中', 'Scheduled'), StatusTone.accent),
  'Disabled' => StatusInfo(appText('已禁用', 'Disabled'), StatusTone.neutral),
  _ => StatusInfo(appText('已完成', 'Completed'), StatusTone.success),
};

String _statusLabel(String status) => _statusInfoForTask(status).label;
