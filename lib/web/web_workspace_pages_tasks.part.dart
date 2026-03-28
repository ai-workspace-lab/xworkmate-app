part of 'web_workspace_pages.dart';

class WebTasksPage extends StatefulWidget {
  const WebTasksPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<WebTasksPage> createState() => _WebTasksPageState();
}

class _WebTasksPageState extends State<WebTasksPage> {
  TasksTab _tab = TasksTab.queue;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  String? _selectedTaskId;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        final allItems = controller.taskItemsForTab(_tab.label);
        final items = allItems.where(_matchesQuery).toList(growable: false);
        final selected = _resolveSelectedTask(items);
        final metrics = [
          MetricSummary(
            label: appText('总数', 'Total'),
            value: '${controller.tasksController.totalCount}',
            caption: appText('任务 / 会话聚合', 'Task / session aggregate'),
            icon: Icons.layers_rounded,
          ),
          MetricSummary(
            label: appText('运行中', 'Running'),
            value: '${controller.tasksController.running.length}',
            caption: appText('当前活跃执行', 'Active executions'),
            icon: Icons.play_circle_outline_rounded,
            status: const StatusInfo('Running', StatusTone.success),
          ),
          MetricSummary(
            label: appText('失败', 'Failed'),
            value: '${controller.tasksController.failed.length}',
            caption: appText('中断或报错', 'Interrupted or failed'),
            icon: Icons.error_outline_rounded,
            status: const StatusInfo('Failed', StatusTone.danger),
          ),
          MetricSummary(
            label: appText('计划中', 'Scheduled'),
            value: '${controller.tasksController.scheduled.length}',
            caption: appText('来自 cron 调度器', 'Loaded from cron scheduler'),
            icon: Icons.event_repeat_rounded,
          ),
        ];

