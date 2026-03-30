// ignore_for_file: unused_import, unnecessary_import

import 'dart:convert';
import 'dart:math' as math;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import '../app/app_controller_web.dart';
import '../app/ui_feature_manifest.dart';
import '../i18n/app_language.dart';
import '../models/app_models.dart';
import '../runtime/runtime_models.dart';
import '../theme/app_palette.dart';
import '../widgets/assistant_artifact_sidebar.dart';
import '../widgets/desktop_workspace_scaffold.dart';
import '../widgets/pane_resize_handle.dart';
import '../widgets/surface_card.dart';
import 'web_assistant_page_core.dart';
import 'web_assistant_page_workspace.dart';
import 'web_assistant_page_helpers.dart';

class AssistantWorkspaceChromeInternal extends StatelessWidget {
  const AssistantWorkspaceChromeInternal({
    super.key,
    required this.controller,
    required this.collapsed,
    required this.onToggleCollapsed,
  });

  final AppController controller;
  final bool collapsed;
  final VoidCallback onToggleCollapsed;

  @override
  Widget build(BuildContext context) {
    final connectionState = controller.currentAssistantConnectionState;
    return SurfaceCard(
      tone: SurfaceCardTone.chrome,
      borderRadius: 10,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        child: collapsed
            ? Row(
                children: [
                  const Expanded(
                    child: ChromeNavigationPillsInternal(compact: true),
                  ),
                  ChromeConnectionChipInternal(
                    state: connectionState,
                    compact: true,
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    key: const Key('assistant-workspace-chrome-toggle'),
                    tooltip: appText('展开顶部导航', 'Expand top navigation'),
                    style: IconButton.styleFrom(
                      minimumSize: const Size(40, 40),
                      maximumSize: const Size(40, 40),
                    ),
                    onPressed: onToggleCollapsed,
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(child: ChromeNavigationPillsInternal()),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ChromeConnectionChipInternal(state: connectionState),
                          const SizedBox(width: 8),
                          IconButton(
                            key: const Key('assistant-workspace-chrome-toggle'),
                            tooltip: appText(
                              '折叠顶部导航',
                              'Collapse top navigation',
                            ),
                            style: IconButton.styleFrom(
                              minimumSize: const Size(40, 40),
                              maximumSize: const Size(40, 40),
                            ),
                            onPressed: onToggleCollapsed,
                            icon: const Icon(Icons.keyboard_arrow_up_rounded),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}

class ChromeNavigationPillsInternal extends StatelessWidget {
  const ChromeNavigationPillsInternal({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ChromePillInternal(
          icon: Icons.home_rounded,
          label: appText('主页', 'Home'),
          compact: compact,
        ),
        ChromePillInternal(
          label: WorkspaceDestination.assistant.label,
          emphasized: true,
          compact: compact,
        ),
      ],
    );
  }
}

class ChromeConnectionChipInternal extends StatelessWidget {
  const ChromeConnectionChipInternal({
    super.key,
    required this.state,
    this.compact = false,
  });

  final AssistantThreadConnectionState state;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    final tone = switch (state.status) {
      RuntimeConnectionStatus.connected => (
        palette.success.withValues(alpha: 0.14),
        palette.success.withValues(alpha: 0.22),
        palette.success,
      ),
      RuntimeConnectionStatus.connecting => (
        palette.accentMuted.withValues(alpha: 0.86),
        palette.accent.withValues(alpha: 0.18),
        palette.accent,
      ),
      RuntimeConnectionStatus.error => (
        palette.danger.withValues(alpha: 0.12),
        palette.danger.withValues(alpha: 0.18),
        palette.textSecondary,
      ),
      RuntimeConnectionStatus.offline => (
        palette.warning.withValues(alpha: 0.12),
        palette.warning.withValues(alpha: 0.18),
        palette.textSecondary,
      ),
    };
    final text = [
      state.primaryLabel.trim(),
      state.detailLabel.trim(),
    ].where((item) => item.isNotEmpty).join(' · ');

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: compact ? 280 : 360),
      child: Container(
        key: const Key('assistant-workspace-status-chip'),
        constraints: const BoxConstraints(minHeight: 40),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 12,
          vertical: compact ? 7 : 8,
        ),
        decoration: BoxDecoration(
          color: tone.$1,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: tone.$2),
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelLarge?.copyWith(
            color: tone.$3,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.02,
          ),
        ),
      ),
    );
  }
}

class AssistantTaskPaneInternal extends StatelessWidget {
  const AssistantTaskPaneInternal({
    super.key,
    required this.controller,
    required this.query,
    required this.searchController,
    required this.onQueryChanged,
    required this.onClearQuery,
    required this.showSingle,
    required this.showLocal,
    required this.showRemote,
    required this.single,
    required this.local,
    required this.remote,
    required this.onRename,
    required this.onArchive,
    required this.onOpenActions,
  });

