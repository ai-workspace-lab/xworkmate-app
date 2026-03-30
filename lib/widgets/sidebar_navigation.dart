import 'package:flutter/material.dart';

import '../i18n/app_language.dart';
import '../models/app_models.dart';
import '../runtime/runtime_models.dart';
import '../theme/app_palette.dart';
import '../theme/app_theme.dart';
import 'chrome_quick_action_buttons.dart';

class SidebarNavigation extends StatelessWidget {
  const SidebarNavigation({
    super.key,
    required this.currentSection,
    required this.sidebarState,
    required this.appLanguage,
    required this.themeMode,
    required this.onSectionChanged,
    required this.onToggleLanguage,
    required this.onCycleSidebarState,
    required this.onExpandFromCollapsed,
    required this.onOpenAccount,
    required this.onOpenThemeToggle,
    this.onOpenHome,
    required this.accountName,
    required this.accountSubtitle,
    this.accountWorkspaceFollowed = false,
    this.onToggleAccountWorkspaceFollowed,
    this.onOpenOnlineWorkspace,
    this.expandedWidthOverride,
    this.marginOverride,
    this.showCollapseControl = true,
    this.availableDestinations,
    this.favoriteDestinations = const <AssistantFocusEntry>{},
    this.onToggleFavorite,
    this.currentSettingsTab,
    this.availableSettingsTabs = const <SettingsTab>[],
    this.onSettingsTabChanged,
    this.taskItems = const <SidebarTaskItem>[],
    this.assistantSkillCount = 0,
    this.onRefreshTasks,
    this.onCreateTask,
    this.onSelectTask,
    this.onArchiveTask,
    this.onRenameTask,
  });

  final WorkspaceDestination currentSection;
  final AppSidebarState sidebarState;
  final AppLanguage appLanguage;
  final ThemeMode themeMode;
  final ValueChanged<WorkspaceDestination> onSectionChanged;
  final VoidCallback onToggleLanguage;
  final VoidCallback onCycleSidebarState;
  final VoidCallback onExpandFromCollapsed;
  final VoidCallback onOpenAccount;
  final VoidCallback onOpenThemeToggle;
  final VoidCallback? onOpenHome;
  final String accountName;
  final String accountSubtitle;
  final bool accountWorkspaceFollowed;
  final Future<void> Function()? onToggleAccountWorkspaceFollowed;
  final VoidCallback? onOpenOnlineWorkspace;
  final double? expandedWidthOverride;
  final EdgeInsetsGeometry? marginOverride;
  final bool showCollapseControl;
  final Set<WorkspaceDestination>? availableDestinations;
  final Set<AssistantFocusEntry> favoriteDestinations;
  final Future<void> Function(AssistantFocusEntry section)? onToggleFavorite;
  final SettingsTab? currentSettingsTab;
  final List<SettingsTab> availableSettingsTabs;
  final ValueChanged<SettingsTab>? onSettingsTabChanged;
  final List<SidebarTaskItem> taskItems;
  final int assistantSkillCount;
  final Future<void> Function()? onRefreshTasks;
  final Future<void> Function()? onCreateTask;
  final Future<void> Function(String sessionKey)? onSelectTask;
  final Future<void> Function(String sessionKey)? onArchiveTask;
  final Future<void> Function(String sessionKey, String title)? onRenameTask;

  static const _primarySections = <WorkspaceDestination>[
    WorkspaceDestination.assistant,
    WorkspaceDestination.tasks,
    WorkspaceDestination.skills,
  ];

  static const _workspaceSections = <WorkspaceDestination>[
    WorkspaceDestination.nodes,
    WorkspaceDestination.agents,
  ];

