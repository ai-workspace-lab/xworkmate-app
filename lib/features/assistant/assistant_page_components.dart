// ignore_for_file: unused_import, unnecessary_import

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:path_provider/path_provider.dart';
import 'package:super_clipboard/super_clipboard.dart';
import '../../app/app_controller.dart';
import '../../app/app_metadata.dart';
import '../../app/ui_feature_manifest.dart';
import '../../i18n/app_language.dart';
import '../../models/app_models.dart';
import '../../runtime/multi_agent_orchestrator.dart';
import '../../runtime/runtime_models.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../widgets/assistant_focus_panel.dart';
import '../../widgets/assistant_artifact_sidebar.dart';
import '../../widgets/desktop_workspace_scaffold.dart';
import '../../widgets/pane_resize_handle.dart';
import '../../widgets/surface_card.dart';
import 'assistant_page_main.dart';
import 'assistant_page_composer_bar.dart';
import 'assistant_page_composer_state_helpers.dart';
import 'assistant_page_composer_support.dart';
import 'assistant_page_tooltip_labels.dart';
import 'assistant_page_message_widgets.dart';
import 'assistant_page_task_models.dart';
import 'assistant_page_composer_skill_models.dart';
import 'assistant_page_composer_skill_picker.dart';
import 'assistant_page_composer_clipboard.dart';
import 'assistant_page_components_core.dart';

class AssistantTaskRailInternal extends StatefulWidget {
  const AssistantTaskRailInternal({
    super.key,
    required this.controller,
    required this.tasks,
    required this.query,
    required this.searchController,
    required this.onQueryChanged,
    required this.onClearQuery,
    required this.onRefreshTasks,
    required this.onCreateTask,
    required this.onSelectTask,
    required this.onArchiveTask,
    required this.onRenameTask,
  });

  final AppController controller;
  final List<AssistantTaskEntryInternal> tasks;
  final String query;
  final TextEditingController searchController;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onClearQuery;
  final Future<void> Function() onRefreshTasks;
  final Future<void> Function() onCreateTask;
  final Future<void> Function(String sessionKey) onSelectTask;
  final Future<void> Function(String sessionKey) onArchiveTask;
  final Future<void> Function(AssistantTaskEntryInternal entry) onRenameTask;

  @override
  State<AssistantTaskRailInternal> createState() =>
      AssistantTaskRailStateInternal();
}

class AssistantTaskRailStateInternal extends State<AssistantTaskRailInternal> {
  final Set<AssistantExecutionTarget> expandedGroupsInternal =
      <AssistantExecutionTarget>{};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    final tasks = widget.tasks;
    final groupedTasks = groupTasksForRailInternal(
      tasks,
      widget.controller
          .visibleAssistantExecutionTargets(const <AssistantExecutionTarget>[
            AssistantExecutionTarget.singleAgent,
            AssistantExecutionTarget.local,
            AssistantExecutionTarget.remote,
          ]),
    );
    final runningCount = tasks
        .where((task) => normalizedTaskStatusInternal(task.status) == 'running')
        .length;
    final openCount = tasks
        .where((task) => normalizedTaskStatusInternal(task.status) == 'open')
        .length;

