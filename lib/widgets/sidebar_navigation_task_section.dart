part of 'sidebar_navigation.dart';

class SidebarTaskItem {
  const SidebarTaskItem({
    required this.sessionKey,
    required this.title,
    required this.preview,
    required this.updatedAtMs,
    required this.executionTarget,
    required this.isCurrent,
    required this.pending,
    this.draft = false,
  });

  final String sessionKey;
  final String title;
  final String preview;
  final double? updatedAtMs;
  final AssistantExecutionTarget executionTarget;
  final bool isCurrent;
  final bool pending;
  final bool draft;
}

class SidebarTaskSection extends StatefulWidget {
  const SidebarTaskSection({
    super.key,
    required this.currentSection,
    required this.items,
    required this.visibleExecutionTargets,
    required this.skillCount,
    required this.showCollapseControl,
    required this.onCycleSidebarState,
    this.onRefreshTasks,
    this.onCreateTask,
    this.onReturnToAssistant,
    this.onSelectTask,
    this.onArchiveTask,
    this.onRenameTask,
  });

  final WorkspaceDestination currentSection;
  final List<SidebarTaskItem> items;
  final List<AssistantExecutionTarget> visibleExecutionTargets;
  final int skillCount;
  final bool showCollapseControl;
  final VoidCallback onCycleSidebarState;
  final Future<void> Function()? onRefreshTasks;
  final Future<void> Function()? onCreateTask;
  final VoidCallback? onReturnToAssistant;
  final Future<void> Function(String sessionKey)? onSelectTask;
  final Future<void> Function(String sessionKey)? onArchiveTask;
  final Future<void> Function(String sessionKey, String title)? onRenameTask;

  @override
  State<SidebarTaskSection> createState() => _SidebarTaskSectionState();
}

class _SidebarTaskSectionState extends State<SidebarTaskSection> {
  final TextEditingController _searchController = TextEditingController();
  final Set<AssistantExecutionTarget> _expandedTargets =
      <AssistantExecutionTarget>{};
  String _query = '';

  @override
  void initState() {
    super.initState();
    _syncExpandedTargets();
  }