  static const _toolSections = <WorkspaceDestination>[
    WorkspaceDestination.mcpServer,
    WorkspaceDestination.clawHub,
    WorkspaceDestination.secrets,
    WorkspaceDestination.aiGateway,
  ];

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isExpanded = sidebarState == AppSidebarState.expanded;
    final isCollapsed = sidebarState == AppSidebarState.collapsed;
    final showTaskSection = !isCollapsed;
    final primarySections = _filterSections(_primarySections);
    final workspaceSections = _filterSections(_workspaceSections);
    final toolSections = _filterSections(_toolSections);
    final expandedWidth =
        expandedWidthOverride ??
        (appLanguage == AppLanguage.zh
            ? AppSizes.sidebarExpandedWidthZh
            : AppSizes.sidebarExpandedWidthEn);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: isExpanded ? expandedWidth : AppSizes.sidebarCollapsedWidth,
      height: double.infinity,
      margin: marginOverride ?? const EdgeInsets.fromLTRB(4, 4, 4, 0),
      decoration: BoxDecoration(
        color: palette.chromeSurface,
        borderRadius: BorderRadius.circular(AppRadius.sidebar),
        border: Border.all(color: palette.strokeSoft),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.zero,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (showTaskSection)
                            SidebarTaskSection(
                              items: taskItems,
                              skillCount: assistantSkillCount,
                              onRefreshTasks: onRefreshTasks,
                              onCreateTask: onCreateTask,
                              onSelectTask: onSelectTask,
                              onArchiveTask: onArchiveTask,
                              onRenameTask: onRenameTask,
                            ),
                          if (showTaskSection &&
                              (primarySections.isNotEmpty ||
                                  workspaceSections.isNotEmpty ||
                                  toolSections.isNotEmpty))
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Container(
                                height: 1,
                                color: palette.chromeStroke.withValues(
                                  alpha: 0.9,
                                ),
                              ),
                            ),
                          if (primarySections.isNotEmpty)
                            _SidebarSectionGroup(
                              sections: primarySections,
                              currentSection: currentSection,
                              collapsed: isCollapsed,
                              emphasis: _SidebarItemEmphasis.primary,
                              favoriteDestinations: favoriteDestinations,
                              onToggleFavorite: onToggleFavorite,
                              onOpenHome: onOpenHome,
                              onSectionChanged: onSectionChanged,
                            ),
                          if (primarySections.isNotEmpty &&
                              workspaceSections.isNotEmpty)
                            const SizedBox(height: 6),
                          if (workspaceSections.isNotEmpty)
                            _SidebarSectionGroup(
                              title: appText('工作区', 'Workspace'),
                              sections: workspaceSections,
                              currentSection: currentSection,
                              collapsed: isCollapsed,
                              emphasis: _SidebarItemEmphasis.secondary,
                              favoriteDestinations: favoriteDestinations,
                              onToggleFavorite: onToggleFavorite,
                              onOpenHome: onOpenHome,
                              onSectionChanged: onSectionChanged,
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (toolSections.isNotEmpty)
                    _SidebarSectionGroup(
                      title: appText('工具', 'Tools'),
                      sections: toolSections,
                      currentSection: currentSection,
                      collapsed: isCollapsed,
                      emphasis: _SidebarItemEmphasis.secondary,
                      favoriteDestinations: favoriteDestinations,
                      onToggleFavorite: onToggleFavorite,
                      onOpenHome: onOpenHome,
                      onSectionChanged: onSectionChanged,
                    ),
                  if (toolSections.isNotEmpty) const SizedBox(height: 6),
                  SidebarFooter(
                    isCollapsed: isCollapsed,
                    currentSection: currentSection,
                    appLanguage: appLanguage,
                    themeMode: themeMode,
                    onToggleLanguage: onToggleLanguage,
                    onOpenThemeToggle: onOpenThemeToggle,
                    onOpenSettings: () =>
                        onSectionChanged(WorkspaceDestination.settings),
                    showSettingsButton:
                        availableDestinations == null ||
                        availableDestinations!.contains(
                          WorkspaceDestination.settings,
                        ),
                    favoriteDestinations: favoriteDestinations,
                    onToggleFavorite: onToggleFavorite,
                    sidebarState: sidebarState,
                    onCycleSidebarState: onCycleSidebarState,
                    onOpenAccount: onOpenAccount,
                    showAccountButton:
                        availableDestinations == null ||
                        availableDestinations!.contains(
                          WorkspaceDestination.account,
                        ),
                    accountName: accountName,
                    accountSubtitle: accountSubtitle,
                    accountWorkspaceFollowed: accountWorkspaceFollowed,
                    onToggleAccountWorkspaceFollowed:
                        onToggleAccountWorkspaceFollowed,
                    accountSelected:
                        currentSection == WorkspaceDestination.account,
                    currentSettingsTab: currentSettingsTab,
                    availableSettingsTabs: availableSettingsTabs,
                    onSettingsTabChanged: onSettingsTabChanged,
                    showCollapseControl: showCollapseControl,
                    onOpenOnlineWorkspace: onOpenOnlineWorkspace,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<WorkspaceDestination> _filterSections(
    List<WorkspaceDestination> sections,
  ) {
    final allowed = availableDestinations;
    if (allowed == null) {
      return sections;
    }
    return sections.where(allowed.contains).toList(growable: false);
  }
}

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
    required this.items,
    required this.skillCount,
    this.onRefreshTasks,
    this.onCreateTask,
    this.onSelectTask,
    this.onArchiveTask,
    this.onRenameTask,
  });

  final List<SidebarTaskItem> items;
  final int skillCount;
  final Future<void> Function()? onRefreshTasks;
  final Future<void> Function()? onCreateTask;
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
    final runningCount = filteredItems.where((item) => item.pending).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
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
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_query.isNotEmpty)
                    IconButton(
                      tooltip: appText('清除搜索', 'Clear search'),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _query = '';
                        });
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
                  if (widget.onRefreshTasks != null)
                    IconButton(
                      key: const Key('workspace-sidebar-task-refresh'),
                      tooltip: appText('刷新任务', 'Refresh tasks'),
                      onPressed: () async {
                        await widget.onRefreshTasks!();
                      },
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: FilledButton.tonalIcon(
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
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _SidebarMetaPill(
                icon: Icons.play_circle_outline_rounded,
                label: '${appText('运行中', 'Running')} $runningCount',
              ),
              _SidebarMetaPill(
                icon: Icons.forum_outlined,
                label: '${appText('当前', 'Current')} ${filteredItems.length}',
              ),
              _SidebarMetaPill(
                icon: Icons.auto_awesome_rounded,
                label: '${appText('技能', 'Skills')} ${widget.skillCount}',
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
          child: Row(
            children: [
              Text(appText('任务列表', 'Task list'), style: theme.textTheme.titleSmall),
              const SizedBox(width: 6),
              Text(
                '${filteredItems.length}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: palette.textMuted,
                ),
              ),
            ],
          ),
        ),
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
                  onArchive: widget.onArchiveTask == null || item.pending
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
                          await widget.onRenameTask!(item.sessionKey, renamed);
                        },
                ),
              ),
          ],
          const SizedBox(height: 4),
        ],
      ],
    );
  }

  List<SidebarTaskItem> _filteredItems() {
    if (_query.isEmpty) {
      return widget.items;
    }
    return widget.items.where((item) {
      final haystack = '${item.title}\n${item.preview}\n${item.sessionKey}'
          .toLowerCase();
      return haystack.contains(_query);
    }).toList(growable: false);
  }

  List<_SidebarTaskGroup> _groupedItems(List<SidebarTaskItem> items) {
    final grouped = <AssistantExecutionTarget, List<SidebarTaskItem>>{
      for (final target in AssistantExecutionTarget.values)
        target: <SidebarTaskItem>[],
    };
    for (final item in items) {
      grouped[item.executionTarget]!.add(item);
    }
    return AssistantExecutionTarget.values
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
    _expandedTargets.addAll(AssistantExecutionTarget.values);
  }
}

