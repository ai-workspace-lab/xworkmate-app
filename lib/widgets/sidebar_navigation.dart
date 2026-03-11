import 'package:flutter/material.dart';

import '../app/app_metadata.dart';
import '../i18n/app_language.dart';
import '../models/app_models.dart';
import '../theme/app_palette.dart';

class SidebarNavigation extends StatelessWidget {
  const SidebarNavigation({
    super.key,
    required this.currentSection,
    required this.isCollapsed,
    required this.appLanguage,
    required this.themeMode,
    required this.onSectionChanged,
    required this.onToggleLanguage,
    required this.onToggleCollapsed,
    required this.onOpenAccount,
    required this.onOpenThemeToggle,
  });

  final WorkspaceDestination currentSection;
  final bool isCollapsed;
  final AppLanguage appLanguage;
  final ThemeMode themeMode;
  final ValueChanged<WorkspaceDestination> onSectionChanged;
  final VoidCallback onToggleLanguage;
  final VoidCallback onToggleCollapsed;
  final VoidCallback onOpenAccount;
  final VoidCallback onOpenThemeToggle;

  static const _mainSections = [
    WorkspaceDestination.assistant,
    WorkspaceDestination.tasks,
    WorkspaceDestination.modules,
    WorkspaceDestination.secrets,
    WorkspaceDestination.settings,
  ];

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: isCollapsed ? 72 : 236,
      margin: const EdgeInsets.fromLTRB(8, 8, 6, 8),
      decoration: BoxDecoration(
        color: palette.sidebar,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: palette.sidebarBorder.withValues(alpha: 0.72),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: isCollapsed ? 8 : 12,
          vertical: 12,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SidebarHeader(isCollapsed: isCollapsed),
            const SizedBox(height: 12),
            Container(height: 1, color: palette.sidebarBorder),
            const SizedBox(height: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: _mainSections
                            .map(
                              (section) => Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: SidebarNavItem(
                                  section: section,
                                  selected: currentSection == section,
                                  collapsed: isCollapsed,
                                  onTap: () => onSectionChanged(section),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(height: 1, color: palette.sidebarBorder),
                  const SizedBox(height: 10),
                  SidebarFooter(
                    isCollapsed: isCollapsed,
                    appLanguage: appLanguage,
                    themeMode: themeMode,
                    onToggleLanguage: onToggleLanguage,
                    onOpenThemeToggle: onOpenThemeToggle,
                    onOpenSettings: () =>
                        onSectionChanged(WorkspaceDestination.settings),
                    onToggleCollapsed: onToggleCollapsed,
                    onOpenAccount: onOpenAccount,
                    accountSelected:
                        currentSection == WorkspaceDestination.account,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SidebarHeader extends StatelessWidget {
  const SidebarHeader({super.key, required this.isCollapsed});

  final bool isCollapsed;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: palette.accentMuted,
          ),
          child: Icon(
            Icons.auto_awesome_rounded,
            color: palette.accent,
            size: 20,
          ),
        ),
        if (!isCollapsed) ...[
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  kProductBrandName,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 2),
                Text(
                  appText('可执行 AI 工作台', kProductSubtitle),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class SidebarNavItem extends StatefulWidget {
  const SidebarNavItem({
    super.key,
    required this.section,
    required this.selected,
    required this.collapsed,
    required this.onTap,
  });

  final WorkspaceDestination section;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  State<SidebarNavItem> createState() => _SidebarNavItemState();
}

class _SidebarNavItemState extends State<SidebarNavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final active = widget.selected;
    final background = active
        ? palette.accentMuted
        : _hovered
        ? palette.hover
        : Colors.transparent;
    final foreground = active ? palette.accent : palette.textSecondary;

    final item = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: widget.onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: widget.collapsed ? 0 : 12,
              vertical: 10,
            ),
            child: Row(
              mainAxisAlignment: widget.collapsed
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                Icon(widget.section.icon, color: foreground, size: 20),
                if (!widget.collapsed) ...[
                  const SizedBox(width: 10),
                  Text(
                    widget.section.label,
                    style: Theme.of(
                      context,
                    ).textTheme.labelLarge?.copyWith(color: foreground),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Tooltip(
        message: widget.collapsed ? widget.section.label : '',
        child: item,
      ),
    );
  }
}

class SidebarFooter extends StatelessWidget {
  const SidebarFooter({
    super.key,
    required this.isCollapsed,
    required this.appLanguage,
    required this.themeMode,
    required this.onToggleLanguage,
    required this.onOpenThemeToggle,
    required this.onOpenSettings,
    required this.onToggleCollapsed,
    required this.onOpenAccount,
    required this.accountSelected,
  });

  final bool isCollapsed;
  final AppLanguage appLanguage;
  final ThemeMode themeMode;
  final VoidCallback onToggleLanguage;
  final VoidCallback onOpenThemeToggle;
  final VoidCallback onOpenSettings;
  final VoidCallback onToggleCollapsed;
  final VoidCallback onOpenAccount;
  final bool accountSelected;

  @override
  Widget build(BuildContext context) {
    final languageButton = Tooltip(
      message: appText('切换语言', 'Switch language'),
      child: isCollapsed
          ? IconButton(
              onPressed: onToggleLanguage,
              icon: const Icon(Icons.translate_rounded),
            )
          : OutlinedButton.icon(
              onPressed: onToggleLanguage,
              icon: const Icon(Icons.translate_rounded, size: 18),
              label: Text(appLanguage.buttonLabel),
            ),
    );

    final themeButton = Tooltip(
      message: themeMode == ThemeMode.dark
          ? appText('切换浅色', 'Switch to light')
          : appText('切换深色', 'Switch to dark'),
      child: IconButton(
        onPressed: onOpenThemeToggle,
        icon: Icon(
          themeMode == ThemeMode.dark
              ? Icons.light_mode_rounded
              : Icons.dark_mode_rounded,
        ),
      ),
    );

    final settingsButton = Tooltip(
      message: appText('打开设置', 'Open settings'),
      child: IconButton(
        onPressed: onOpenSettings,
        icon: const Icon(Icons.settings_rounded),
      ),
    );

    final collapseButton = Tooltip(
      message: isCollapsed
          ? appText('展开导航', 'Expand sidebar')
          : appText('折叠导航', 'Collapse sidebar'),
      child: IconButton(
        onPressed: onToggleCollapsed,
        icon: Icon(
          isCollapsed
              ? Icons.menu_open_rounded
              : Icons.keyboard_double_arrow_left_rounded,
        ),
      ),
    );

    return Column(
      children: [
        if (isCollapsed)
          Column(
            children: [
              themeButton,
              const SizedBox(height: 6),
              languageButton,
              const SizedBox(height: 6),
              settingsButton,
              const SizedBox(height: 6),
              collapseButton,
            ],
          )
        else
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [themeButton, settingsButton, collapseButton],
          ),
        if (!isCollapsed) ...[
          const SizedBox(height: 8),
          SizedBox(width: double.infinity, child: languageButton),
        ],
        const SizedBox(height: 8),
        Tooltip(
          message: isCollapsed ? appText('账号', 'Account') : '',
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onOpenAccount,
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(
                horizontal: isCollapsed ? 0 : 12,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: accountSelected
                    ? context.palette.accentMuted
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: isCollapsed
                  ? const Icon(Icons.account_circle_rounded)
                  : Row(
                      children: [
                        const CircleAvatar(radius: 16, child: Text('H')),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Haitao Pan',
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                            Text(
                              appText('账号', 'Account'),
                              style: Theme.of(context).textTheme.bodySmall,
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
