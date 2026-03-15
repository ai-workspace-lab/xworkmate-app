import 'package:flutter/material.dart';

import '../i18n/app_language.dart';
import '../models/app_models.dart';
import '../theme/app_palette.dart';
import '../theme/app_theme.dart';

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
    required this.accountName,
    required this.accountSubtitle,
    this.expandedWidthOverride,
    this.marginOverride,
    this.showCollapseControl = true,
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
  final String accountName;
  final String accountSubtitle;
  final double? expandedWidthOverride;
  final EdgeInsetsGeometry? marginOverride;
  final bool showCollapseControl;

  static const _primarySections = <WorkspaceDestination>[
    WorkspaceDestination.assistant,
    WorkspaceDestination.tasks,
    WorkspaceDestination.skills,
  ];

  static const _workspaceSections = <WorkspaceDestination>[
    WorkspaceDestination.nodes,
    WorkspaceDestination.agents,
  ];

  static const _toolSections = <WorkspaceDestination>[
    WorkspaceDestination.mcpServer,
    WorkspaceDestination.clawHub,
    WorkspaceDestination.secrets,
    WorkspaceDestination.aiGateway,
  ];

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isExpanded = sidebarState == AppSidebarState.expanded;
    final isCollapsed = sidebarState == AppSidebarState.collapsed;
    final expandedWidth =
        expandedWidthOverride ??
        (appLanguage == AppLanguage.zh ? AppSizes.sidebarExpandedWidth : 220.0);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: isExpanded ? expandedWidth : AppSizes.sidebarCollapsedWidth,
      height: double.infinity,
      margin:
          marginOverride ??
          const EdgeInsets.fromLTRB(AppSpacing.xs, AppSpacing.xs, 6, 0),
      decoration: BoxDecoration(
        color: palette.sidebar,
        borderRadius: BorderRadius.circular(AppRadius.sidebar),
        border: Border.all(
          color: palette.sidebarBorder.withValues(alpha: 0.72),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.xs,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SidebarHeader(
              isCollapsed: !isExpanded,
              onTap: isCollapsed ? onExpandFromCollapsed : null,
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.zero,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _SidebarSectionGroup(
                            sections: _primarySections,
                            currentSection: currentSection,
                            collapsed: isCollapsed,
                            emphasis: _SidebarItemEmphasis.primary,
                            onSectionChanged: onSectionChanged,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          _SidebarSectionGroup(
                            title: appText('工作区', 'Workspace'),
                            sections: _workspaceSections,
                            currentSection: currentSection,
                            collapsed: isCollapsed,
                            emphasis: _SidebarItemEmphasis.secondary,
                            onSectionChanged: onSectionChanged,
                          ),
                        ],
                      ),
                    ),
                  ),
                  _SidebarSectionGroup(
                    title: appText('工具', 'Tools'),
                    sections: _toolSections,
                    currentSection: currentSection,
                    collapsed: isCollapsed,
                    emphasis: _SidebarItemEmphasis.secondary,
                    onSectionChanged: onSectionChanged,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SidebarFooter(
                    isCollapsed: isCollapsed,
                    currentSection: currentSection,
                    appLanguage: appLanguage,
                    themeMode: themeMode,
                    onToggleLanguage: onToggleLanguage,
                    onOpenThemeToggle: onOpenThemeToggle,
                    onOpenSettings: () =>
                        onSectionChanged(WorkspaceDestination.settings),
                    sidebarState: sidebarState,
                    onCycleSidebarState: onCycleSidebarState,
                    onOpenAccount: onOpenAccount,
                    accountName: accountName,
                    accountSubtitle: accountSubtitle,
                    accountSelected:
                        currentSection == WorkspaceDestination.account,
                    showCollapseControl: showCollapseControl,
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

    final content = Container(
      width: isCollapsed ? AppSizes.sidebarItemHeight : 36,
      height: isCollapsed ? AppSizes.sidebarItemHeight : 36,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: palette.surfaceSecondary,
        border: Border.all(color: palette.strokeSoft),
      ),
      child: Icon(
        Icons.crop_square_rounded,
        color: palette.textSecondary,
        size: AppSizes.sidebarIconSize,
      ),
    );

    if (onTap == null) {
      return content;
    }

    return Tooltip(
      message: appText('展开导航', 'Expand sidebar'),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.button),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: content,
        ),
      ),
    );
  }
}

class _SidebarSectionGroup extends StatelessWidget {
  const _SidebarSectionGroup({
    this.title,
    required this.sections,
    required this.currentSection,
    required this.collapsed,
    required this.emphasis,
    required this.onSectionChanged,
  });

  final String? title;
  final List<WorkspaceDestination> sections;
  final WorkspaceDestination currentSection;
  final bool collapsed;
  final _SidebarItemEmphasis emphasis;
  final ValueChanged<WorkspaceDestination> onSectionChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!collapsed && title != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
            child: Text(
              title!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: palette.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
        ...sections.map(
          (section) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
            child: _SidebarNavItem(
              section: section,
              selected: currentSection == section,
              collapsed: collapsed,
              emphasis: emphasis,
              onTap: () => onSectionChanged(section),
            ),
          ),
        ),
      ],
    );
  }
}