class _SidebarTaskGroup {
  const _SidebarTaskGroup({
    required this.executionTarget,
    required this.items,
  });

  final AssistantExecutionTarget executionTarget;
  final List<SidebarTaskItem> items;
}

class _SidebarMetaPill extends StatelessWidget {
  const _SidebarMetaPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: palette.surfacePrimary,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.strokeSoft),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: palette.textSecondary),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: palette.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
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
        key: ValueKey<String>('workspace-sidebar-task-group-${executionTarget.name}'),
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
                  executionTarget.label,
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
            color: item.isCurrent ? palette.surfaceSecondary : Colors.transparent,
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
    AssistantExecutionTarget.singleAgent => Icons.hub_outlined,
    AssistantExecutionTarget.local => Icons.computer_outlined,
    AssistantExecutionTarget.remote => Icons.cloud_outlined,
  };
}

class SidebarHeader extends StatelessWidget {
  const SidebarHeader({super.key, required this.isCollapsed, this.onTap});

  final bool isCollapsed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = _SidebarHeaderChevron(
      size: isCollapsed ? 36 : 28,
      borderRadius: isCollapsed ? 10 : 8,
    );
    final alignedContent = Align(
      alignment: Alignment.centerRight,
      child: content,
    );

    if (onTap == null) {
      return alignedContent;
    }

    return Tooltip(
      message: appText('展开导航', 'Expand sidebar'),
      child: Align(
        alignment: Alignment.centerRight,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.button),
          onTap: onTap,
          child: Padding(padding: EdgeInsets.zero, child: content),
        ),
      ),
    );
  }
}

class _SidebarHeaderChevron extends StatelessWidget {
  const _SidebarHeaderChevron({required this.size, required this.borderRadius});

  final double size;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: palette.surfacePrimary,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: palette.strokeSoft),
      ),
      child: Center(
        child: Icon(
          Icons.chevron_right_rounded,
          size: size * 0.72,
          color: palette.textSecondary,
        ),
      ),
    );
  }
}

class _SidebarSectionGroup extends StatelessWidget {
  const _SidebarSectionGroup({
    this.title,
    required this.sections,
    required this.currentSection,
    required this.collapsed,
    required this.emphasis,
    required this.favoriteDestinations,
    this.onToggleFavorite,
    this.onOpenHome,
    required this.onSectionChanged,
  });

  final String? title;
  final List<WorkspaceDestination> sections;
  final WorkspaceDestination currentSection;
  final bool collapsed;
  final _SidebarItemEmphasis emphasis;
  final Set<AssistantFocusEntry> favoriteDestinations;
  final Future<void> Function(AssistantFocusEntry section)? onToggleFavorite;
  final VoidCallback? onOpenHome;
  final ValueChanged<WorkspaceDestination> onSectionChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!collapsed && title != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
            child: Text(
              title!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: palette.textMuted,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.28,
              ),
            ),
          ),
        ],
        ...sections.map((section) {
          final useHomeShortcut =
              currentSection == WorkspaceDestination.settings &&
              section == WorkspaceDestination.assistant;
          final focusEntry = switch (section) {
            WorkspaceDestination.tasks => AssistantFocusEntry.tasks,
            WorkspaceDestination.skills => AssistantFocusEntry.skills,
            WorkspaceDestination.nodes => AssistantFocusEntry.nodes,
            WorkspaceDestination.agents => AssistantFocusEntry.agents,
            WorkspaceDestination.mcpServer => AssistantFocusEntry.mcpServer,
            WorkspaceDestination.clawHub => AssistantFocusEntry.clawHub,
            WorkspaceDestination.secrets => AssistantFocusEntry.secrets,
            WorkspaceDestination.aiGateway => AssistantFocusEntry.aiGateway,
            WorkspaceDestination.settings => AssistantFocusEntry.settings,
            WorkspaceDestination.assistant ||
            WorkspaceDestination.account => null,
          };
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
            child: _SidebarNavItem(
              section: section,
              selected: currentSection == section,
              collapsed: collapsed,
              emphasis: emphasis,
              favorite:
                  focusEntry != null &&
                  favoriteDestinations.contains(focusEntry),
              showFavoriteToggle: false,
              labelOverride: useHomeShortcut
                  ? appText('回到 APP首页', 'Back to app home')
                  : null,
              onToggleFavorite: onToggleFavorite == null || focusEntry == null
                  ? null
                  : () async {
                      await onToggleFavorite!(focusEntry);
                    },
              onTap: useHomeShortcut && onOpenHome != null
                  ? onOpenHome!
                  : () => onSectionChanged(section),
            ),
          );
        }),
      ],
    );
  }
}