  @override
  void didUpdateWidget(covariant SidebarTaskSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items != widget.items) {
      _syncExpandedTargets();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    final filteredItems = _filteredItems();
    final groups = _groupedItems(filteredItems);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: TextField(
                  key: const Key('workspace-sidebar-task-search'),
                  controller: _searchController,
                  onChanged: (value) {
                    setState(() {
                      _query = value.trim().toLowerCase();
                    });
                  },
                  decoration: InputDecoration(
                    hintText: appText('搜索任务', 'Search tasks'),
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: appText('清除搜索', 'Clear search'),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _query = '';
                              });
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                  ),
                ),
              ),
              if (widget.showCollapseControl) ...[
                const SizedBox(width: AppSpacing.xs),
                Tooltip(
                  message: appText('收起侧边栏', 'Collapse sidebar'),
                  child: IconButton(
                    key: const Key('workspace-sidebar-collapse-button'),
                    onPressed: widget.onCycleSidebarState,
                    visualDensity: VisualDensity.compact,
                    splashRadius: 18,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 28,
                      height: 28,
                    ),
                    style: IconButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(28, 28),
                      maximumSize: const Size(28, 28),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      backgroundColor: Colors.transparent,
                      foregroundColor: palette.textSecondary,
                      overlayColor: palette.chromeSurfacePressed,
                      side: BorderSide.none,
                      shape: const CircleBorder(),
                    ),
                    icon: const Icon(
                      Icons.keyboard_double_arrow_left_rounded,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: widget.currentSection == WorkspaceDestination.settings
              ? _SidebarBackToAssistantButton(
                  onPressed: widget.onReturnToAssistant,
                )
              : FilledButton.tonalIcon(
                  key: const Key('workspace-sidebar-new-task-button'),
                  onPressed: widget.onCreateTask == null
                      ? null
                      : () async {
                          await widget.onCreateTask!();
                        },
                  icon: const Icon(Icons.edit_note_rounded),
                  label: Text(appText('新对话', 'New conversation')),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
          child: Text(
            appText('任务列表', 'Task list'),
            style: theme.textTheme.titleSmall,
          ),
        ),
        Expanded(
          child: Scrollbar(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 4),
              children: [
                for (final group in groups) ...[
                  _SidebarTaskGroupHeader(
                    executionTarget: group.executionTarget,
                    count: group.items.length,
                    expanded: _expandedTargets.contains(group.executionTarget),
                    onTap: () {
                      setState(() {
                        if (_expandedTargets.contains(group.executionTarget)) {
                          _expandedTargets.remove(group.executionTarget);
                        } else {
                          _expandedTargets.add(group.executionTarget);
                        }
                      });
                    },
                  ),
                  if (_expandedTargets.contains(group.executionTarget)) ...[
                    if (group.items.isEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(28, 0, 8, 6),
                        child: Text(
                          appText('当前分组没有任务。', 'No tasks in this group.'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: palette.textMuted,
                          ),
                        ),
                      ),
                    for (final item in group.items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: _SidebarTaskTile(
                          item: item,
                          onTap: widget.onSelectTask == null
                              ? null
                              : () async {
                                  await widget.onSelectTask!(item.sessionKey);
                                },
                          onArchive:
                              widget.onArchiveTask == null || item.pending
                              ? null
                              : () async {
                                  await widget.onArchiveTask!(item.sessionKey);
                                },
                          onRename: widget.onRenameTask == null
                              ? null
                              : () async {
                                  final renamed = await _promptRenameTask(
                                    context,
                                    item.title,
                                  );
                                  if (!mounted || renamed == null) {
                                    return;
                                  }
                                  await widget.onRenameTask!(
                                    item.sessionKey,
                                    renamed,
                                  );
                                },
                        ),
                      ),
                  ],
                  const SizedBox(height: 4),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<SidebarTaskItem> _filteredItems() {
    if (_query.isEmpty) {
      return widget.items;
    }
    return widget.items
        .where((item) {
          final haystack = '${item.title}\n${item.preview}\n${item.sessionKey}'
              .toLowerCase();
          return haystack.contains(_query);
        })
        .toList(growable: false);
  }

  List<_SidebarTaskGroup> _groupedItems(List<SidebarTaskItem> items) {
    final compactTargets = compactAssistantExecutionTargets(
      widget.visibleExecutionTargets,
    );
    final grouped = <AssistantExecutionTarget, List<SidebarTaskItem>>{
      for (final target in compactTargets) target: <SidebarTaskItem>[],
    };
    for (final item in items) {
      final bucket =
          grouped[collapseAssistantExecutionTargetForDisplay(
            item.executionTarget,
          )];
      if (bucket == null) {
        continue;
      }
      bucket.add(item);
    }
    return compactTargets
        .map(
          (target) => _SidebarTaskGroup(
            executionTarget: target,
            items: grouped[target]!,
          ),
        )
        .toList(growable: false);
  }

  Future<String?> _promptRenameTask(
    BuildContext context,
    String currentTitle,
  ) async {
    final input = TextEditingController(text: currentTitle);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(appText('重命名任务', 'Rename task')),
        content: TextField(
          key: const Key('workspace-sidebar-task-rename-input'),
          controller: input,
          autofocus: true,
          decoration: InputDecoration(
            labelText: appText('任务名称', 'Task name'),
            hintText: appText('留空后恢复默认名称', 'Leave empty to restore default'),
          ),
          onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(appText('取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(input.text.trim()),
            child: Text(appText('保存', 'Save')),
          ),
        ],
      ),
    );
    input.dispose();
    return result;
  }

  void _syncExpandedTargets() {
    if (_expandedTargets.isNotEmpty) {
      return;
    }
    _expandedTargets.addAll(
      compactAssistantExecutionTargets(widget.visibleExecutionTargets),
    );
  }
}

class _SidebarBackToAssistantButton extends StatelessWidget {
  const _SidebarBackToAssistantButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const Key('workspace-sidebar-back-to-chat-button'),
        onTap: onPressed,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          height: 56,
          decoration: BoxDecoration(
            color: palette.surfaceSecondary,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: palette.strokeSoft),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: palette.textPrimary, width: 1.8),
                  ),
                  child: Icon(
                    Icons.arrow_back_rounded,
                    size: 24,
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    appText('返回聊天', 'Back to chat'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: palette.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarTaskGroup {
  const _SidebarTaskGroup({required this.executionTarget, required this.items});

  final AssistantExecutionTarget executionTarget;
  final List<SidebarTaskItem> items;
}

class _SidebarTaskGroupHeader extends StatelessWidget {
  const _SidebarTaskGroupHeader({
    required this.executionTarget,
    required this.count,
    required this.expanded,
    required this.onTap,
  });

  final AssistantExecutionTarget executionTarget;
  final int count;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey<String>(
          'workspace-sidebar-task-group-${executionTarget.name}',
        ),
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 2),
          child: Row(
            children: [
              Icon(
                expanded
                    ? Icons.keyboard_arrow_down_rounded
                    : Icons.keyboard_arrow_right_rounded,
                size: 16,
                color: palette.textMuted,
              ),
              const SizedBox(width: 4),
              Icon(
                _sidebarTaskTargetIcon(executionTarget),
                size: 14,
                color: palette.textMuted,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  executionTarget.compactLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: palette.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$count',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: palette.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarTaskTile extends StatelessWidget {
  const _SidebarTaskTile({
    required this.item,
    this.onTap,
    this.onArchive,
    this.onRename,
  });

  final SidebarTaskItem item;
  final Future<void> Function()? onTap;
  final Future<void> Function()? onArchive;
  final Future<void> Function()? onRename;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    return Material(
      color: item.isCurrent ? palette.surfacePrimary : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        key: ValueKey<String>('workspace-sidebar-task-item-${item.sessionKey}'),
        borderRadius: BorderRadius.circular(8),
        onTap: onTap == null
            ? null
            : () async {
                await onTap!();
              },
        onLongPress: onRename == null
            ? null
            : () async {
                await onRename!();
              },
        onSecondaryTap: onRename == null
            ? null
            : () async {
                await onRename!();
              },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: item.isCurrent
                ? palette.surfaceSecondary
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: item.isCurrent ? palette.strokeSoft : Colors.transparent,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: item.pending
                      ? palette.accentMuted.withValues(alpha: 0.88)
                      : palette.surfacePrimary,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  item.draft
                      ? Icons.edit_note_rounded
                      : item.pending
                      ? Icons.play_arrow_rounded
                      : Icons.task_alt_rounded,
                  size: 15,
                  color: item.pending ? palette.accent : palette.textSecondary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: item.isCurrent
                            ? FontWeight.w700
                            : FontWeight.w600,
                      ),
                    ),
                    if (item.preview.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        item.preview.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _sidebarTaskUpdatedAtLabel(item.updatedAtMs),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: palette.textMuted,
                    ),
                  ),
                  if (onArchive != null)
                    IconButton(
                      key: ValueKey<String>(
                        'workspace-sidebar-task-archive-${item.sessionKey}',
                      ),
                      tooltip: appText('归档任务', 'Archive task'),
                      visualDensity: VisualDensity.compact,
                      splashRadius: 12,
                      onPressed: () async {
                        await onArchive!();
                      },
                      icon: Icon(
                        Icons.archive_outlined,
                        size: 18,
                        color: palette.textMuted,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _sidebarTaskUpdatedAtLabel(double? updatedAtMs) {
  if (updatedAtMs == null) {
    return '';
  }
  final timestamp = DateTime.fromMillisecondsSinceEpoch(updatedAtMs.round());
  final now = DateTime.now();
  final delta = now.difference(timestamp);
  if (delta.inMinutes < 1) {
    return appText('刚刚', 'Just now');
  }
  if (delta.inHours < 1) {
    return appText('${delta.inMinutes} 分钟前', '${delta.inMinutes}m ago');
  }
  if (delta.inDays < 1) {
    return appText('${delta.inHours} 小时前', '${delta.inHours}h ago');
  }
  if (delta.inDays < 7) {
    return appText('${delta.inDays} 天前', '${delta.inDays}d ago');
  }
  return '${timestamp.month}/${timestamp.day}';
}

IconData _sidebarTaskTargetIcon(AssistantExecutionTarget target) {
  return switch (target) {
    AssistantExecutionTarget.gateway => Icons.cloud_outlined,
  };
}
