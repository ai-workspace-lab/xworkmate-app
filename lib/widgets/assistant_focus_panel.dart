import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../i18n/app_language.dart';
import '../models/app_models.dart';
import '../runtime/runtime_models.dart';
import '../theme/app_palette.dart';
import 'surface_card.dart';

class AssistantFocusPanel extends StatefulWidget {
  const AssistantFocusPanel({super.key, required this.controller});

  final AppController controller;

  @override
  State<AssistantFocusPanel> createState() => _AssistantFocusPanelState();
}

class _AssistantFocusPanelState extends State<AssistantFocusPanel> {
  WorkspaceDestination? _selectedDestination;

  @override
  void initState() {
    super.initState();
    _selectedDestination = _normalizeSelection(
      widget.controller.assistantNavigationDestinations,
      _selectedDestination,
    );
  }

  @override
  void didUpdateWidget(covariant AssistantFocusPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _selectedDestination = _normalizeSelection(
      widget.controller.assistantNavigationDestinations,
      _selectedDestination,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    final favorites = widget.controller.assistantNavigationDestinations;
    final available = kAssistantNavigationDestinationCandidates
        .where((item) => !favorites.contains(item))
        .toList(growable: false);
    final selected = _normalizeSelection(favorites, _selectedDestination);

    return SurfaceCard(
      borderRadius: 16,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 10, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        appText('关注入口', 'Focused navigation'),
                        key: const Key('assistant-focus-panel-title'),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        appText(
                          '像侧边工作区一样切换常用入口。点 tab 只切左侧预览，不会打断当前主页面。',
                          'Switch frequent destinations like a side workspace. Tabs update the left preview without replacing the main page.',
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: palette.textSecondary,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                if (available.isNotEmpty)
                  PopupMenuButton<WorkspaceDestination>(
                    key: const Key('assistant-focus-add-menu'),
                    tooltip: appText('添加关注入口', 'Add focused destination'),
                    onSelected: _addFavorite,
                    itemBuilder: (context) => available
                        .map(
                          (destination) => PopupMenuItem<WorkspaceDestination>(
                            value: destination,
                            child: Row(
                              children: [
                                Icon(destination.icon, size: 18),
                                const SizedBox(width: 10),
                                Expanded(child: Text(destination.label)),
                              ],
                            ),
                          ),
                        )
                        .toList(growable: false),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: palette.surfaceSecondary,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: palette.strokeSoft),
                      ),
                      child: Icon(
                        Icons.add_rounded,
                        size: 18,
                        color: palette.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: palette.strokeSoft),
          Expanded(
            child: favorites.isEmpty
                ? _AssistantFocusEmptyState(
                    message: appText(
                      '还没有关注入口。给左侧菜单点星标，或从右上角添加一个常用入口。',
                      'No focused entries yet. Star a menu item on the left or add a frequent destination from the top-right menu.',
                    ),
                    available: available,
                    onAdd: _addFavorite,
                  )
                : Row(
                    children: [
                      Container(
                        width: 56,
                        margin: const EdgeInsets.fromLTRB(10, 12, 0, 10),
                        decoration: BoxDecoration(
                          color: palette.surfaceSecondary,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: palette.strokeSoft),
                        ),
                        child: ListView(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          children: favorites
                              .map(
                                (destination) => Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: _AssistantFocusRailButton(
                                    destination: destination,
                                    selected: destination == selected,
                                    onTap: () {
                                      setState(() {
                                        _selectedDestination = destination;
                                      });
                                    },
                                  ),
                                ),
                              )
                              .toList(growable: false),
                        ),
                      ),
                      VerticalDivider(
                        width: 20,
                        thickness: 1,
                        color: palette.strokeSoft,
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(0, 12, 10, 10),
                          child: _AssistantFocusWorkbench(
                            controller: widget.controller,
                            destination: selected!,
                            onOpenPage: () =>
                                widget.controller.navigateTo(selected),
                            onRemoveFavorite: () => _removeFavorite(selected),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  WorkspaceDestination? _normalizeSelection(
    List<WorkspaceDestination> favorites,
    WorkspaceDestination? current,
  ) {
    if (favorites.isEmpty) {
      return null;
    }
    if (current != null && favorites.contains(current)) {
      return current;
    }
    return favorites.first;
  }

  Future<void> _addFavorite(WorkspaceDestination destination) async {
    await widget.controller.toggleAssistantNavigationDestination(destination);
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedDestination = destination;
    });
  }

  Future<void> _removeFavorite(WorkspaceDestination destination) async {
    await widget.controller.toggleAssistantNavigationDestination(destination);
    if (!mounted) {
      return;
    }
    setState(() {
      final favorites = widget.controller.assistantNavigationDestinations;
      _selectedDestination = _normalizeSelection(favorites, _selectedDestination);
    });
  }
}

class _AssistantFocusRailButton extends StatelessWidget {
  const _AssistantFocusRailButton({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final WorkspaceDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Tooltip(
      message: destination.label,
      child: InkWell(
        key: ValueKey<String>('assistant-focus-tab-${destination.name}'),
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          margin: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: selected ? palette.accentMuted : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            destination.icon,
            size: 20,
            color: selected ? palette.accent : palette.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _AssistantFocusWorkbench extends StatelessWidget {
  const _AssistantFocusWorkbench({
    required this.controller,
    required this.destination,
    required this.onOpenPage,
    required this.onRemoveFavorite,
  });

  final AppController controller;
  final WorkspaceDestination destination;
  final VoidCallback onOpenPage;
  final Future<void> Function() onRemoveFavorite;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;

    return Container(
      decoration: BoxDecoration(
        color: palette.surfacePrimary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.strokeSoft),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 10, 10),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: palette.surfaceSecondary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    destination.icon,
                    size: 18,
                    color: palette.accent,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        destination.label,
                        key: const Key('assistant-focus-active-title'),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        destination.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: palette.textSecondary,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: const Key('assistant-focus-open-page'),
                  tooltip: appText('打开全页', 'Open full page'),
                  onPressed: onOpenPage,
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                ),
                IconButton(
                  key: ValueKey<String>(
                    'assistant-focus-remove-${destination.name}',
                  ),
                  tooltip: appText('取消关注', 'Remove from focused panel'),
                  onPressed: () async {
                    await onRemoveFavorite();
                  },
                  icon: Icon(Icons.star_rounded, color: palette.accent),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: palette.strokeSoft),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              child: _AssistantFocusPreview(
                controller: controller,
                destination: destination,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AssistantFocusPreview extends StatelessWidget {
  const _AssistantFocusPreview({
    required this.controller,
    required this.destination,
  });

  final AppController controller;
  final WorkspaceDestination destination;

  @override
  Widget build(BuildContext context) {
    return switch (destination) {
      WorkspaceDestination.tasks => _TasksFocusPreview(controller: controller),
      WorkspaceDestination.skills => _SkillsFocusPreview(controller: controller),
      WorkspaceDestination.nodes => _NodesFocusPreview(controller: controller),
      WorkspaceDestination.agents => _AgentsFocusPreview(controller: controller),
      WorkspaceDestination.mcpServer => _McpFocusPreview(controller: controller),
      WorkspaceDestination.clawHub => _ClawHubFocusPreview(
        controller: controller,
      ),
      WorkspaceDestination.secrets => _SecretsFocusPreview(
        controller: controller,
      ),
      WorkspaceDestination.aiGateway => _AiGatewayFocusPreview(
        controller: controller,
      ),
      WorkspaceDestination.settings => _SettingsFocusPreview(
        controller: controller,
      ),
      _ => const SizedBox.shrink(),
    };
  }
}

class _TasksFocusPreview extends StatelessWidget {
  const _TasksFocusPreview({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final items = <DerivedTaskItem>[
      ...controller.tasksController.running.take(2),
      ...controller.tasksController.queue.take(2),
      ...controller.tasksController.history.take(1),
    ].take(4).toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _FocusPill(
              label: appText(
                '运行中 ${controller.tasksController.running.length}',
                'Running ${controller.tasksController.running.length}',
              ),
            ),
            _FocusPill(
              label: appText(
                '队列 ${controller.tasksController.queue.length}',
                'Queue ${controller.tasksController.queue.length}',
              ),
            ),
            _FocusPill(
              label: appText(
                '计划 ${controller.tasksController.scheduled.length}',
                'Scheduled ${controller.tasksController.scheduled.length}',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (items.isEmpty)
          _PreviewEmptyState(
            message: controller.connection.status ==
                    RuntimeConnectionStatus.connected
                ? appText('当前没有任务摘要。', 'No task summary yet.')
                : appText('连接 Gateway 后这里会显示任务摘要。', 'Connect a gateway to load task summaries.'),
          )
        else
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _FocusListTile(
                title: item.title,
                subtitle: item.summary,
                trailing: item.status,
              ),
            ),
          ),
      ],
    );
  }
}

class _SkillsFocusPreview extends StatelessWidget {
  const _SkillsFocusPreview({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final items = controller.skills.take(4).toList(growable: false);
    if (items.isEmpty) {
      return _PreviewEmptyState(
        message: controller.connection.status == RuntimeConnectionStatus.connected
            ? appText('当前代理没有已加载技能。', 'No skills are loaded for the active agent.')
            : appText('连接 Gateway 后可查看技能摘要。', 'Connect a gateway to inspect skills here.'),
      );
    }
    return Column(
      children: items
          .map(
            (skill) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _FocusListTile(
                title: skill.name,
                subtitle: skill.description,
                trailing: skill.disabled
                    ? appText('已禁用', 'Disabled')
                    : appText('已启用', 'Enabled'),
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _NodesFocusPreview extends StatelessWidget {
  const _NodesFocusPreview({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final items = controller.instances.take(4).toList(growable: false);
    if (items.isEmpty) {
      return _PreviewEmptyState(
        message: appText('当前没有节点可显示。', 'No nodes are available right now.'),
      );
    }
    return Column(
      children: items
          .map(
            (instance) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _FocusListTile(
                title: instance.host?.trim().isNotEmpty == true
                    ? instance.host!
                    : instance.id,
                subtitle: [
                  instance.platform,
                  instance.deviceFamily,
                  instance.ip,
                ].whereType<String>().where((item) => item.trim().isNotEmpty).join(' · '),
                trailing: instance.mode ?? appText('未知', 'Unknown'),
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _AgentsFocusPreview extends StatelessWidget {
  const _AgentsFocusPreview({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final items = controller.agents.take(5).toList(growable: false);
    if (items.isEmpty) {
      return _PreviewEmptyState(
        message: appText('当前没有代理摘要。', 'No agents are available right now.'),
      );
    }
    return Column(
      children: items
          .map(
            (agent) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _FocusListTile(
                title: '${agent.emoji} ${agent.name}',
                subtitle: agent.id,
                trailing: agent.name == controller.activeAgentName
                    ? appText('当前', 'Active')
                    : agent.theme,
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _McpFocusPreview extends StatelessWidget {
  const _McpFocusPreview({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final items = controller.connectors.take(4).toList(growable: false);
    if (items.isEmpty) {
      return _PreviewEmptyState(
        message: appText(
          '当前没有 MCP 连接器。连接 Gateway 后这里会显示工具摘要。',
          'No MCP connectors yet. Connect a gateway to load tool summaries here.',
        ),
      );
    }
    return Column(
      children: items
          .map(
            (connector) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _FocusListTile(
                title: connector.label,
                subtitle: connector.detailLabel,
                trailing: connector.status,
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _ClawHubFocusPreview extends StatelessWidget {
  const _ClawHubFocusPreview({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _FocusPill(
              label: appText(
                '已加载技能 ${controller.skills.length}',
                'Loaded skills ${controller.skills.length}',
              ),
            ),
            _FocusPill(
              label: appText(
                '关注入口 ${controller.assistantNavigationDestinations.length}',
                'Pinned ${controller.assistantNavigationDestinations.length}',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _PreviewEmptyState(
          message: appText(
            'ClawHub 适合放在侧板做快速搜索或安装入口；需要完整终端交互时，再打开全页。',
            'Use ClawHub in the side panel for quick access. Open the full page when you need the terminal workflow.',
          ),
        ),
      ],
    );
  }
}

class _SecretsFocusPreview extends StatelessWidget {
  const _SecretsFocusPreview({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final items = controller.secretReferences.take(4).toList(growable: false);
    if (items.isEmpty) {
      return _PreviewEmptyState(
        message: appText(
          '当前没有密钥引用摘要。',
          'No masked secret references are available yet.',
        ),
      );
    }
    return Column(
      children: items
          .map(
            (secret) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _FocusListTile(
                title: secret.name,
                subtitle: '${secret.provider} · ${secret.module}',
                trailing: secret.status,
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _AiGatewayFocusPreview extends StatelessWidget {
  const _AiGatewayFocusPreview({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final items = controller.models.take(4).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _FocusPill(label: controller.connection.status.label),
            _FocusPill(
              label: appText(
                '模型 ${controller.models.length}',
                'Models ${controller.models.length}',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (items.isEmpty)
          _PreviewEmptyState(
            message: appText(
              '当前没有 AI Gateway 模型摘要。',
              'No AI Gateway model summary is available yet.',
            ),
          )
        else
          ...items.map(
            (model) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _FocusListTile(
                title: model.name,
                subtitle: model.provider,
                trailing: model.id,
              ),
            ),
          ),
      ],
    );
  }
}

class _SettingsFocusPreview extends StatelessWidget {
  const _SettingsFocusPreview({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final languageLabel = controller.appLanguage == AppLanguage.zh
        ? appText('中文', 'Chinese')
        : 'English';
    final themeLabel = switch (controller.themeMode) {
      ThemeMode.dark => appText('深色', 'Dark'),
      ThemeMode.light => appText('浅色', 'Light'),
      ThemeMode.system => appText('跟随系统', 'System'),
    };

    return Column(
      children: [
        _FocusListTile(
          title: appText('语言', 'Language'),
          subtitle: appText('当前界面语言', 'Current interface language'),
          trailing: languageLabel,
        ),
        const SizedBox(height: 8),
        _FocusListTile(
          title: appText('主题', 'Theme'),
          subtitle: appText('当前显示模式', 'Current display mode'),
          trailing: themeLabel,
        ),
        const SizedBox(height: 8),
        _FocusListTile(
          title: appText('执行目标', 'Execution target'),
          subtitle: appText('Assistant 默认运行位置', 'Default assistant execution target'),
          trailing: controller.assistantExecutionTarget.label,
        ),
        const SizedBox(height: 8),
        _FocusListTile(
          title: appText('权限', 'Permissions'),
          subtitle: appText('Assistant 默认权限级别', 'Default assistant permission level'),
          trailing: controller.assistantPermissionLevel.label,
        ),
      ],
    );
  }
}

class _FocusListTile extends StatelessWidget {
  const _FocusListTile({
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  final String title;
  final String subtitle;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: palette.surfaceSecondary,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.strokeSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: palette.textSecondary,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            trailing,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelLarge?.copyWith(
              color: palette.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _FocusPill extends StatelessWidget {
  const _FocusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: palette.surfaceSecondary,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.strokeSoft),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelLarge?.copyWith(
          color: palette.textSecondary,
        ),
      ),
    );
  }
}

class _PreviewEmptyState extends StatelessWidget {
  const _PreviewEmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.surfaceSecondary,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.strokeSoft),
      ),
      child: Text(
        message,
        style: theme.textTheme.bodySmall?.copyWith(
          color: palette.textSecondary,
          height: 1.35,
        ),
      ),
    );
  }
}

class _AssistantFocusEmptyState extends StatelessWidget {
  const _AssistantFocusEmptyState({
    required this.message,
    required this.available,
    required this.onAdd,
  });

  final String message;
  final List<WorkspaceDestination> available;
  final Future<void> Function(WorkspaceDestination destination) onAdd;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: palette.surfaceSecondary,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: palette.strokeSoft),
          ),
          child: Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(
              color: palette.textSecondary,
              height: 1.35,
            ),
          ),
        ),
        if (available.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: available
                .map(
                  (destination) => ActionChip(
                    key: ValueKey<String>(
                      'assistant-focus-add-${destination.name}',
                    ),
                    avatar: Icon(destination.icon, size: 16),
                    label: Text(destination.label),
                    onPressed: () async {
                      await onAdd(destination);
                    },
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ],
    );
  }
}
