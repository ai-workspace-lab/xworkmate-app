part of 'sidebar_navigation.dart';

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
    required this.sidebarState,
    required this.onCycleSidebarState,
    required this.onOpenAccount,
    required this.showAccountButton,
    required this.accountSelected,
    required this.showCollapseControl,
  });

  final bool isCollapsed;
  final WorkspaceDestination currentSection;
  final AppLanguage appLanguage;
  final ThemeMode themeMode;
  final VoidCallback onToggleLanguage;
  final VoidCallback onOpenThemeToggle;
  final VoidCallback onOpenSettings;
  final bool showSettingsButton;
  final AppSidebarState sidebarState;
  final VoidCallback onCycleSidebarState;
  final VoidCallback onOpenAccount;
  final bool showAccountButton;
  final bool accountSelected;
  final bool showCollapseControl;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final actions = <Widget>[
      if (showSettingsButton)
        _SidebarFooterButton(
          key: const ValueKey<String>('sidebar-footer-settings'),
          icon: currentSection == WorkspaceDestination.settings
              ? Icons.settings_rounded
              : Icons.settings_outlined,
          label: appText('设置', 'Settings'),
          tooltip: appText('打开设置页', 'Open settings'),
          selected: currentSection == WorkspaceDestination.settings,
          collapsed: isCollapsed,
          onTap: onOpenSettings,
        ),
      if (showAccountButton)
        _SidebarFooterButton(
          key: const ValueKey<String>('sidebar-footer-account'),
          icon: accountSelected
              ? Icons.account_circle_rounded
              : Icons.account_circle_outlined,
          label: appText('账户', 'Account'),
          tooltip: appText('打开账号页', 'Open account'),
          selected: accountSelected,
          collapsed: isCollapsed,
          onTap: onOpenAccount,
        ),
      _SidebarFooterButton(
        key: const ValueKey<String>('sidebar-footer-language'),
        icon: Icons.translate_rounded,
        label: appText('语言', 'Language'),
        tooltip: appText('切换语言', 'Toggle language'),
        collapsed: isCollapsed,
        trailingLabel: isCollapsed ? null : _languageBadge(appLanguage),
        onTap: onToggleLanguage,
      ),
      _SidebarFooterButton(
        key: const ValueKey<String>('sidebar-footer-theme'),
        icon: _themeIcon(themeMode),
        label: appText('主题', 'Theme'),
        tooltip: appText('切换主题', 'Toggle theme'),
        collapsed: isCollapsed,
        trailingLabel: isCollapsed ? null : _themeBadge(themeMode),
        onTap: onOpenThemeToggle,
      ),
      if (showCollapseControl)
        _SidebarFooterButton(
          key: const ValueKey<String>('sidebar-footer-collapse'),
          icon: _sidebarStateIcon(sidebarState),
          label: _sidebarStateLabel(sidebarState),
          tooltip: _sidebarStateTooltip(sidebarState),
          collapsed: isCollapsed,
          onTap: onCycleSidebarState,
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 1,
          color: palette.chromeStroke.withValues(alpha: 0.9),
        ),
        const SizedBox(height: AppSpacing.xs),
        for (var index = 0; index < actions.length; index++) ...[
          actions[index],
          if (index != actions.length - 1) const SizedBox(height: AppSpacing.xs),
        ],
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
      AppSidebarState.expanded => appText('折叠', 'Collapse'),
      AppSidebarState.collapsed => appText('展开', 'Expand'),
      AppSidebarState.hidden => appText('展开', 'Expand'),
    };
  }

  String _sidebarStateTooltip(AppSidebarState state) {
    return switch (state) {
      AppSidebarState.expanded => appText('收起侧边栏', 'Collapse sidebar'),
      AppSidebarState.collapsed => appText('展开侧边栏', 'Expand sidebar'),
      AppSidebarState.hidden => appText('展开侧边栏', 'Expand sidebar'),
    };
  }

  IconData _themeIcon(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.light => Icons.light_mode_rounded,
      ThemeMode.dark => Icons.dark_mode_rounded,
      ThemeMode.system => Icons.brightness_auto_rounded,
    };
  }

  String _themeBadge(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.light => appText('浅色', 'Light'),
      ThemeMode.dark => appText('深色', 'Dark'),
      ThemeMode.system => appText('跟随', 'Auto'),
    };
  }

  String _languageBadge(AppLanguage language) {
    return switch (language) {
      AppLanguage.zh => '中',
      AppLanguage.en => 'EN',
    };
  }
}

class _SidebarFooterButton extends StatefulWidget {
  const _SidebarFooterButton({
    super.key,
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.collapsed,
    required this.onTap,
    this.selected = false,
    this.trailingLabel,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final bool collapsed;
  final VoidCallback onTap;
  final bool selected;
  final String? trailingLabel;

  @override
  State<_SidebarFooterButton> createState() => _SidebarFooterButtonState();
}

class _SidebarFooterButtonState extends State<_SidebarFooterButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    final active = widget.selected || _hovered;
    final background = widget.selected
        ? palette.surfacePrimary
        : _hovered
        ? palette.chromeSurfacePressed
        : Colors.transparent;

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            color: active ? background.withValues(alpha: 0.98) : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.button),
            border: Border.all(
              color: active ? palette.strokeSoft : Colors.transparent,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.button),
              onTap: widget.onTap,
              child: SizedBox(
                height: 40,
                child: widget.collapsed
                    ? Center(
                        child: Icon(
                          widget.icon,
                          size: AppSizes.sidebarIconSize,
                          color: active
                              ? palette.textPrimary
                              : palette.textSecondary,
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 20,
                              child: Icon(
                                widget.icon,
                                size: AppSizes.sidebarIconSize,
                                color: active
                                    ? palette.textPrimary
                                    : palette.textSecondary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                widget.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: active
                                      ? palette.textPrimary
                                      : palette.textSecondary,
                                  fontWeight: active
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                            if (widget.trailingLabel != null) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: palette.surfacePrimary,
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(color: palette.strokeSoft),
                                ),
                                child: Text(
                                  widget.trailingLabel!,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: palette.textSecondary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ],
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