    return SurfaceCard(
      borderRadius: 0,
      padding: EdgeInsets.zero,
      tone: SurfaceCardTone.chrome,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('assistant-task-search'),
                        controller: widget.searchController,
                        onChanged: widget.onQueryChanged,
                        decoration: InputDecoration(
                          hintText: appText('搜索任务', 'Search tasks'),
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: widget.query.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: appText('清除搜索', 'Clear search'),
                                  onPressed: widget.onClearQuery,
                                  icon: const Icon(Icons.close_rounded),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      key: const Key('assistant-task-refresh'),
                      tooltip: appText('刷新任务', 'Refresh tasks'),
                      onPressed: () async {
                        await widget.onRefreshTasks();
                      },
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    key: const Key('assistant-new-task-button'),
                    onPressed: () async {
                      await widget.onCreateTask();
                    },
                    icon: const Icon(Icons.edit_note_rounded),
                    label: Text(appText('新对话', 'New conversation')),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 32),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    MetaPillInternal(
                      label: '${appText('运行中', 'Running')} $runningCount',
                      icon: Icons.play_circle_outline_rounded,
                    ),
                    MetaPillInternal(
                      label: '${appText('当前', 'Open')} $openCount',
                      icon: Icons.forum_outlined,
                    ),
                    MetaPillInternal(
                      label:
                          '${appText('技能', 'Skills')} ${widget.controller.currentAssistantSkillCount}',
                      icon: Icons.auto_awesome_rounded,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Divider(height: 1, color: palette.strokeSoft),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
            child: Row(
              children: [
                Text(
                  appText('任务列表', 'Task list'),
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(width: 6),
                Text(
                  '${tasks.length}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: palette.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
              itemCount: groupedTasks.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final group = groupedTasks[index];
                final expanded = expandedGroupsInternal.contains(
                  group.executionTarget,
                );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AssistantTaskGroupHeaderInternal(
                      executionTarget: group.executionTarget,
                      count: group.items.length,
                      expanded: expanded,
                      onTap: () {
                        setState(() {
                          if (expanded) {
                            expandedGroupsInternal.remove(
                              group.executionTarget,
                            );
                          } else {
                            expandedGroupsInternal.add(group.executionTarget);
                          }
                        });
                      },
                    ),
                    if (expanded) ...[
                      const SizedBox(height: 4),
                      if (group.items.isEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(28, 0, 8, 4),
                          child: Text(
                            appText('当前分组没有任务。', 'No tasks in this group.'),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: palette.textMuted,
                            ),
                          ),
                        ),
                      for (
                        var itemIndex = 0;
                        itemIndex < group.items.length;
                        itemIndex++
                      ) ...[
                        if (itemIndex > 0) const SizedBox(height: 4),
                        AssistantTaskTileInternal(
                          entry: group.items[itemIndex],
                          archiveEnabled:
                              normalizedTaskStatusInternal(
                                group.items[itemIndex].status,
                              ) !=
                              'running',
                          onTap: () async {
                            await widget.onSelectTask(
                              group.items[itemIndex].sessionKey,
                            );
                          },
                          onRename: () async {
                            await widget.onRenameTask(group.items[itemIndex]);
                          },
                          onArchive: () async {
                            await widget.onArchiveTask(
                              group.items[itemIndex].sessionKey,
                            );
                          },
                        ),
                      ],
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

List<AssistantTaskGroupInternal> groupTasksForRailInternal(
  List<AssistantTaskEntryInternal> tasks,
  List<AssistantExecutionTarget> visibleExecutionTargets,
) {
  final grouped = <AssistantExecutionTarget, List<AssistantTaskEntryInternal>>{
    for (final target in visibleExecutionTargets)
      target: <AssistantTaskEntryInternal>[],
  };
  for (final task in tasks) {
    final bucket = grouped[task.executionTarget];
    if (bucket == null) {
      continue;
    }
    bucket.add(task);
  }
  return visibleExecutionTargets
      .map(
        (target) => AssistantTaskGroupInternal(
          executionTarget: target,
          items: grouped[target]!,
        ),
      )
      .toList(growable: false);
}

class AssistantTaskTileInternal extends StatelessWidget {
  const AssistantTaskTileInternal({
    super.key,
    required this.entry,
    required this.archiveEnabled,
    required this.onTap,
    required this.onRename,
    required this.onArchive,
  });

  final AssistantTaskEntryInternal entry;
  final bool archiveEnabled;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    final statusStyle = pillStyleForStatusInternal(context, entry.status);

    return Material(
      color: entry.isCurrent ? palette.surfacePrimary : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        key: ValueKey<String>('assistant-task-item-${entry.sessionKey}'),
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        onLongPress: onRename,
        onSecondaryTap: onRename,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          decoration: BoxDecoration(
            color: entry.isCurrent
                ? palette.surfaceSecondary
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: entry.isCurrent ? palette.strokeSoft : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: statusStyle.backgroundColor,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  entry.draft
                      ? Icons.edit_note_rounded
                      : normalizedTaskStatusInternal(entry.status) == 'running'
                      ? Icons.play_arrow_rounded
                      : Icons.task_alt_rounded,
                  size: 15,
                  color: statusStyle.foregroundColor,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  entry.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: entry.isCurrent
                        ? FontWeight.w600
                        : FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                entry.updatedAtLabel,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: palette.textMuted,
                ),
              ),
              const SizedBox(width: 2),
              IconButton(
                key: ValueKey<String>(
                  'assistant-task-archive-${entry.sessionKey}',
                ),
                tooltip: appText('归档任务', 'Archive task'),
                visualDensity: VisualDensity.compact,
                splashRadius: 12,
                onPressed: archiveEnabled ? onArchive : null,
                icon: Icon(
                  Icons.archive_outlined,
                  size: 18,
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

class AssistantTaskGroupHeaderInternal extends StatelessWidget {
  const AssistantTaskGroupHeaderInternal({
    super.key,
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
        key: ValueKey<String>('assistant-task-group-${executionTarget.name}'),
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
              Icon(executionTarget.icon, size: 14, color: palette.textMuted),
              const SizedBox(width: 6),
              Flexible(
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

class AssistantEmptyStateInternal extends StatelessWidget {
  const AssistantEmptyStateInternal({
    super.key,
    required this.controller,
    required this.onFocusComposer,
    required this.onOpenGateway,
    required this.onOpenAiGatewaySettings,
    required this.onReconnectGateway,
  });

  final AppController controller;
  final VoidCallback onFocusComposer;
  final VoidCallback onOpenGateway;
  final VoidCallback onOpenAiGatewaySettings;
  final Future<void> Function() onReconnectGateway;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connectionState = controller.currentAssistantConnectionState;
    final singleAgent = connectionState.isSingleAgent;
    final connected = connectionState.connected;
    final singleAgentNeedsAiGateway =
        controller.currentSingleAgentNeedsAiGatewayConfiguration;
    final singleAgentSuggestsAcpSwitch =
        controller.currentSingleAgentShouldSuggestAcpSwitch;
    final providerLabel = controller.currentSingleAgentProvider.label;
    final reconnectAvailable = controller.canQuickConnectGateway;
    final title = singleAgent
        ? connected
              ? appText('开始 ACP Server 任务', 'Start an ACP Server task')
              : singleAgentNeedsAiGateway
              ? appText('先配置 ACP Server', 'Configure ACP Server first')
              : appText('先准备 ACP Server', 'Prepare the ACP Server first')
        : connected
        ? appText('开始对话或运行任务', 'Start a chat or run a task')
        : connectionState.status == RuntimeConnectionStatus.error
        ? appText('Gateway 连接失败', 'Gateway connection failed')
        : appText('先连接 Gateway', 'Connect a gateway first');
    final description = singleAgent
        ? connected
              ? appText(
                  '当前线程通过 ACP Server 处理任务，不会建立 OpenClaw Gateway 会话。',
                  'This thread runs through the ACP Server path and does not open an OpenClaw Gateway session.',
                )
              : singleAgentSuggestsAcpSwitch
              ? appText(
                  '当前线程固定为 $providerLabel，但它在这台设备上不可用。请改成可用的 ACP Server。',
                  'This thread is pinned to $providerLabel, but it is unavailable on this device. Switch to an available ACP Server.',
                )
              : singleAgentNeedsAiGateway
              ? appText(
                  '请先在 设置 -> 集成 中配置可用的外部 Agent ACP 端点，然后以 ACP Server 模式继续当前任务。',
                  'Configure an external Agent ACP endpoint in Settings -> Integrations, then continue this task in ACP Server mode.',
                )
              : appText(
                  '当前线程的外部 Agent ACP 连接尚未就绪。请先配置 $providerLabel 对应端点。',
                  'The external Agent ACP connection for this thread is not ready yet. Configure the endpoint for $providerLabel first.',
                )
        : connected
        ? appText(
            '输入需求后即可开始执行，结果会回到当前会话并同步到任务页。',
            'Type a request to start execution. Results return to this session and the Tasks page.',
          )
        : connectionState.pairingRequired
        ? appText(
            '当前设备还没通过 Gateway 配对审批。请先在已授权设备上批准该 pairing request，再重新连接。',
            'This device has not been approved yet. Approve the pairing request from an authorized device, then reconnect.',
          )
        : connectionState.gatewayTokenMissing
        ? appText(
            '首次连接需要共享 Token；配对完成后可继续使用本机的 device token。',
            'The first connection requires a shared token; after pairing, this device can continue with its device token.',
          )
        : !connected
        ? appText(
            '当前线程目标网关尚未连接。请先连接对应 Gateway，再继续当前任务。',
            'The selected gateway target for this thread is not connected yet. Connect that Gateway first, then continue this task.',
          )
        : (connectionState.lastError?.trim().isNotEmpty == true
              ? connectionState.lastError!.trim()
              : appText(
                  '连接后可直接对话、创建任务，并在当前会话查看结果。',
                  'After connecting, you can chat, create tasks, and read results in this session.',
                ));

    return Align(
      alignment: Alignment.topCenter,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Container(
            key: const Key('assistant-empty-state-card'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.palette.surfacePrimary.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: context.palette.strokeSoft),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(description, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    FilledButton.icon(
                      onPressed: connected
                          ? onFocusComposer
                          : singleAgent
                          ? singleAgentNeedsAiGateway
                                ? onOpenAiGatewaySettings
                                : onFocusComposer
                          : reconnectAvailable
                          ? () async {
                              await onReconnectGateway();
                            }
                          : onOpenGateway,
                      icon: Icon(
                        connected
                            ? Icons.edit_rounded
                            : singleAgent
                            ? singleAgentNeedsAiGateway
                                  ? Icons.tune_rounded
                                  : Icons.smart_toy_outlined
                            : reconnectAvailable
                            ? Icons.refresh_rounded
                            : Icons.link_rounded,
                      ),
                      label: Text(
                        connected
                            ? appText('开始输入', 'Start typing')
                            : singleAgent
                            ? singleAgentNeedsAiGateway
                                  ? appText('打开配置中心', 'Open settings')
                                  : appText('查看线程工具栏', 'Open toolbar')
                            : reconnectAvailable
                            ? appText('重新连接', 'Reconnect')
                            : appText('连接 Gateway', 'Connect gateway'),
                      ),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 28),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    if (!connected &&
                        (!singleAgent || singleAgentNeedsAiGateway))
                      OutlinedButton.icon(
                        onPressed: singleAgent
                            ? onOpenAiGatewaySettings
                            : onOpenGateway,
                        icon: Icon(
                          singleAgent
                              ? Icons.hub_outlined
                              : Icons.settings_rounded,
                        ),
                        label: Text(
                          singleAgent
                              ? appText('打开设置中心', 'Open settings')
                              : appText('编辑连接', 'Edit connection'),
                        ),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 28),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
