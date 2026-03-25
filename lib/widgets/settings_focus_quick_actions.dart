import 'package:flutter/material.dart';

import '../i18n/app_language.dart';
import '../theme/app_theme.dart';
import 'chrome_quick_action_buttons.dart';

class SettingsFocusQuickActions extends StatelessWidget {
  const SettingsFocusQuickActions({
    super.key,
    required this.appLanguage,
    required this.themeMode,
    required this.onToggleLanguage,
    required this.onToggleTheme,
    this.languageButtonKey,
    this.themeButtonKey,
  });

  final AppLanguage appLanguage;
  final ThemeMode themeMode;
  final VoidCallback onToggleLanguage;
  final VoidCallback onToggleTheme;
  final Key? languageButtonKey;
  final Key? themeButtonKey;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ChromeLanguageActionButton(
            key: languageButtonKey,
            appLanguage: appLanguage,
            compact: false,
            tooltip: appText('切换语言', 'Toggle language'),
            onPressed: onToggleLanguage,
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        ChromeIconActionButton(
          key: themeButtonKey,
          icon: chromeThemeToggleIcon(themeMode),
          tooltip: chromeThemeToggleTooltip(themeMode),
          onPressed: onToggleTheme,
        ),
      ],
    );
  }
}