  final AppController controller;
  final String query;
  final TextEditingController searchController;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onClearQuery;
  final bool showSingle;
  final bool showLocal;
  final bool showRemote;
  final List<WebConversationSummary> single;
  final List<WebConversationSummary> local;
  final List<WebConversationSummary> remote;
  final ValueChanged<String> onRename;
  final ValueChanged<String> onArchive;
  final ValueChanged<String> onOpenActions;

  @override
  Widget build(BuildContext context) {
    final runningCount = controller.conversations
        .where((item) => item.pending)
        .length;
    final threadCount = controller.conversations.length;
    final skillCount = controller.currentAssistantSkillCount;

    return SurfaceCard(
      key: const Key('assistant-task-rail'),
      borderRadius: 10,
      tone: SurfaceCardTone.chrome,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: searchController,
            onChanged: onQueryChanged,
            decoration: InputDecoration(
              hintText: appText('搜索任务', 'Search tasks'),
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      onPressed: onClearQuery,
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: () => controller.createConversation(
              target: controller.assistantExecutionTarget,
            ),
            icon: const Icon(Icons.edit_square),
            label: Text(appText('新对话', 'New conversation')),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(42),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              MetaChipInternal(
                icon: Icons.play_circle_outline_rounded,
                label: '${appText('运行中', 'Running')} $runningCount',
              ),
              MetaChipInternal(
                icon: Icons.chat_bubble_outline_rounded,
                label: '${appText('当前', 'Current')} $threadCount',
              ),
              MetaChipInternal(
                icon: Icons.auto_awesome_rounded,
                label: '${appText('技能', 'Skills')} $skillCount',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              children: [
                if (showSingle)
                  ConversationGroupInternal(
                    title: appText('单机智能体', 'Single Agent'),
                    icon: Icons.hub_rounded,
                    items: single,
                    emptyLabel: appText(
                      '还没有 Single Agent 任务线程',
                      'No Single Agent task threads yet',
                    ),
                    onSelect: controller.switchConversation,
                    onRename: onRename,
                    onArchive: onArchive,
                    onOpenActions: onOpenActions,
                  ),
                if (showLocal) ...[
                  const SizedBox(height: 12),
                  ConversationGroupInternal(
                    title: appText('本地 OpenClaw Gateway', 'Local Gateway'),
                    icon: Icons.laptop_mac_rounded,
                    items: local,
                    emptyLabel: appText(
                      '还没有 Local Gateway 任务线程',
                      'No Local Gateway task threads yet',
                    ),
                    onSelect: controller.switchConversation,
                    onRename: onRename,
                    onArchive: onArchive,
                    onOpenActions: onOpenActions,
                  ),
                ],
                if (showRemote) ...[
                  const SizedBox(height: 12),
                  ConversationGroupInternal(
                    title: appText('远程 OpenClaw Gateway', 'Remote Gateway'),
                    icon: Icons.cloud_outlined,
                    items: remote,
                    emptyLabel: appText(
                      '还没有 Remote Gateway 任务线程',
                      'No Remote Gateway task threads yet',
                    ),
                    onSelect: controller.switchConversation,
                    onRename: onRename,
                    onArchive: onArchive,
                    onOpenActions: onOpenActions,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ConversationGroupInternal extends StatelessWidget {
  const ConversationGroupInternal({
    super.key,
    required this.title,
    required this.icon,
    required this.items,
    required this.emptyLabel,
    required this.onSelect,
    required this.onRename,
    required this.onArchive,
    required this.onOpenActions,
  });

  final String title;
  final IconData icon;
  final List<WebConversationSummary> items;
  final String emptyLabel;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onRename;
  final ValueChanged<String> onArchive;
  final ValueChanged<String> onOpenActions;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: palette.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$title ${items.length}',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (items.isEmpty)
          Text(
            emptyLabel,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: palette.textSecondary),
          ),
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SurfaceCard(
              onTap: () => onSelect(item.sessionKey),
              borderRadius: 10,
              padding: const EdgeInsets.all(12),
              color: item.current ? palette.accentMuted : null,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      item.pending
                          ? Icons.play_circle_outline_rounded
                          : Icons.check_circle_outline_rounded,
                      size: 18,
                      color: item.pending
                          ? palette.accent
                          : palette.success.withValues(alpha: 0.92),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.preview,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: palette.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        relativeTimeLabelInternal(item.updatedAtMs),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                      const SizedBox(height: 6),
                      IconButton(
                        tooltip: appText('更多操作', 'More actions'),
                        onPressed: () => onOpenActions(item.sessionKey),
                        icon: const Icon(Icons.more_horiz_rounded),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
