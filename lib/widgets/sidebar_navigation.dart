import 'package:flutter/material.dart';

import '../app/app_metadata.dart';
import '../i18n/app_language.dart';
import '../models/app_models.dart';
import '../theme/app_palette.dart';

class SidebarNavigation extends StatelessWidget {
  const SidebarNavigation({
    super.key,
    required this.currentSection,
    required this.sidebarState,
    required this.appLanguage,
    required this.themeMode,
    required this.onSectionChanged,
    required this.onToggleLanguage,
    required this.onCycleSidebarState,
    required this.onExpandFromCollapsed,
    required this.onOpenAccount,
    required this.onOpenThemeToggle,
  });

  final WorkspaceDestination currentSection;
  final AppSidebarState sidebarState;
  final AppLanguage appLanguage;
  final ThemeMode themeMode;
  final ValueChanged<WorkspaceDestination> onSectionChanged;
  final VoidCallback onToggleLanguage;
  final VoidCallback onCycleSidebarState;
  final VoidCallback onExpandFromCollapsed;
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
    final isExpanded = sidebarState == AppSidebarState.expanded;
    final isCollapsed = sidebarState == AppSidebarState.collapsed;
    final expandedWidth = appLanguage == AppLanguage.zh ? 204.0 : 220.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: isExpanded ? expandedWidth : 72,
      height: double.infinity,
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
          horizontal: isExpanded ? 10 : 8,
          vertical: 10,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SidebarHeader(
              isCollapsed: !isExpanded,
              onTap: isCollapsed ? onExpandFromCollapsed : null,
            ),
            const SizedBox(height: 12),
            Container(height: 1, color: palette.sidebarBorder),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  ..._mainSections.map(
                    (section) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: SidebarNavItem(
                        section: section,
                        selected: currentSection == section,
                        collapsed: isCollapsed,
                        onTap: () => onSectionChanged(section),
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
                    sidebarState: sidebarState,
                    onCycleSidebarState: onCycleSidebarState,
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
  const SidebarHeader({super.key, required this.isCollapsed, this.onTap});

  final bool isCollapsed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;

    final content = Row(
      children: [
        Container(
          width: isCollapsed ? 38 : 34,
          height: isCollapsed ? 38 : 34,
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
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  kProductBrandName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.headlineSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  appText('可执行 AI 工作台', kProductSubtitle),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ],
    );

    if (onTap == null) {
      return content;
    }

    return Tooltip(
      message: appText('展开导航', 'Expand sidebar'),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: content,
        ),
      ),
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
      width: widget.collapsed ? null : double.infinity,
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
              horizontal: widget.collapsed ? 0 : 10,
              vertical: widget.collapsed ? 10 : 9,
            ),
            child: Row(
              mainAxisAlignment: widget.collapsed
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                Icon(widget.section.icon, color: foreground, size: 18),
                if (!widget.collapsed) ...[
                  const SizedBox(width: 8),
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
      child: widget.collapsed
          ? Tooltip(message: widget.section.label, child: item)
          : item,
    );
  }
}

class SidebarFooter extends StatelessWidget {
  const SidebarFooter({
    super.key,
    required this.isCollapsed,
    required this.sidebarState,
    required this.appLanguage,
    required this.themeMode,
    required this.onToggleLanguage,
    required this.onOpenThemeToggle,
    required this.onOpenSettings,
    required this.onCycleSidebarState,
    required this.onOpenAccount,
    required this.accountSelected,
  });

  final bool isCollapsed;
  final AppSidebarState sidebarState;
  final AppLanguage appLanguage;
  final ThemeMode themeMode;
  final VoidCallback onToggleLanguage;
  final VoidCallback onOpenThemeToggle;
  final VoidCallback onOpenSettings;
  final VoidCallback onCycleSidebarState;
  final VoidCallback onOpenAccount;
  final bool accountSelected;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final themeLabel = themeMode == ThemeMode.dark
        ? appText('切换浅色', 'Switch to light')
        : appText('切换深色', 'Switch to dark');
    final collapseLabel = switch (sidebarState) {
      AppSidebarState.expanded => appText('折叠导航', 'Collapse sidebar'),
      AppSidebarState.collapsed => appText('隐藏导航', 'Hide sidebar'),
      AppSidebarState.hidden => appText('展开导航', 'Expand sidebar'),
    };
    final languageButton = Tooltip(
      message: appText('切换语言', 'Switch language'),
      child: _SidebarLanguageButton(
        appLanguage: appLanguage,
        compact: isCollapsed,
        onPressed: onToggleLanguage,
      ),
    );