class _SidebarNavItem extends StatefulWidget {
  const _SidebarNavItem({
    required this.section,
    required this.selected,
    required this.collapsed,
    required this.emphasis,
    required this.onTap,
  });

  final WorkspaceDestination section;
  final bool selected;
  final bool collapsed;
  final _SidebarItemEmphasis emphasis;
  final VoidCallback onTap;

  @override
  State<_SidebarNavItem> createState() => _SidebarNavItemState();
}

class _SidebarNavItemState extends State<_SidebarNavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    final isPrimary = widget.emphasis == _SidebarItemEmphasis.primary;
    final background = widget.selected
        ? palette.accentMuted
        : _hovered
        ? palette.hover
        : Colors.transparent;
    final iconColor = widget.selected ? palette.accent : palette.textSecondary;
    final height = isPrimary ? 46.0 : AppSizes.sidebarItemHeight;
    final radius = isPrimary ? 14.0 : AppRadius.button;

    return Tooltip(
      message: widget.collapsed ? _sectionLabel(widget.section) : '',
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(radius),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(radius),
              onTap: widget.onTap,
              child: Container(
                height: height,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                child: widget.collapsed
                    ? Center(
                        child: Icon(
                          _sectionIcon(widget.section),
                          size: AppSizes.sidebarIconSize,
                          color: iconColor,
                        ),
                      )
                    : Row(
                        children: [
                          SizedBox(
                            width: isPrimary ? 28 : 24,
                            child: Icon(
                              _sectionIcon(widget.section),
                              size: AppSizes.sidebarIconSize,
                              color: iconColor,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(
                            child: Text(
                              _sectionLabel(widget.section),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  (isPrimary
                                          ? theme.textTheme.titleMedium
                                          : theme.textTheme.labelLarge)
                                      ?.copyWith(
                                        color: widget.selected
                                            ? palette.textPrimary
                                            : palette.textSecondary,
                                        fontWeight: isPrimary
                                            ? FontWeight.w600
                                            : FontWeight.w500,
                                      ),
                            ),
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

  IconData _sectionIcon(WorkspaceDestination section) {
    return switch (section) {
      WorkspaceDestination.assistant => Icons.edit_outlined,
      WorkspaceDestination.tasks => Icons.schedule_rounded,
      WorkspaceDestination.skills => Icons.blur_on_rounded,
      WorkspaceDestination.nodes => Icons.developer_board_rounded,
      WorkspaceDestination.agents => Icons.hub_rounded,
      WorkspaceDestination.mcpServer => Icons.dns_rounded,
      WorkspaceDestination.clawHub => Icons.extension_rounded,
      WorkspaceDestination.secrets => Icons.key_rounded,
      WorkspaceDestination.aiGateway => Icons.smart_toy_rounded,
      WorkspaceDestination.settings => Icons.tune_rounded,
      WorkspaceDestination.account => Icons.account_circle_rounded,
    };
  }

  String _sectionLabel(WorkspaceDestination section) {
    return switch (section) {
      WorkspaceDestination.assistant => appText('新对话', 'New conversation'),
      WorkspaceDestination.tasks => appText('自动化', 'Automation'),
      WorkspaceDestination.skills => appText('技能', 'Skills'),
      WorkspaceDestination.nodes => appText('节点', 'Nodes'),
      WorkspaceDestination.agents => appText('代理', 'Agents'),
      WorkspaceDestination.mcpServer => 'MCP Hub',
      WorkspaceDestination.clawHub => 'ClawHub',
      WorkspaceDestination.secrets => appText('密钥', 'Secrets'),
      WorkspaceDestination.aiGateway => 'AI Gateway',
      WorkspaceDestination.settings => appText('设置', 'Settings'),
      WorkspaceDestination.account => appText('账户', 'Account'),
    };
  }
}

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
    required this.sidebarState,
    required this.onCycleSidebarState,
    required this.onOpenAccount,
    required this.accountName,
    required this.accountSubtitle,
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
  final AppSidebarState sidebarState;
  final VoidCallback onCycleSidebarState;
  final VoidCallback onOpenAccount;
  final String accountName;
  final String accountSubtitle;
  final bool accountSelected;
  final bool showCollapseControl;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final themeToggleTooltip = themeMode == ThemeMode.dark
        ? appText('切换浅色', 'Switch to light')
        : appText('切换深色', 'Switch to dark');

    if (isCollapsed) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(height: 1, color: palette.sidebarBorder),
          const SizedBox(height: AppSpacing.xs),
          _SidebarLanguageButton(
            appLanguage: appLanguage,
            compact: true,
            tooltip: appText('切换语言', 'Toggle language'),
            onPressed: onToggleLanguage,
          ),
          const SizedBox(height: AppSpacing.xs),
          _SidebarActionButton(
            icon: themeMode == ThemeMode.dark
                ? Icons.dark_mode_rounded
                : themeMode == ThemeMode.light
                ? Icons.light_mode_rounded
                : Icons.brightness_auto_rounded,
            tooltip: themeToggleTooltip,
            onPressed: onOpenThemeToggle,
          ),
          const SizedBox(height: AppSpacing.xs),
          if (showCollapseControl) ...[
            _SidebarActionButton(
              icon: _sidebarStateIcon(sidebarState),
              tooltip: _sidebarStateLabel(sidebarState),
              onPressed: onCycleSidebarState,
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          _SidebarActionButton(
            icon: Icons.tune_rounded,
            tooltip: appText('设置', 'Settings'),
            onPressed: onOpenSettings,
          ),
          const SizedBox(height: AppSpacing.xs),
          _SidebarAccountTile(
            selected: accountSelected,
            onTap: onOpenAccount,
            name: accountName,
            subtitle: accountSubtitle,
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(height: 1, color: palette.sidebarBorder),
        const SizedBox(height: AppSpacing.xs),
        _SidebarNavItem(
          section: WorkspaceDestination.settings,
          selected: currentSection == WorkspaceDestination.settings,
          collapsed: false,
          emphasis: _SidebarItemEmphasis.secondary,
          onTap: onOpenSettings,
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            Expanded(
              child: _SidebarLanguageButton(
                appLanguage: appLanguage,
                compact: false,
                tooltip: appText('切换语言', 'Toggle language'),
                onPressed: onToggleLanguage,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            _SidebarActionButton(
              icon: themeMode == ThemeMode.dark
                  ? Icons.dark_mode_rounded
                  : themeMode == ThemeMode.light
                  ? Icons.light_mode_rounded
                  : Icons.brightness_auto_rounded,
              tooltip: themeToggleTooltip,
              onPressed: onOpenThemeToggle,
            ),
            const SizedBox(width: AppSpacing.xs),
            if (showCollapseControl)
              _SidebarActionButton(
                icon: _sidebarStateIcon(sidebarState),
                tooltip: _sidebarStateLabel(sidebarState),
                onPressed: onCycleSidebarState,
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        _SidebarAccountTile(
          selected: accountSelected,
          onTap: onOpenAccount,
          name: accountName,
          subtitle: accountSubtitle,
        ),
      ],
    );
  }

  IconData _sidebarStateIcon(AppSidebarState state) {
    return switch (state) {
      AppSidebarState.expanded => Icons.view_sidebar_rounded,
      AppSidebarState.collapsed => Icons.menu_rounded,
      AppSidebarState.hidden => Icons.view_sidebar_rounded,
    };
  }

  String _sidebarStateLabel(AppSidebarState state) {
    return switch (state) {
      AppSidebarState.expanded => appText('收起侧边栏', 'Collapse sidebar'),
      AppSidebarState.collapsed => appText('展开侧边栏', 'Expand sidebar'),
      AppSidebarState.hidden => appText('展开侧边栏', 'Expand sidebar'),
    };
  }
}

enum _SidebarItemEmphasis { primary, secondary }

class _SidebarActionButton extends StatefulWidget {
  const _SidebarActionButton({
    required this.icon,
    this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String? tooltip;
  final VoidCallback onPressed;

  @override
  State<_SidebarActionButton> createState() => _SidebarActionButtonState();
}

class _SidebarActionButtonState extends State<_SidebarActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final background = _hovered ? palette.hover : Colors.transparent;

    return Tooltip(
      message: widget.tooltip ?? '',
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.button),
              onTap: widget.onPressed,
              child: Container(
                height: AppSizes.sidebarItemHeight,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                child: Center(
                  child: Icon(
                    widget.icon,
                    size: AppSizes.sidebarIconSize,
                    color: palette.textSecondary,
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

class _SidebarAccountTile extends StatefulWidget {
  const _SidebarAccountTile({
    required this.selected,
    required this.onTap,
    required this.name,
    required this.subtitle,
  });

  final bool selected;
  final VoidCallback onTap;
  final String name;
  final String subtitle;

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
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.button),
              onTap: widget.onTap,
              child: Container(
                height: AppSizes.sidebarItemHeight,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                child: Row(
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    CircleAvatar(
                      radius: 14,
                      child: Text(
                        widget.name.trim().isEmpty
                            ? 'X'
                            : widget.name.trim().substring(0, 1).toUpperCase(),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
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
    required this.tooltip,
    required this.onPressed,
  });

  final AppLanguage appLanguage;
  final bool compact;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  State<_SidebarLanguageButton> createState() => _SidebarLanguageButtonState();
}

class _SidebarLanguageButtonState extends State<_SidebarLanguageButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final size = widget.compact ? AppSizes.sidebarItemHeight : 44.0;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Tooltip(
        message: widget.tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.button),
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _hovered ? palette.hover : palette.surfaceSecondary,
              borderRadius: BorderRadius.circular(AppRadius.button),
              border: Border.all(color: palette.strokeSoft),
            ),
            child: Text(
              widget.appLanguage.compactLabel,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: palette.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