        return DesktopWorkspaceScaffold(
          breadcrumbs: _buildWebBreadcrumbs(
            controller,
            rootLabel: WorkspaceDestination.tasks.label,
          ),
          eyebrow: appText('任务与线程', 'Tasks and sessions'),
          title: appText('任务工作台', 'Task workspace'),
          subtitle: appText(
            '左侧筛选和切换任务，右侧查看当前任务详情。',
            'Filter and switch tasks on the left, inspect the current task on the right.',
          ),
          toolbar: Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 240,
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) {
                    setState(() => _query = value.trim().toLowerCase());
                  },
                  decoration: InputDecoration(
                    hintText: appText('搜索任务 / 会话', 'Search tasks / sessions'),
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: appText('清除', 'Clear'),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                  ),
                ),
              ),
              IconButton(
                tooltip: appText('刷新任务', 'Refresh tasks'),
                onPressed: controller.refreshSessions,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                SectionTabs(
                  items: TasksTab.values.map((item) => item.label).toList(),
                  value: _tab.label,
                  onChanged: (value) {
                    setState(() {
                      _tab = TasksTab.values.firstWhere(
                        (item) => item.label == value,
                      );
                      _selectedTaskId = null;
                    });
                  },
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 172,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: metrics.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (context, index) => SizedBox(
                      width: 240,
                      child: MetricCard(metric: metrics[index]),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: SurfaceCard(
                    padding: EdgeInsets.zero,
                    borderRadius: 20,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 360,
                            child: _TaskListPanel(
                              tab: _tab,
                              items: items,
                              selectedTaskId: selected?.id,
                              onSelectTask: (task) {
                                setState(() => _selectedTaskId = task.id);
                              },
                            ),
                          ),
                          Container(
                            width: 1,
                            color: context.palette.strokeSoft,
                          ),
                          Expanded(
                            child: _TaskDetailPanel(
                              controller: controller,
                              tab: _tab,
                              selected: selected,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  bool _matchesQuery(DerivedTaskItem item) {
    if (_query.isEmpty) {
      return true;
    }
    final haystack = [
      item.title,
      item.summary,
      item.owner,
      item.surface,
      item.sessionKey,
    ].join(' ').toLowerCase();
    return haystack.contains(_query);
  }

  DerivedTaskItem? _resolveSelectedTask(List<DerivedTaskItem> items) {
    if (items.isEmpty) {
      return null;
    }
    for (final item in items) {
      if (item.id == _selectedTaskId) {
        return item;
      }
    }
    return items.first;
  }
}

class _TaskListPanel extends StatelessWidget {
  const _TaskListPanel({
    required this.tab,
    required this.items,
    required this.selectedTaskId,
    required this.onSelectTask,
  });

  final TasksTab tab;
  final List<DerivedTaskItem> items;
  final String? selectedTaskId;
  final ValueChanged<DerivedTaskItem> onSelectTask;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final emptyLabel = tab == TasksTab.scheduled
        ? appText('当前没有计划任务。', 'No scheduled tasks right now.')
        : appText('当前筛选下没有任务。', 'No tasks match the current filter.');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
          child: Row(
            children: [
              Text(
                appText('任务列表', 'Task list'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(width: 8),
              Text(
                '${items.length}',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: palette.textMuted),
              ),
            ],
          ),
        ),
        Container(height: 1, color: palette.strokeSoft),
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      emptyLabel,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(10),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final task = items[index];
                    final selected = task.id == selectedTaskId;
                    return _TaskListTile(
                      task: task,
                      selected: selected,
                      onTap: () => onSelectTask(task),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _TaskListTile extends StatelessWidget {
  const _TaskListTile({
    required this.task,
    required this.selected,
    required this.onTap,
  });

  final DerivedTaskItem task;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: selected ? palette.surfacePrimary : Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        key: ValueKey<String>('tasks-list-item-${task.id}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? palette.surfaceSecondary : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: palette.shadow.withValues(alpha: 0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : const [],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      task.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  StatusBadge(status: _taskStatusInfo(task.status)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                task.summary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: palette.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 6,
                children: [
                  _InlineMeta(label: task.owner),
                  _InlineMeta(label: task.startedAtLabel),
                  _InlineMeta(label: task.surface),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskDetailPanel extends StatelessWidget {
  const _TaskDetailPanel({
    required this.controller,
    required this.tab,
    required this.selected,
  });

  final AppController controller;
  final TasksTab tab;
  final DerivedTaskItem? selected;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    if (selected == null) {
      return Center(
        child: Text(
          appText('选择左侧任务查看详情。', 'Select a task on the left.'),
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: palette.textSecondary),
        ),
      );
    }

    return Padding(
      key: const Key('tasks-detail-panel'),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                selected!.title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              StatusBadge(status: _taskStatusInfo(selected!.status)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            selected!.summary,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: palette.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _DetailStat(
                label: appText('任务来源', 'Surface'),
                value: selected!.surface,
              ),
              _DetailStat(
                label: appText('执行代理', 'Owner'),
                value: selected!.owner,
              ),
              _DetailStat(
                label: appText('开始时间', 'Started'),
                value: selected!.startedAtLabel,
              ),
              _DetailStat(
                label: appText('耗时', 'Duration'),
                value: selected!.durationLabel,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: palette.surfaceSecondary,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: palette.shadow.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  appText('会话上下文', 'Conversation context'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                SelectableText(
                  selected!.sessionKey,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          const Spacer(),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: controller.refreshSessions,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(appText('刷新', 'Refresh')),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailStat extends StatelessWidget {
  const _DetailStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      constraints: const BoxConstraints(minWidth: 160),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: palette.surfaceSecondary,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: palette.shadow.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: palette.textMuted),
          ),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.labelLarge),
        ],
      ),
    );
  }
}

class _InlineMeta extends StatelessWidget {
  const _InlineMeta({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(color: context.palette.textMuted),
    );
  }
}

StatusInfo _taskStatusInfo(String status) => switch (status) {
  'running' ||
  'Running' => StatusInfo(appText('运行中', 'Running'), StatusTone.accent),
  'failed' ||
  'Failed' => StatusInfo(appText('失败', 'Failed'), StatusTone.danger),
  'queued' ||
  'Queued' => StatusInfo(appText('排队中', 'Queued'), StatusTone.neutral),
  _ => StatusInfo(appText('可继续', 'Open'), StatusTone.success),
};
