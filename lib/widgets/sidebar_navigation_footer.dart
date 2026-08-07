part of 'sidebar_navigation.dart';

/// Height of one footer row, matching the control inside it.
const double sidebarFooterRowHeight = 40;

/// Gap between the section divider and the first row. Sized so the whole
/// footer block reaches [sidebarFooterBlockHeight]; it is not a free choice.
const double sidebarFooterDividerGap = 19;

/// Distance from the sidebar pane's bottom to the last row. The pane's own
/// 4pt padding brings the total to the composer's 16pt.
const double sidebarFooterBottomInset = 12;

/// Total height of the footer block: divider + gap + three rows.
/// Must equal the composer card's minimum height so the shell's two bottom
/// blocks line up. Locked by sidebar_footer_baseline_test.dart.
const double sidebarFooterBlockHeight =
    1 +
    sidebarFooterDividerGap +
    sidebarFooterRowHeight * 3 +
    AppSpacing.xs * 2;

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

    // The footer and the composer card are the shell's two bottom blocks, and
    // they sit side by side across the whole window — so they share a baseline
    // and a height, or the mismatch reads as a misalignment.
    //
    // The composer at its minimum is 152pt tall and floats 16pt above the pane
    // bottom (8pt safe-area inset + 8pt card padding). The sidebar's own pane
    // padding already supplies 4pt of that, so the footer adds the remaining
    // 12pt below and pads the divider gap out until the block reaches 152pt.
    // `sidebarFooterBlockHeight` is asserted against the composer's minimum in
    // sidebar_footer_baseline_test.dart, so the two cannot drift apart
    // unnoticed.
    return Padding(
      padding: const EdgeInsets.only(bottom: sidebarFooterBottomInset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 1,
            color: palette.chromeStroke.withValues(alpha: 0.9),
          ),
          const SizedBox(height: sidebarFooterDividerGap),
          for (var index = 0; index < actions.length; index++) ...[
            actions[index],
            if (index != actions.length - 1)
              const SizedBox(height: AppSpacing.xs),
          ],
        ],
      ),
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
                height: sidebarFooterRowHeight,
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
                                  borderRadius: BorderRadius.circular(
                                    AppRadius.badge,
                                  ),
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