class _SidebarNavItem extends StatefulWidget {
  const _SidebarNavItem({
    required this.section,
    required this.selected,
    required this.collapsed,
    required this.emphasis,
    required this.favorite,
    required this.showFavoriteToggle,
    this.labelOverride,
    this.onToggleFavorite,
    required this.onTap,
  });

  final WorkspaceDestination section;
  final bool selected;
  final bool collapsed;
  final _SidebarItemEmphasis emphasis;
  final bool favorite;
  final bool showFavoriteToggle;
  final String? labelOverride;
  final Future<void> Function()? onToggleFavorite;
  final VoidCallback onTap;

  @override
  State<_SidebarNavItem> createState() => _SidebarNavItemState();
}

class _SidebarNavItemState extends State<_SidebarNavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    final label = widget.labelOverride ?? _sectionLabel(widget.section);
    final isPrimary = widget.emphasis == _SidebarItemEmphasis.primary;
    final background = widget.selected
        ? palette.surfacePrimary
        : _hovered
        ? palette.chromeSurfacePressed
        : Colors.transparent;
    final iconColor = widget.selected
        ? palette.textPrimary
        : palette.textSecondary;
    final height = isPrimary ? 36.0 : 32.0;
    final radius = AppRadius.button;

    return Tooltip(
      message: widget.collapsed ? label : '',
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            color: widget.selected || _hovered
                ? background.withValues(alpha: widget.selected ? 1 : 0.96)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: widget.selected || _hovered
                  ? palette.strokeSoft
                  : Colors.transparent,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(radius),
              onTap: widget.onTap,
              child: Container(
                height: height,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: widget.collapsed
                    ? Center(
                        child: Icon(
                          _sectionIcon(widget.section, active: widget.selected),
                          size: AppSizes.sidebarIconSize,
                          color: iconColor,
                        ),
                      )
                    : Row(
                        children: [
                          SizedBox(
                            width: 20,
                            child: Icon(
                              _sectionIcon(
                                widget.section,
                                active: widget.selected,
                              ),
                              size: AppSizes.sidebarIconSize,
                              color: iconColor,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  (isPrimary
                                          ? theme.textTheme.titleMedium
                                          : theme.textTheme.labelLarge)
                                      ?.copyWith(
                                        color: widget.selected
                                            ? palette.textPrimary
                                            : palette.textSecondary,
                                        fontWeight: isPrimary
                                            ? FontWeight.w600
                                            : FontWeight.w500,
                                        letterSpacing: isPrimary ? 0.02 : 0,
                                      ),
                            ),
                          ),
                          if (widget.showFavoriteToggle)
                            IconButton(
                              key: ValueKey<String>(
                                'sidebar-favorite-${widget.section.name}',
                              ),
                              tooltip: widget.favorite
                                  ? appText('取消关注', 'Remove from focused panel')
                                  : appText('加入关注', 'Add to focused panel'),
                              visualDensity: VisualDensity.compact,
                              splashRadius: 12,
                              onPressed: () async {
                                await widget.onToggleFavorite?.call();
                              },
                              icon: Icon(
                                widget.favorite
                                    ? Icons.star_rounded
                                    : Icons.star_outline_rounded,
                                size: 18,
                                color: widget.favorite
                                    ? palette.accent
                                    : palette.textMuted,
                              ),
                            ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  IconData _sectionIcon(WorkspaceDestination section, {required bool active}) {
    return switch (section) {
      WorkspaceDestination.assistant =>
        active ? Icons.chat_bubble_rounded : Icons.chat_bubble_outline_rounded,
      WorkspaceDestination.tasks =>
        active ? Icons.layers_rounded : Icons.layers_outlined,
      WorkspaceDestination.skills =>
        active ? Icons.auto_awesome_rounded : Icons.auto_awesome_outlined,
      WorkspaceDestination.nodes =>
        active ? Icons.developer_board_rounded : Icons.developer_board_outlined,
      WorkspaceDestination.agents =>
        active ? Icons.hub_rounded : Icons.hub_outlined,
      WorkspaceDestination.mcpServer =>
        active ? Icons.dns_rounded : Icons.dns_outlined,
      WorkspaceDestination.clawHub =>
        active ? Icons.extension_rounded : Icons.extension_outlined,
      WorkspaceDestination.secrets =>
        active ? Icons.key_rounded : Icons.key_outlined,
      WorkspaceDestination.aiGateway =>
        active ? Icons.smart_toy_rounded : Icons.smart_toy_outlined,
      WorkspaceDestination.settings =>
        active ? Icons.settings_rounded : Icons.settings_outlined,
      WorkspaceDestination.account =>
        active ? Icons.account_circle_rounded : Icons.account_circle_outlined,
    };
  }

  String _sectionLabel(WorkspaceDestination section) {
    return switch (section) {
      WorkspaceDestination.assistant => appText('新对话', 'New conversation'),
      WorkspaceDestination.tasks => appText('自动化', 'Automation'),
      WorkspaceDestination.skills => appText('技能', 'Skills'),
      WorkspaceDestination.nodes => appText('节点', 'Nodes'),
      WorkspaceDestination.agents => appText('代理', 'Agents'),
      WorkspaceDestination.mcpServer => 'MCP Hub',
      WorkspaceDestination.clawHub => 'ClawHub',
      WorkspaceDestination.secrets => appText('密钥', 'Secrets'),
      WorkspaceDestination.aiGateway => 'LLM API',
      WorkspaceDestination.settings => appText('设置', 'Settings'),
      WorkspaceDestination.account => appText('账户', 'Account'),
    };
  }
}

class SidebarFooter extends StatelessWidget {
  const SidebarFooter({
    super.key,
    required this.isCollapsed,
    required this.currentSection,
    required this.appLanguage,
    required this.themeMode,
    required this.onToggleLanguage,
    required this.onOpenThemeToggle,
    required this.onOpenSettings,
    required this.showSettingsButton,
    required this.favoriteDestinations,
    this.onToggleFavorite,
    required this.sidebarState,
    required this.onCycleSidebarState,
    required this.onOpenAccount,
    required this.showAccountButton,
    required this.accountName,
    required this.accountSubtitle,
    required this.accountWorkspaceFollowed,
    required this.accountSelected,
    required this.currentSettingsTab,
    required this.availableSettingsTabs,
    this.onSettingsTabChanged,
    required this.showCollapseControl,
    this.onToggleAccountWorkspaceFollowed,
    this.onOpenOnlineWorkspace,
  });

  final bool isCollapsed;
  final WorkspaceDestination currentSection;
  final AppLanguage appLanguage;
  final ThemeMode themeMode;
  final VoidCallback onToggleLanguage;
  final VoidCallback onOpenThemeToggle;
  final VoidCallback onOpenSettings;
  final bool showSettingsButton;
  final Set<AssistantFocusEntry> favoriteDestinations;
  final Future<void> Function(AssistantFocusEntry entry)? onToggleFavorite;
  final AppSidebarState sidebarState;
  final VoidCallback onCycleSidebarState;
  final VoidCallback onOpenAccount;
  final bool showAccountButton;
  final String accountName;
  final String accountSubtitle;
  final bool accountWorkspaceFollowed;
  final bool accountSelected;
  final SettingsTab? currentSettingsTab;
  final List<SettingsTab> availableSettingsTabs;
  final ValueChanged<SettingsTab>? onSettingsTabChanged;
  final bool showCollapseControl;
  final Future<void> Function()? onToggleAccountWorkspaceFollowed;
  final VoidCallback? onOpenOnlineWorkspace;

  bool get showSettingsRail =>
      showSettingsButton &&
      currentSection == WorkspaceDestination.settings &&
      currentSettingsTab != null &&
      availableSettingsTabs.isNotEmpty &&
      onSettingsTabChanged != null;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final themeToggleTooltip = chromeThemeToggleTooltip(themeMode);

    if (isCollapsed) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 1,
            color: palette.chromeStroke.withValues(alpha: 0.9),
          ),
          const SizedBox(height: 6),
          if (showAccountButton) ...[
            ChromeIconActionButton(
              icon: currentSection == WorkspaceDestination.account
                  ? Icons.account_circle_rounded
                  : Icons.account_circle_outlined,
              tooltip: appText('打开账号页', 'Open account'),
              onPressed: onOpenAccount,
            ),
            const SizedBox(height: 6),
          ],
          ChromeLanguageActionButton(
            appLanguage: appLanguage,
            compact: true,
            tooltip: appText('切换语言', 'Toggle language'),
            onPressed: onToggleLanguage,
            favorite: favoriteDestinations.contains(
              AssistantFocusEntry.language,
            ),
            showFavoriteToggle: onToggleFavorite != null,
            favoriteButtonKey: const ValueKey<String>(
              'sidebar-favorite-language',
            ),
            onToggleFavorite: onToggleFavorite == null
                ? null
                : () => onToggleFavorite!(AssistantFocusEntry.language),
          ),
          const SizedBox(height: 6),
          ChromeIconActionButton(
            icon: chromeThemeToggleIcon(themeMode),
            tooltip: themeToggleTooltip,
            onPressed: onOpenThemeToggle,
            favorite: favoriteDestinations.contains(AssistantFocusEntry.theme),
            showFavoriteToggle: onToggleFavorite != null,
            favoriteButtonKey: const ValueKey<String>('sidebar-favorite-theme'),
            onToggleFavorite: onToggleFavorite == null
                ? null
                : () => onToggleFavorite!(AssistantFocusEntry.theme),
          ),
          const SizedBox(height: AppSpacing.xs),
          if (showCollapseControl) ...[
            ChromeIconActionButton(
              icon: _sidebarStateIcon(sidebarState),
              tooltip: _sidebarStateLabel(sidebarState),
              onPressed: onCycleSidebarState,
            ),
            const SizedBox(height: 6),
          ],
          if (showSettingsButton) ...[
            ChromeIconActionButton(
              icon: Icons.tune_rounded,
              tooltip: appText('设置', 'Settings'),
              onPressed: onOpenSettings,
            ),
            const SizedBox(height: 6),
          ],
          if (showSettingsRail) ...[
            ...availableSettingsTabs.map(
              (tab) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _SidebarSettingsCompactButton(
                  tab: tab,
                  selected: tab == currentSettingsTab,
                  onPressed: () => onSettingsTabChanged!(tab),
                ),
              ),
            ),
          ],
          if (onOpenOnlineWorkspace != null) ...[
            ChromeIconActionButton(
              icon: Icons.open_in_new_rounded,
              tooltip: appText('打开在线版', 'Open online workspace'),
              onPressed: onOpenOnlineWorkspace!,
            ),
            const SizedBox(height: 6),
          ],
          if (showAccountButton)
            _SidebarAccountTile(
              selected: accountSelected,
              onTap: onOpenAccount,
              name: accountName,
              subtitle: accountSubtitle,
              workspaceFollowed: accountWorkspaceFollowed,
              onToggleWorkspaceFollowed: onToggleAccountWorkspaceFollowed,
              onlineActionLabel: appText('在线版', 'Online'),
              onOpenOnlineWorkspace: onOpenOnlineWorkspace,
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 1,
          color: palette.chromeStroke.withValues(alpha: 0.9),
        ),
        const SizedBox(height: AppSpacing.xs),
        if (showAccountButton) ...[
          _SidebarNavItem(
            section: WorkspaceDestination.account,
            selected: currentSection == WorkspaceDestination.account,
            collapsed: false,
            emphasis: _SidebarItemEmphasis.secondary,
            favorite: false,
            showFavoriteToggle: false,
            onTap: onOpenAccount,
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
        if (showSettingsButton) ...[
          _SidebarNavItem(
            section: WorkspaceDestination.settings,
            selected: currentSection == WorkspaceDestination.settings,
            collapsed: false,
            emphasis: _SidebarItemEmphasis.secondary,
            favorite: false,
            showFavoriteToggle: false,
            onTap: onOpenSettings,
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
        if (showSettingsRail) ...[
          Container(
            margin: const EdgeInsets.only(bottom: AppSpacing.xs),
            padding: const EdgeInsets.all(AppSpacing.xxs),
            decoration: BoxDecoration(
              color: palette.chromeSurface,
              borderRadius: BorderRadius.circular(AppRadius.button),
              border: Border.all(color: palette.strokeSoft),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: availableSettingsTabs
                  .map(
                    (tab) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
                      child: _SidebarSettingsNavItem(
                        tab: tab,
                        selected: tab == currentSettingsTab,
                        onTap: () => onSettingsTabChanged!(tab),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        ],
        Row(
          children: [
            Expanded(
              child: ChromeLanguageActionButton(
                appLanguage: appLanguage,
                compact: false,
                tooltip: appText('切换语言', 'Toggle language'),
                onPressed: onToggleLanguage,
                favorite: favoriteDestinations.contains(
                  AssistantFocusEntry.language,
                ),
                showFavoriteToggle: onToggleFavorite != null,
                favoriteButtonKey: const ValueKey<String>(
                  'sidebar-favorite-language',
                ),
                onToggleFavorite: onToggleFavorite == null
                    ? null
                    : () => onToggleFavorite!(AssistantFocusEntry.language),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            ChromeIconActionButton(
              icon: chromeThemeToggleIcon(themeMode),
              tooltip: themeToggleTooltip,
              onPressed: onOpenThemeToggle,
              favorite: favoriteDestinations.contains(
                AssistantFocusEntry.theme,
              ),
              showFavoriteToggle: onToggleFavorite != null,
              favoriteButtonKey: const ValueKey<String>(
                'sidebar-favorite-theme',
              ),
              onToggleFavorite: onToggleFavorite == null
                  ? null
                  : () => onToggleFavorite!(AssistantFocusEntry.theme),
            ),
            const SizedBox(width: AppSpacing.xs),
            if (showCollapseControl)
              ChromeIconActionButton(
                icon: _sidebarStateIcon(sidebarState),
                tooltip: _sidebarStateLabel(sidebarState),
                onPressed: onCycleSidebarState,
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        if (showAccountButton)
          _SidebarAccountTile(
            selected: accountSelected,
            onTap: onOpenAccount,
            name: accountName,
            subtitle: accountSubtitle,
            workspaceFollowed: accountWorkspaceFollowed,
            onToggleWorkspaceFollowed: onToggleAccountWorkspaceFollowed,
            onlineActionLabel: appText('在线版', 'Online'),
            onOpenOnlineWorkspace: onOpenOnlineWorkspace,
          ),
      ],
    );
  }

  IconData _sidebarStateIcon(AppSidebarState state) {
    return switch (state) {
      AppSidebarState.expanded => Icons.keyboard_double_arrow_left_rounded,
      AppSidebarState.collapsed => Icons.keyboard_double_arrow_right_rounded,
      AppSidebarState.hidden => Icons.keyboard_double_arrow_right_rounded,
    };
  }

  String _sidebarStateLabel(AppSidebarState state) {
    return switch (state) {
      AppSidebarState.expanded => appText('收起侧边栏', 'Collapse sidebar'),
      AppSidebarState.collapsed => appText('展开侧边栏', 'Expand sidebar'),
      AppSidebarState.hidden => appText('展开侧边栏', 'Expand sidebar'),
    };
  }
}

enum _SidebarItemEmphasis { primary, secondary }

IconData _sidebarSettingsTabIcon(SettingsTab tab) {
  return switch (tab) {
    SettingsTab.general => Icons.tune_rounded,
    SettingsTab.workspace => Icons.folder_open_rounded,
    SettingsTab.gateway => Icons.settings_ethernet_rounded,
    SettingsTab.agents => Icons.smart_toy_rounded,
    SettingsTab.appearance => Icons.palette_outlined,
    SettingsTab.diagnostics => Icons.monitor_heart_outlined,
    SettingsTab.experimental => Icons.science_outlined,
    SettingsTab.about => Icons.info_outline_rounded,
  };
}

class _SidebarSettingsCompactButton extends StatefulWidget {
  const _SidebarSettingsCompactButton({
    required this.tab,
    required this.selected,
    required this.onPressed,
  });

  final SettingsTab tab;
  final bool selected;
  final VoidCallback onPressed;

  @override
  State<_SidebarSettingsCompactButton> createState() =>
      _SidebarSettingsCompactButtonState();
}

class _SidebarSettingsCompactButtonState
    extends State<_SidebarSettingsCompactButton> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final active = widget.selected || hovered;
    final background = active
        ? palette.chromeSurfacePressed
        : palette.chromeSurface;

    return Tooltip(
      message: widget.tab.label,
      child: MouseRegion(
        onEnter: (_) => setState(() => hovered = true),
        onExit: (_) => setState(() => hovered = false),
        child: AnimatedContainer(
          key: ValueKey<String>('sidebar-settings-tab-${widget.tab.name}'),
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                palette.chromeHighlight.withValues(alpha: active ? 0.95 : 0.88),
                background,
              ],
            ),
            borderRadius: BorderRadius.circular(AppRadius.button),
            border: Border.all(
              color: active ? palette.chromeStroke : palette.strokeSoft,
            ),
            boxShadow: [
              active ? palette.chromeShadowLift : palette.chromeShadowAmbient,
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.button),
              onTap: widget.onPressed,
              child: SizedBox(
                height: AppSizes.sidebarItemHeight,
                child: Center(
                  child: Icon(
                    _sidebarSettingsTabIcon(widget.tab),
                    size: AppSizes.sidebarIconSize,
                    color: active
                        ? palette.textPrimary
                        : palette.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarSettingsNavItem extends StatefulWidget {
  const _SidebarSettingsNavItem({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final SettingsTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_SidebarSettingsNavItem> createState() => _SidebarSettingsNavItemState();
}

class _SidebarSettingsNavItemState extends State<_SidebarSettingsNavItem> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    final active = widget.selected || hovered;

    return MouseRegion(
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: AnimatedContainer(
        key: ValueKey<String>('sidebar-settings-tab-${widget.tab.name}'),
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          gradient: active
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    palette.chromeHighlight.withValues(alpha: 0.95),
                    palette.chromeSurface,
                  ],
                )
              : null,
          color: active ? null : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.button),
          border: Border.all(
            color: active ? palette.chromeStroke : Colors.transparent,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.button),
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.compact,
              ),
              child: Row(
                children: [
                  Icon(
                    _sidebarSettingsTabIcon(widget.tab),
                    size: 18,
                    color: active
                        ? palette.textPrimary
                        : palette.textSecondary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      widget.tab.label,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: active
                            ? palette.textPrimary
                            : palette.textSecondary,
                        fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarAccountTile extends StatefulWidget {
  const _SidebarAccountTile({
    required this.selected,
    required this.onTap,
    required this.name,
    required this.subtitle,
    required this.workspaceFollowed,
    this.onToggleWorkspaceFollowed,
    this.onlineActionLabel,
    this.onOpenOnlineWorkspace,
  });

  final bool selected;
  final VoidCallback onTap;
  final String name;
  final String subtitle;
  final bool workspaceFollowed;
  final Future<void> Function()? onToggleWorkspaceFollowed;
  final String? onlineActionLabel;
  final VoidCallback? onOpenOnlineWorkspace;

  @override
  State<_SidebarAccountTile> createState() => _SidebarAccountTileState();
}

class _SidebarAccountTileState extends State<_SidebarAccountTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final background = widget.selected
        ? palette.chromeSurface
        : _hovered
        ? palette.chromeSurfacePressed
        : Colors.transparent;
    final initial = widget.name.trim().isEmpty
        ? 'X'
        : widget.name.trim().substring(0, 1).toUpperCase();
    final statusLabel = _statusLabel();
    final List<PopupMenuEntry<_AccountMenuAction>> accountMenuItems =
        <PopupMenuEntry<_AccountMenuAction>>[];
    accountMenuItems.addAll([
      PopupMenuItem<_AccountMenuAction>(
        enabled: false,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 220),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: palette.accentMuted,
                    child: Text(
                      initial,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        _AccountStatusBadge(label: statusLabel),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: palette.chromeSurface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: palette.strokeSoft),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.subtitle.trim().isEmpty
                            ? appText('体验版', 'Preview')
                            : widget.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _AccountUpgradePill(label: appText('升级', 'Upgrade')),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      PopupMenuItem<_AccountMenuAction>(
        value: _AccountMenuAction.account,
        child: _AccountMenuItemRow(
          icon: Icons.person_outline_rounded,
          label: appText('打开账号页', 'Open account'),
        ),
      ),
    ]);
    if (widget.onOpenOnlineWorkspace != null &&
        widget.onlineActionLabel != null) {
      accountMenuItems.add(
        PopupMenuItem<_AccountMenuAction>(
          value: _AccountMenuAction.online,
          child: _AccountMenuItemRow(
            icon: Icons.open_in_new_rounded,
            label: widget.onlineActionLabel!,
          ),
        ),
      );
    }
    final tileChildren = <Widget>[
      Expanded(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            color: widget.selected || _hovered
                ? background
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.button),
            border: Border.all(
              color: widget.selected || _hovered
                  ? palette.strokeSoft
                  : Colors.transparent,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: Theme(
              data: Theme.of(context).copyWith(
                popupMenuTheme: PopupMenuThemeData(
                  color: palette.surfacePrimary.withValues(alpha: 0.98),
                  surfaceTintColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: BorderSide(color: palette.chromeStroke),
                  ),
                  textStyle: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: palette.textPrimary),
                ),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.button),
                onTap: widget.onTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.max,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: palette.accentMuted,
                        child: Text(initial),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.subtitle.trim().isEmpty
                                  ? statusLabel
                                  : widget.subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      PopupMenuButton<_AccountMenuAction>(
                        tooltip: appText('更多操作', 'More actions'),
                        padding: EdgeInsets.zero,
                        position: PopupMenuPosition.under,
                        offset: const Offset(0, 8),
                        elevation: 10,
                        splashRadius: 18,
                        onSelected: (action) {
                          if (action == _AccountMenuAction.account) {
                            widget.onTap();
                            return;
                          }
                          widget.onOpenOnlineWorkspace?.call();
                        },
                        itemBuilder: (context) => accountMenuItems,
                        child: _AccountCircleActionButton(
                          icon: Icons.unfold_more_rounded,
                          tooltip: appText('更多操作', 'More actions'),
                          iconColor: palette.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ];
    if (widget.onToggleWorkspaceFollowed != null) {
      tileChildren.add(const SizedBox(width: AppSpacing.xs));
      tileChildren.add(
        _AccountCircleActionButton(
          key: const ValueKey<String>('sidebar-account-follow'),
          icon: widget.workspaceFollowed
              ? Icons.star_rounded
              : Icons.star_outline_rounded,
          tooltip: widget.workspaceFollowed
              ? appText('取消关注工作区', 'Unfollow workspace')
              : appText('关注工作区', 'Follow workspace'),
          selected: widget.workspaceFollowed,
          onTap: () {
            widget.onToggleWorkspaceFollowed?.call();
          },
        ),
      );
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Row(children: tileChildren),
      ),
    );
  }

  String _statusLabel() {
    final lowerName = widget.name.trim().toLowerCase();
    final isLocalIdentity =
        lowerName.contains('local') ||
        lowerName.contains('web') ||
        widget.subtitle.trim().isEmpty;
    return isLocalIdentity
        ? appText('未登录', 'Not signed in')
        : appText('已登录', 'Signed in');
  }
}

class _AccountCircleActionButton extends StatefulWidget {
  const _AccountCircleActionButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.iconColor,
    this.selected = false,
    this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final Color? iconColor;
  final bool selected;
  final VoidCallback? onTap;

  @override
  State<_AccountCircleActionButton> createState() =>
      _AccountCircleActionButtonState();
}

class _AccountCircleActionButtonState
    extends State<_AccountCircleActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final resolvedBackground = _hovered
        ? palette.chromeSurfacePressed
        : palette.chromeSurface;

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                palette.chromeHighlight.withValues(
                  alpha: _hovered || widget.selected ? 0.96 : 0.88,
                ),
                resolvedBackground,
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: widget.selected ? palette.accent : palette.chromeStroke,
            ),
            boxShadow: [
              _hovered || widget.selected
                  ? palette.chromeShadowLift
                  : palette.chromeShadowAmbient,
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: widget.onTap,
              child: Center(
                child: Icon(
                  widget.icon,
                  size: 17,
                  color:
                      widget.iconColor ??
                      (widget.selected
                          ? palette.accent
                          : palette.textSecondary),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _AccountMenuAction { account, online }

class _AccountMenuItemRow extends StatelessWidget {
  const _AccountMenuItemRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      children: [
        Icon(icon, size: 18, color: palette.textSecondary),
        const SizedBox(width: 10),
        Expanded(child: Text(label)),
      ],
    );
  }
}

class _AccountStatusBadge extends StatelessWidget {
  const _AccountStatusBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: palette.accentMuted,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: palette.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _AccountUpgradePill extends StatelessWidget {
  const _AccountUpgradePill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: const BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.all(Radius.circular(999)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