    final themeButton = Tooltip(
      message: themeLabel,
      child: IconButton(
        iconSize: 20,
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
        iconSize: 20,
        onPressed: onOpenSettings,
        icon: const Icon(Icons.settings_rounded),
      ),
    );

    final collapseButton = Tooltip(
      message: collapseLabel,
      child: IconButton(
        iconSize: 20,
        onPressed: onCycleSidebarState,
        icon: Icon(switch (sidebarState) {
          AppSidebarState.expanded => Icons.keyboard_double_arrow_left_rounded,
          AppSidebarState.collapsed => Icons.visibility_off_outlined,
          AppSidebarState.hidden => Icons.keyboard_double_arrow_right_rounded,
        }),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isCollapsed)
          Column(
            mainAxisSize: MainAxisSize.min,
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SidebarFooterActionTile(
                icon: themeMode == ThemeMode.dark
                    ? Icons.light_mode_rounded
                    : Icons.dark_mode_rounded,
                label: themeLabel,
                onTap: onOpenThemeToggle,
              ),
              const SizedBox(height: 6),
              _SidebarFooterActionTile(
                icon: Icons.translate_rounded,
                label: appText('语言', 'Language'),
                trailingText: appLanguage == AppLanguage.zh ? '中文' : 'EN',
                onTap: onToggleLanguage,
              ),
              const SizedBox(height: 6),
              _SidebarFooterActionTile(
                icon: Icons.settings_rounded,
                label: appText('打开设置', 'Open settings'),
                onTap: onOpenSettings,
              ),
              const SizedBox(height: 6),
              _SidebarFooterActionTile(
                icon: switch (sidebarState) {
                  AppSidebarState.expanded =>
                    Icons.keyboard_double_arrow_left_rounded,
                  AppSidebarState.collapsed => Icons.visibility_off_outlined,
                  AppSidebarState.hidden =>
                    Icons.keyboard_double_arrow_right_rounded,
                },
                label: collapseLabel,
                onTap: onCycleSidebarState,
              ),
            ],
          ),
        const SizedBox(height: 8),
        if (isCollapsed)
          Tooltip(
            message: appText('账号', 'Account'),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: onOpenAccount,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: accountSelected
                      ? palette.accentMuted
                      : palette.surfaceSecondary,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: palette.strokeSoft),
                ),
                child: const Icon(Icons.account_circle_rounded),
              ),
            ),
          )
        else
          _SidebarAccountTile(selected: accountSelected, onTap: onOpenAccount),
      ],
    );
  }
}

class _SidebarFooterActionTile extends StatefulWidget {
  const _SidebarFooterActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailingText,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? trailingText;

  @override
  State<_SidebarFooterActionTile> createState() =>
      _SidebarFooterActionTileState();
}

class _SidebarFooterActionTileState extends State<_SidebarFooterActionTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Align(
        alignment: Alignment.centerLeft,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            color: _hovered ? palette.hover : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: widget.onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(widget.icon, size: 20, color: palette.textSecondary),
                    const SizedBox(width: 8),
                    Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    if (widget.trailingText != null) ...[
                      const SizedBox(width: 12),
                      Text(
                        widget.trailingText!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: palette.textSecondary,
                          fontWeight: FontWeight.w700,
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
    );
  }
}

class _SidebarAccountTile extends StatefulWidget {
  const _SidebarAccountTile({required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  @override
  State<_SidebarAccountTile> createState() => _SidebarAccountTileState();
}

class _SidebarAccountTileState extends State<_SidebarAccountTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final background = widget.selected
        ? palette.accentMuted
        : _hovered
        ? palette.hover
        : Colors.transparent;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Align(
        alignment: Alignment.centerLeft,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: widget.onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircleAvatar(radius: 16, child: Text('H')),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Haitao Pan',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 1),
                        Text(
                          appText('账号', 'Account'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarLanguageButton extends StatefulWidget {
  const _SidebarLanguageButton({
    required this.appLanguage,
    required this.compact,
    required this.onPressed,
  });

  final AppLanguage appLanguage;
  final bool compact;
  final VoidCallback onPressed;

  @override
  State<_SidebarLanguageButton> createState() => _SidebarLanguageButtonState();
}

class _SidebarLanguageButtonState extends State<_SidebarLanguageButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final size = widget.compact ? 44.0 : 58.0;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _hovered ? palette.hover : palette.surfaceSecondary,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: palette.strokeSoft),
          ),
          child: Text(
            widget.appLanguage.compactLabel,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: palette.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
