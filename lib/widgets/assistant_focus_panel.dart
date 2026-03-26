import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../i18n/app_language.dart';
import '../models/app_models.dart';
import '../runtime/runtime_models.dart';
import '../theme/app_palette.dart';
import 'chrome_quick_action_buttons.dart';
import 'settings_focus_quick_actions.dart';
import 'surface_card.dart';

class AssistantFocusPanel extends StatefulWidget {
  const AssistantFocusPanel({super.key, required this.controller});

  final AppController controller;

  @override
  State<AssistantFocusPanel> createState() => _AssistantFocusPanelState();
}

class AssistantFocusDestinationCard extends StatelessWidget {
  const AssistantFocusDestinationCard({
    super.key,
    required this.controller,
    required this.destination,
    required this.onOpenPage,
    required this.onRemoveFavorite,
  });

  final AppController controller;
  final AssistantFocusEntry destination;
  final VoidCallback onOpenPage;
  final Future<void> Function() onRemoveFavorite;

  @override
  Widget build(BuildContext context) {
    return _AssistantFocusWorkbench(
      controller: controller,
      destination: destination,
      onOpenPage: onOpenPage,
      onRemoveFavorite: onRemoveFavorite,
    );
  }
}

class _AssistantFocusPanelState extends State<AssistantFocusPanel> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    final favorites = widget.controller.assistantNavigationDestinations;
    final available = kAssistantNavigationDestinationCandidates
        .where(widget.controller.supportsAssistantFocusEntry)
        .where((item) => !favorites.contains(item))
        .toList(growable: false);

    return SurfaceCard(
      borderRadius: 16,
      padding: EdgeInsets.zero,
      tone: SurfaceCardTone.chrome,
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
                          '添加后的入口会直接出现在最左侧侧板。这里负责管理关注项和查看摘要，需要完整页面时再单独打开。',
                          'Added entries appear directly in the far-left rail. Manage focused destinations and review summaries here, then open the full page only when needed.',
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
                  PopupMenuButton<AssistantFocusEntry>(
                    key: const Key('assistant-focus-add-menu'),
                    tooltip: appText('添加关注入口', 'Add focused destination'),
                    onSelected: _addFavorite,
                    itemBuilder: (context) => available
                        .map(
                          (destination) => PopupMenuItem<AssistantFocusEntry>(
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
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            palette.chromeHighlight.withValues(alpha: 0.94),
                            palette.chromeSurfacePressed,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: palette.chromeStroke),
                        boxShadow: [palette.chromeShadowLift],
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
                      '还没有关注入口。给功能菜单点星标，或从右上角添加一个入口，加入最左侧侧板。',
                      'No focused entries yet. Star a destination or add one from the top-right menu to place it in the far-left rail.',
                    ),
                    available: available,
                    onAdd: _addFavorite,
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    itemCount: favorites.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final destination = favorites[index];
                      return AssistantFocusDestinationCard(
                        controller: widget.controller,
                        destination: destination,
                        onOpenPage: () => widget.controller.navigateTo(
                          destination.destination ?? WorkspaceDestination.settings,
                        ),
                        onRemoveFavorite: () => _removeFavorite(destination),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _addFavorite(AssistantFocusEntry destination) async {
    await widget.controller.toggleAssistantNavigationDestination(destination);
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _removeFavorite(AssistantFocusEntry destination) async {
    await widget.controller.toggleAssistantNavigationDestination(destination);
    if (mounted) {
      setState(() {});
    }
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
  final AssistantFocusEntry destination;
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
        crossAxisAlignment: CrossAxisAlignment.start,
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
                        key: ValueKey<String>(
                          'assistant-focus-active-title-${destination.name}',
                        ),
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
                  key: ValueKey<String>(
                    'assistant-focus-open-page-${destination.name}',
                  ),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: _AssistantFocusPreview(
              controller: controller,
              destination: destination,
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
  final AssistantFocusEntry destination;

  @override
  Widget build(BuildContext context) {
    return switch (destination) {
      AssistantFocusEntry.tasks => _TasksFocusPreview(controller: controller),
      AssistantFocusEntry.skills => _SkillsFocusPreview(
        controller: controller,
      ),
      AssistantFocusEntry.nodes => _NodesFocusPreview(controller: controller),
      AssistantFocusEntry.agents => _AgentsFocusPreview(
        controller: controller,
      ),
      AssistantFocusEntry.mcpServer => _McpFocusPreview(
        controller: controller,
      ),
      AssistantFocusEntry.clawHub => _ClawHubFocusPreview(
        controller: controller,
      ),
      AssistantFocusEntry.secrets => _SecretsFocusPreview(
        controller: controller,
      ),
      AssistantFocusEntry.aiGateway => _AiGatewayFocusPreview(
        controller: controller,
      ),
      AssistantFocusEntry.settings => _SettingsFocusPreview(
        controller: controller,
      ),
      AssistantFocusEntry.language => _LanguageFocusPreview(
        controller: controller,
      ),
      AssistantFocusEntry.theme => _ThemeFocusPreview(controller: controller),
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
            message:
                controller.connection.status ==
                    RuntimeConnectionStatus.connected
                ? appText('当前没有任务摘要。', 'No task summary yet.')
                : appText(
                    '连接 Gateway 后这里会显示任务摘要。',
                    'Connect a gateway to load task summaries.',
                  ),
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
    final items = controller.isSingleAgentMode
        ? controller
              .assistantImportedSkillsForSession(controller.currentSessionKey)
              .take(4)
              .map(
                (skill) => GatewaySkillSummary(
                  name: skill.label,
                  description: skill.description,
                  source: skill.sourcePath,
                  skillKey: skill.key,
                  primaryEnv: null,
                  eligible: true,
                  disabled: false,
                  missingBins: const <String>[],
                  missingEnv: const <String>[],
                  missingConfig: const <String>[],
                ),
              )
              .toList(growable: false)
        : controller.skills.take(4).toList(growable: false);
    if (items.isEmpty) {
      return _PreviewEmptyState(
        message: controller.isSingleAgentMode
            ? (controller.currentSingleAgentNeedsAiGatewayConfiguration
                  ? appText(
                      '当前没有可用的外部 Agent ACP 端点，请先配置 LLM API fallback。',
                      'No external Agent ACP endpoint is available. Configure LLM API fallback first.',
                    )
                  : appText(
                      '当前线程还没有已加载技能。切换 provider 后会读取该线程自己的 skills 列表。',
                      'No skills are loaded for this thread yet. Switching the provider reloads the thread-owned skills list.',
                    ))
            : controller.connection.status == RuntimeConnectionStatus.connected
            ? appText(
                '当前代理没有已加载技能。',
                'No skills are loaded for the active agent.',
              )
            : appText(
                '连接 Gateway 后可查看技能摘要。',
                'Connect a gateway to inspect skills here.',
              ),
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
                subtitle:
                    [instance.platform, instance.deviceFamily, instance.ip]
                        .whereType<String>()
                        .where((item) => item.trim().isNotEmpty)
                        .join(' · '),
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
    final skillCount = controller.isSingleAgentMode
        ? controller.currentAssistantSkillCount
        : controller.skills.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _FocusPill(
              label: appText('已加载技能 $skillCount', 'Loaded skills $skillCount'),
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
              '当前没有 LLM API 模型摘要。',
              'No LLM API model summary is available yet.',
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsFocusQuickActions(
          appLanguage: controller.appLanguage,
          themeMode: controller.themeMode,
          onToggleLanguage: controller.toggleAppLanguage,
          onToggleTheme: () {
            controller.setThemeMode(
              controller.themeMode == ThemeMode.dark
                  ? ThemeMode.light
                  : ThemeMode.dark,
            );
          },
          languageButtonKey: const Key(
            'assistant-focus-settings-language-toggle',
          ),
          themeButtonKey: const Key('assistant-focus-settings-theme-toggle'),
        ),
        const SizedBox(height: 12),
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
          subtitle: appText(
            'Assistant 默认运行位置',
            'Default assistant execution target',
          ),
          trailing: controller.assistantExecutionTarget.label,
        ),
        const SizedBox(height: 8),
        _FocusListTile(
          title: appText('权限', 'Permissions'),
          subtitle: appText(
            'Assistant 默认权限级别',
            'Default assistant permission level',
          ),
          trailing: controller.assistantPermissionLevel.label,
        ),
      ],
    );
  }
}

class _LanguageFocusPreview extends StatelessWidget {
  const _LanguageFocusPreview({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final currentLabel = controller.appLanguage == AppLanguage.zh
        ? appText('中文', 'Chinese')
        : 'English';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ChromeLanguageActionButton(
          key: const Key('assistant-focus-language-toggle'),
          appLanguage: controller.appLanguage,
          compact: false,
          tooltip: appText('切换语言', 'Toggle language'),
          onPressed: controller.toggleAppLanguage,
        ),
        const SizedBox(height: 12),
        _FocusListTile(
          title: appText('当前语言', 'Current language'),
          subtitle: appText(
            '点击上方按钮即可在中英文界面之间切换。',
            'Use the button above to switch between Chinese and English.',
          ),
          trailing: currentLabel,
        ),
      ],
    );
  }
}

class _ThemeFocusPreview extends StatelessWidget {
  const _ThemeFocusPreview({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final themeLabel = switch (controller.themeMode) {
      ThemeMode.dark => appText('深色', 'Dark'),
      ThemeMode.light => appText('浅色', 'Light'),
      ThemeMode.system => appText('跟随系统', 'System'),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ChromeIconActionButton(
          key: const Key('assistant-focus-theme-toggle'),
          icon: chromeThemeToggleIcon(controller.themeMode),
          tooltip: chromeThemeToggleTooltip(controller.themeMode),
          onPressed: () {
            controller.setThemeMode(
              controller.themeMode == ThemeMode.dark
                  ? ThemeMode.light
                  : ThemeMode.dark,
            );
          },
        ),
        const SizedBox(height: 12),
        _FocusListTile(
          title: appText('当前主题', 'Current theme'),
          subtitle: appText(
            '点击上方按钮即可切换亮度模式。',
            'Use the button above to switch appearance mode.',
          ),
          trailing: themeLabel,
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
  final List<AssistantFocusEntry> available;
  final Future<void> Function(AssistantFocusEntry destination) onAdd;

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
