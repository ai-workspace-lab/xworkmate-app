part of 'web_assistant_page.dart';

class _AssistantWorkspaceChrome extends StatelessWidget {
  const _AssistantWorkspaceChrome({
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
                  const Expanded(child: _ChromeNavigationPills(compact: true)),
                  _ChromeConnectionChip(state: connectionState, compact: true),
                  const SizedBox(width: 8),
                  IconButton(
                    key: const Key('assistant-workspace-chrome-toggle'),
                    tooltip: appText('展开顶部导航', 'Expand top navigation'),
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
                      const Expanded(child: _ChromeNavigationPills()),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _ChromeConnectionChip(state: connectionState),
                          const SizedBox(width: 8),
                          IconButton(
                            key: const Key('assistant-workspace-chrome-toggle'),
                            tooltip: appText(
                              '折叠顶部导航',
                              'Collapse top navigation',
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

class _ChromeNavigationPills extends StatelessWidget {
  const _ChromeNavigationPills({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _ChromePill(
          icon: Icons.home_rounded,
          label: appText('主页', 'Home'),
          compact: compact,
        ),
        _ChromePill(
          label: WorkspaceDestination.assistant.label,
          emphasized: true,
          compact: compact,
        ),
      ],
    );
  }
}

class _ChromeConnectionChip extends StatelessWidget {
  const _ChromeConnectionChip({required this.state, this.compact = false});

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
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 12,
          vertical: compact ? 6 : 7,
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

class _AssistantSidePane extends StatelessWidget {
  const _AssistantSidePane({
    required this.collapsed,
    required this.activePane,
    required this.controller,
    required this.query,
    required this.searchController,
    required this.permissionLevel,
    required this.onQueryChanged,
    required this.onClearQuery,
    required this.onToggleCollapsed,
    required this.onPaneChanged,
    required this.onPermissionChanged,
    required this.onRename,
    required this.onArchive,
    required this.onOpenActions,
  });

  final bool collapsed;
  final _WebAssistantPane activePane;
  final AppController controller;
  final String query;
  final TextEditingController searchController;
  final AssistantPermissionLevel permissionLevel;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onClearQuery;
  final VoidCallback onToggleCollapsed;
  final ValueChanged<_WebAssistantPane> onPaneChanged;
  final ValueChanged<AssistantPermissionLevel> onPermissionChanged;
  final ValueChanged<String> onRename;
  final ValueChanged<String> onArchive;
  final ValueChanged<String> onOpenActions;

  @override
  Widget build(BuildContext context) {
    final single = controller.conversationsForTarget(
      AssistantExecutionTarget.singleAgent,
    );
    final local = controller.conversationsForTarget(
      AssistantExecutionTarget.local,
    );
    final remote = controller.conversationsForTarget(
      AssistantExecutionTarget.remote,
    );
    final filteredSingle = _filterConversations(single, query);
    final filteredLocal = _filterConversations(local, query);
    final filteredRemote = _filterConversations(remote, query);
    final palette = context.palette;

    return Row(
      children: [
        Container(
          key: const Key('assistant-side-pane'),
          width: _webAssistantSideTabRailWidth,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                palette.chromeHighlight.withValues(alpha: 0.96),
                palette.chromeSurface,
              ],
            ),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: palette.chromeStroke),
            boxShadow: [palette.chromeShadowAmbient],
          ),
          child: Column(
            children: [
              const SizedBox(height: 4),
              _AssistantSideTabButton(
                key: const Key('assistant-side-pane-tab-tasks'),
                icon: Icons.checklist_rtl_rounded,
                selected: activePane == _WebAssistantPane.tasks,
                tooltip: appText('任务', 'Tasks'),
                onTap: () => onPaneChanged(_WebAssistantPane.tasks),
              ),
              const SizedBox(height: 4),
              _AssistantSideTabButton(
                key: const Key('assistant-side-pane-tab-quick'),
                icon: Icons.dashboard_customize_outlined,
                selected: activePane == _WebAssistantPane.quick,
                tooltip: appText('快捷面板', 'Quick panel'),
                onTap: () => onPaneChanged(_WebAssistantPane.quick),
              ),
              const Spacer(),
              IconButton(
                key: const Key('assistant-side-pane-toggle'),
                tooltip: collapsed
                    ? appText('展开侧板', 'Expand side pane')
                    : appText('收起侧板', 'Collapse side pane'),
                onPressed: onToggleCollapsed,
                style: IconButton.styleFrom(
                  backgroundColor: palette.chromeSurface,
                  foregroundColor: palette.textSecondary,
                  side: BorderSide(color: palette.chromeStroke),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: Icon(
                  collapsed
                      ? Icons.keyboard_double_arrow_right_rounded
                      : Icons.keyboard_double_arrow_left_rounded,
                  size: 18,
                ),
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
        if (!collapsed) ...[
          const SizedBox(width: 6),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: KeyedSubtree(
                key: ValueKey<String>('assistant-side-pane-${activePane.name}'),
                child: activePane == _WebAssistantPane.tasks
                    ? _AssistantTaskPane(
                        controller: controller,
                        query: query,
                        searchController: searchController,
                        onQueryChanged: onQueryChanged,
                        onClearQuery: onClearQuery,
                        showSingle: controller
                            .featuresFor(UiFeaturePlatform.web)
                            .supportsDirectAi,
                        showLocal: controller
                            .featuresFor(UiFeaturePlatform.web)
                            .supportsLocalGateway,
                        showRemote: controller
                            .featuresFor(UiFeaturePlatform.web)
                            .supportsRelayGateway,
                        single: filteredSingle,
                        local: filteredLocal,
                        remote: filteredRemote,
                        onRename: onRename,
                        onArchive: onArchive,
                        onOpenActions: onOpenActions,
                      )
                    : _AssistantQuickPane(
                        controller: controller,
                        permissionLevel: permissionLevel,
                        onPermissionChanged: onPermissionChanged,
                      ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _AssistantTaskPane extends StatelessWidget {
  const _AssistantTaskPane({
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
              _MetaChip(
                icon: Icons.play_circle_outline_rounded,
                label: '${appText('运行中', 'Running')} $runningCount',
              ),
              _MetaChip(
                icon: Icons.chat_bubble_outline_rounded,
                label: '${appText('当前', 'Current')} $threadCount',
              ),
              _MetaChip(
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
                  _ConversationGroup(
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
                  _ConversationGroup(
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
                  _ConversationGroup(
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

class _AssistantQuickPane extends StatelessWidget {
  const _AssistantQuickPane({
    required this.controller,
    required this.permissionLevel,
    required this.onPermissionChanged,
  });

  final AppController controller;
  final AssistantPermissionLevel permissionLevel;
  final ValueChanged<AssistantPermissionLevel> onPermissionChanged;

  @override
  Widget build(BuildContext context) {
    return WebAssistantFocusPanel(controller: controller);
  }
}

class _ConversationGroup extends StatelessWidget {
  const _ConversationGroup({
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
                        _relativeTimeLabel(item.updatedAtMs),
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
