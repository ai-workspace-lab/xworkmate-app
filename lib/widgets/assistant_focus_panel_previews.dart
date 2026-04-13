// ignore_for_file: unused_import, unnecessary_import

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../i18n/app_language.dart';
import '../models/app_models.dart';
import '../runtime/runtime_models.dart';
import '../theme/app_palette.dart';
import 'assistant_focus_panel_core.dart';
import 'assistant_focus_panel_support.dart';
import 'chrome_quick_action_buttons.dart';
import 'settings_focus_quick_actions.dart';
import 'surface_card.dart';

class SettingsFocusPreviewInternal extends StatelessWidget {
  const SettingsFocusPreviewInternal({super.key, required this.controller});

  final AssistantFocusControllerInternal controller;

  @override
  Widget build(BuildContext context) {
    final typedController = castAssistantFocusControllerInternal(controller);
    final themeMode = typedController.themeMode;
    final languageLabel = typedController.appLanguage == AppLanguage.zh
        ? appText('中文', 'Chinese')
        : 'English';
    final themeLabel = switch (themeMode) {
      ThemeMode.dark => appText('深色', 'Dark'),
      ThemeMode.light => appText('浅色', 'Light'),
      ThemeMode.system => appText('跟随系统', 'System'),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsFocusQuickActions(
          appLanguage: typedController.appLanguage,
          themeMode: themeMode,
          onToggleLanguage: typedController.toggleAppLanguage,
          onToggleTheme: () {
            typedController.setThemeMode(
              themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark,
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
          trailing: typedController.assistantExecutionTarget.label,
        ),
        const SizedBox(height: 8),
        FocusListTileInternal(
          title: appText('权限', 'Permissions'),
          subtitle: appText(
            'Assistant 默认权限级别',
            'Default assistant permission level',
          ),
          trailing: typedController.assistantPermissionLevel.label,
        ),
      ],
    );
  }
}

class LanguageFocusPreviewInternal extends StatelessWidget {
  const LanguageFocusPreviewInternal({super.key, required this.controller});

  final AssistantFocusControllerInternal controller;

  @override
  Widget build(BuildContext context) {
    final typedController = castAssistantFocusControllerInternal(controller);
    final currentLabel = typedController.appLanguage == AppLanguage.zh
        ? appText('中文', 'Chinese')
        : 'English';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ChromeLanguageActionButton(
          key: const Key('assistant-focus-language-toggle'),
          appLanguage: typedController.appLanguage,
          compact: false,
          tooltip: appText('切换语言', 'Toggle language'),
          onPressed: typedController.toggleAppLanguage,
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

  final AssistantFocusControllerInternal controller;

  @override
  Widget build(BuildContext context) {
    final typedController = castAssistantFocusControllerInternal(controller);
    final themeMode = typedController.themeMode;
    final themeLabel = switch (themeMode) {
      ThemeMode.dark => appText('深色', 'Dark'),
      ThemeMode.light => appText('浅色', 'Light'),
      ThemeMode.system => appText('跟随系统', 'System'),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ChromeIconActionButton(
          key: const Key('assistant-focus-theme-toggle'),
          icon: chromeThemeToggleIcon(themeMode),
          tooltip: chromeThemeToggleTooltip(themeMode),
          onPressed: () {
            typedController.setThemeMode(
              themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark,
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
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: palette.surfaceSecondary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.strokeSoft),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: palette.textSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            trailing,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: palette.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
