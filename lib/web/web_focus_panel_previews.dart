// ignore_for_file: unused_import, unnecessary_import

import 'package:flutter/material.dart';
import '../app/app_controller_web.dart';
import '../i18n/app_language.dart';
import '../models/app_models.dart';
import '../runtime/runtime_models.dart';
import '../theme/app_palette.dart';
import '../widgets/chrome_quick_action_buttons.dart';
import '../widgets/settings_focus_quick_actions.dart';
import '../widgets/surface_card.dart';
import 'web_focus_panel_core.dart';
import 'web_focus_panel_support.dart';

class TasksFocusPreviewInternal extends StatelessWidget {
  const TasksFocusPreviewInternal({super.key, required this.controller});

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
            FocusPillInternal(
              label: appText(
                '运行中 ${controller.tasksController.running.length}',
                'Running ${controller.tasksController.running.length}',
              ),
            ),
            FocusPillInternal(
              label: appText(
                '队列 ${controller.tasksController.queue.length}',
                'Queue ${controller.tasksController.queue.length}',
              ),
            ),
            FocusPillInternal(
              label: appText(
                '计划 ${controller.tasksController.scheduled.length}',
                'Scheduled ${controller.tasksController.scheduled.length}',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (items.isEmpty)
          PreviewEmptyStateInternal(
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
              child: FocusListTileInternal(
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

class SkillsFocusPreviewInternal extends StatelessWidget {
  const SkillsFocusPreviewInternal({super.key, required this.controller});

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
      return PreviewEmptyStateInternal(
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
              child: FocusListTileInternal(
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

class NodesFocusPreviewInternal extends StatelessWidget {
  const NodesFocusPreviewInternal({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final items = controller.instances.take(4).toList(growable: false);
    if (items.isEmpty) {
      return PreviewEmptyStateInternal(
        message: appText('当前没有节点可显示。', 'No nodes are available right now.'),
      );
    }
    return Column(
      children: items
          .map(
            (instance) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: FocusListTileInternal(
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

class AgentsFocusPreviewInternal extends StatelessWidget {
  const AgentsFocusPreviewInternal({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final items = controller.agents.take(5).toList(growable: false);
    if (items.isEmpty) {
      return PreviewEmptyStateInternal(
        message: appText('当前没有代理摘要。', 'No agents are available right now.'),
      );
    }
    return Column(
      children: items
          .map(
            (agent) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: FocusListTileInternal(
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

class McpFocusPreviewInternal extends StatelessWidget {
  const McpFocusPreviewInternal({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final items = controller.connectors.take(4).toList(growable: false);
    if (items.isEmpty) {
      return PreviewEmptyStateInternal(
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
              child: FocusListTileInternal(
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

class ClawHubFocusPreviewInternal extends StatelessWidget {
  const ClawHubFocusPreviewInternal({super.key, required this.controller});

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
            FocusPillInternal(
              label: appText('已加载技能 $skillCount', 'Loaded skills $skillCount'),
            ),
            FocusPillInternal(
              label: appText(
                '关注入口 ${controller.assistantNavigationDestinations.length}',
                'Pinned ${controller.assistantNavigationDestinations.length}',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        PreviewEmptyStateInternal(
          message: appText(
            'ClawHub 适合放在侧板做快速搜索或安装入口；需要完整终端交互时，再打开全页。',
            'Use ClawHub in the side panel for quick access. Open the full page when you need the terminal workflow.',
          ),
        ),
      ],
    );
  }
}

class SecretsFocusPreviewInternal extends StatelessWidget {
  const SecretsFocusPreviewInternal({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final items = controller.secretReferences.take(4).toList(growable: false);
    if (items.isEmpty) {
      return PreviewEmptyStateInternal(
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
              child: FocusListTileInternal(
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

class AiGatewayFocusPreviewInternal extends StatelessWidget {
  const AiGatewayFocusPreviewInternal({super.key, required this.controller});

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
            FocusPillInternal(label: controller.connection.status.label),
            FocusPillInternal(
              label: appText(
                '模型 ${controller.models.length}',
                'Models ${controller.models.length}',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (items.isEmpty)
          PreviewEmptyStateInternal(
            message: appText(
              '当前没有 LLM API 模型摘要。',
              'No LLM API model summary is available yet.',
            ),
          )
        else
          ...items.map(
            (model) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: FocusListTileInternal(
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

class SettingsFocusPreviewInternal extends StatelessWidget {
  const SettingsFocusPreviewInternal({super.key, required this.controller});

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
        FocusListTileInternal(
          title: appText('语言', 'Language'),
          subtitle: appText('当前界面语言', 'Current interface language'),
          trailing: languageLabel,
        ),
        const SizedBox(height: 8),
        FocusListTileInternal(
          title: appText('主题', 'Theme'),
          subtitle: appText('当前显示模式', 'Current display mode'),
          trailing: themeLabel,
        ),
        const SizedBox(height: 8),
        FocusListTileInternal(
          title: appText('执行目标', 'Execution target'),
          subtitle: appText(
            'Assistant 默认运行位置',
            'Default assistant execution target',
          ),
          trailing: controller.assistantExecutionTarget.label,
        ),
        const SizedBox(height: 8),
        FocusListTileInternal(
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

class LanguageFocusPreviewInternal extends StatelessWidget {
  const LanguageFocusPreviewInternal({super.key, required this.controller});

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
        FocusListTileInternal(
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

class ThemeFocusPreviewInternal extends StatelessWidget {
  const ThemeFocusPreviewInternal({super.key, required this.controller});

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
        FocusListTileInternal(
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

class FocusListTileInternal extends StatelessWidget {
  const FocusListTileInternal({
    super.key,
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

class FocusPillInternal extends StatelessWidget {
  const FocusPillInternal({super.key, required this.label});

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

class PreviewEmptyStateInternal extends StatelessWidget {
  const PreviewEmptyStateInternal({super.key, required this.message});

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
