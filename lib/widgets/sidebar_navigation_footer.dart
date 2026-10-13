part of 'sidebar_navigation.dart';

/// Height of the footer row, matching the control inside it.
const double sidebarFooterRowHeight = 40;

/// Distance from the sidebar pane's bottom to the footer row. The pane's own
/// 4pt padding brings the total to the composer's 16pt, so the footer row and
/// the composer card rest on the same baseline.
const double sidebarFooterBottomInset = 12;

/// The footer is one row: a settings control that opens a sectioned menu, and
/// the signed-in account. Settings, language, theme and account live in the
/// menu instead of as a stack of rows.
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
    required this.onOpenAccount,
    required this.accountName,
    required this.accountSubtitle,
  });

  final bool isCollapsed;
  final WorkspaceDestination currentSection;
  final AppLanguage appLanguage;
  final ThemeMode themeMode;
  final VoidCallback onToggleLanguage;
  final VoidCallback onOpenThemeToggle;
  final VoidCallback onOpenSettings;
  final bool showSettingsButton;
  final VoidCallback onOpenAccount;
  final String accountName;
  final String accountSubtitle;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    final menu = _SidebarSettingsMenu(
      selected: currentSection == WorkspaceDestination.settings,
      appLanguage: appLanguage,
      themeMode: themeMode,
      onToggleLanguage: onToggleLanguage,
      onOpenThemeToggle: onOpenThemeToggle,
      onOpenSettings: showSettingsButton ? onOpenSettings : null,
      onOpenAccount: onOpenAccount,
      accountName: accountName,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: sidebarFooterBottomInset),
      child: SizedBox(
        height: sidebarFooterRowHeight,
        child: isCollapsed
            ? Center(child: menu)
            : Row(
                children: [
                  menu,
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      accountName.trim().isEmpty
                          ? appText('未登录', 'Not signed in')
                          : accountName,
                      key: const Key('sidebar-footer-account-name'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _SidebarSettingsMenu extends StatelessWidget {
  const _SidebarSettingsMenu({
    required this.selected,
    required this.appLanguage,
    required this.themeMode,
    required this.onToggleLanguage,
    required this.onOpenThemeToggle,
    required this.onOpenSettings,
    required this.onOpenAccount,
    required this.accountName,
  });

  final bool selected;
  final AppLanguage appLanguage;
  final ThemeMode themeMode;
  final VoidCallback onToggleLanguage;
  final VoidCallback onOpenThemeToggle;
  final VoidCallback? onOpenSettings;
  final VoidCallback onOpenAccount;
  final String accountName;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return MenuAnchor(
      alignmentOffset: const Offset(0, 6),
      // Match the app's popup menus instead of the Material 3 tinted surface.
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(palette.surfacePrimary),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        side: WidgetStatePropertyAll(BorderSide(color: palette.strokeSoft)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.dialog),
          ),
        ),
      ),
      menuChildren: [
        _MenuSectionLabel(appText('设置', 'Settings')),
        if (onOpenSettings != null)
          _menuItem(
            context,
            key: 'settings',
            icon: Icons.tune_rounded,
            label: appText('设置', 'Settings'),
            onPressed: onOpenSettings!,
          ),
        _menuItem(
          context,
          key: 'language',
          icon: Icons.translate_rounded,
          label: appText('语言', 'Language'),
          trailing: switch (appLanguage) {
            AppLanguage.zh => '中',
            AppLanguage.en => 'EN',
          },
          onPressed: onToggleLanguage,
        ),
        _menuItem(
          context,
          key: 'theme',
          icon: switch (themeMode) {
            ThemeMode.light => Icons.light_mode_rounded,
            ThemeMode.dark => Icons.dark_mode_rounded,
            ThemeMode.system => Icons.brightness_auto_rounded,
          },
          label: appText('主题', 'Theme'),
          trailing: switch (themeMode) {
            ThemeMode.light => appText('浅色', 'Light'),
            ThemeMode.dark => appText('深色', 'Dark'),
            ThemeMode.system => appText('跟随', 'Auto'),
          },
          onPressed: onOpenThemeToggle,
        ),
        const Divider(height: 9),
        _MenuSectionLabel(appText('账户', 'Account')),
        _menuItem(
          context,
          key: 'account',
          icon: Icons.account_circle_outlined,
          label: accountName.trim().isEmpty
              ? appText('登录账户', 'Sign in')
              : accountName,
          onPressed: onOpenAccount,
        ),
      ],
      builder: (context, controller, child) => Tooltip(
        message: appText('设置与账户', 'Settings and account'),
        child: IconButton(
          key: const Key('sidebar-footer-menu-button'),
          onPressed: () =>
              controller.isOpen ? controller.close() : controller.open(),
          visualDensity: VisualDensity.compact,
          isSelected: selected,
          style: IconButton.styleFrom(
            foregroundColor: palette.textSecondary,
            overlayColor: palette.chromeSurfacePressed,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.button),
            ),
          ),
          icon: Icon(
            selected ? Icons.settings_rounded : Icons.settings_outlined,
            size: AppSizes.sidebarIconSize,
          ),
        ),
      ),
    );
  }

  Widget _menuItem(
    BuildContext context, {
    required String key,
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    String? trailing,
  }) {
    final palette = context.palette;
    final theme = Theme.of(context);
    return MenuItemButton(
      key: Key('sidebar-footer-menu-$key'),
      style: MenuItemButton.styleFrom(
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
      leadingIcon: Icon(icon, size: 18, color: palette.textSecondary),
      trailingIcon: trailing == null
          ? null
          : Text(
              trailing,
              style: theme.textTheme.labelSmall?.copyWith(
                color: palette.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
      onPressed: onPressed,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 160),
        child: Text(label),
      ),
    );
  }
}

class _MenuSectionLabel extends StatelessWidget {
  const _MenuSectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Text(
        label.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: palette.textMuted,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
