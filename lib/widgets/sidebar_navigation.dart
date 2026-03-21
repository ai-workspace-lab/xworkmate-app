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
    this.onOpenOnlineWorkspace,
    this.expandedWidthOverride,
    this.marginOverride,
    this.showCollapseControl = true,
    this.favoriteDestinations = const <WorkspaceDestination>{},
    this.onToggleFavorite,
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
  final VoidCallback? onOpenOnlineWorkspace;
  final double? expandedWidthOverride;
  final EdgeInsetsGeometry? marginOverride;
  final bool showCollapseControl;
  final Set<WorkspaceDestination> favoriteDestinations;
  final Future<void> Function(WorkspaceDestination section)? onToggleFavorite;

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
        (appLanguage == AppLanguage.zh
            ? AppSizes.sidebarExpandedWidthZh
            : AppSizes.sidebarExpandedWidthEn);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: isExpanded ? expandedWidth : AppSizes.sidebarCollapsedWidth,
      height: double.infinity,
      margin: marginOverride ?? const EdgeInsets.fromLTRB(4, 4, 4, 0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            palette.chromeHighlight.withValues(alpha: 0.9),
            palette.chromeSurface.withValues(alpha: 0.92),
          ],
        ),
        borderRadius: BorderRadius.circular(AppRadius.sidebar),
        border: Border.all(color: palette.chromeStroke),
        boxShadow: [palette.chromeShadowAmbient],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SidebarHeader(
              isCollapsed: !isExpanded,
              onTap: isCollapsed ? onExpandFromCollapsed : null,
            ),
            const SizedBox(height: 6),
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
                            favoriteDestinations: favoriteDestinations,
                            onToggleFavorite: onToggleFavorite,
                            onSectionChanged: onSectionChanged,
                          ),
                          const SizedBox(height: 6),
                          _SidebarSectionGroup(
                            title: appText('工作区', 'Workspace'),
                            sections: _workspaceSections,
                            currentSection: currentSection,
                            collapsed: isCollapsed,
                            emphasis: _SidebarItemEmphasis.secondary,
                            favoriteDestinations: favoriteDestinations,
                            onToggleFavorite: onToggleFavorite,
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
                    favoriteDestinations: favoriteDestinations,
                    onToggleFavorite: onToggleFavorite,
                    onSectionChanged: onSectionChanged,
                  ),
                  const SizedBox(height: 6),
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
                    onOpenOnlineWorkspace: onOpenOnlineWorkspace,
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
      width: isCollapsed ? 36 : 28,
      height: isCollapsed ? 36 : 28,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            palette.chromeHighlight.withValues(alpha: 0.88),
            palette.chromeSurfacePressed.withValues(alpha: 0.92),
          ],
        ),
        border: Border.all(color: palette.chromeStroke),
        boxShadow: [palette.chromeShadowLift],
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
        child: Padding(padding: EdgeInsets.zero, child: content),
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
    required this.favoriteDestinations,
    this.onToggleFavorite,
    required this.onSectionChanged,
  });

  final String? title;
  final List<WorkspaceDestination> sections;
  final WorkspaceDestination currentSection;
  final bool collapsed;
  final _SidebarItemEmphasis emphasis;
  final Set<WorkspaceDestination> favoriteDestinations;
  final Future<void> Function(WorkspaceDestination section)? onToggleFavorite;
  final ValueChanged<WorkspaceDestination> onSectionChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!collapsed && title != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
            child: Text(
              title!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: palette.textMuted,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.28,
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
              favorite: favoriteDestinations.contains(section),
              showFavoriteToggle:
                  !collapsed &&
                  onToggleFavorite != null &&
                  kAssistantNavigationDestinationCandidates.contains(section),
              onToggleFavorite: onToggleFavorite == null
                  ? null
                  : () async {
                      await onToggleFavorite!(section);
                    },
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
    required this.favorite,
    required this.showFavoriteToggle,
    this.onToggleFavorite,
    required this.onTap,
  });

  final WorkspaceDestination section;
  final bool selected;
  final bool collapsed;
  final _SidebarItemEmphasis emphasis;
  final bool favorite;
  final bool showFavoriteToggle;
  final Future<void> Function()? onToggleFavorite;
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
        ? palette.surfacePrimary
        : _hovered
        ? palette.chromeSurfacePressed
        : Colors.transparent;
    final iconColor = widget.selected
        ? palette.textPrimary
        : palette.textSecondary;
    final height = isPrimary ? 36.0 : 32.0;
    final radius = AppRadius.button;

    return Tooltip(
      message: widget.collapsed ? _sectionLabel(widget.section) : '',
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            gradient: widget.selected || _hovered
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      palette.chromeHighlight.withValues(
                        alpha: widget.selected ? 0.84 : 0.7,
                      ),
                      background.withValues(
                        alpha: widget.selected ? 0.96 : 0.9,
                      ),
                    ],
                  )
                : null,
            color: widget.selected || _hovered ? null : Colors.transparent,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: widget.selected || _hovered
                  ? palette.chromeStroke
                  : Colors.transparent,
            ),
            boxShadow: widget.selected ? [palette.chromeShadowLift] : const [],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(radius),
              onTap: widget.onTap,
              child: Container(
                height: height,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: widget.collapsed
                    ? Center(
                        child: Icon(
                          _sectionIcon(widget.section, active: widget.selected),
                          size: AppSizes.sidebarIconSize,
                          color: iconColor,
                        ),
                      )
                    : Row(
                        children: [
                          SizedBox(
                            width: 20,
                            child: Icon(
                              _sectionIcon(
                                widget.section,
                                active: widget.selected,
                              ),
                              size: AppSizes.sidebarIconSize,
                              color: iconColor,
                            ),
                          ),
                          const SizedBox(width: 6),
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
                                        letterSpacing: isPrimary ? 0.02 : 0,
                                      ),
                            ),
                          ),
                          if (widget.showFavoriteToggle)
                            IconButton(
                              key: ValueKey<String>(
                                'sidebar-favorite-${widget.section.name}',
                              ),
                              tooltip: widget.favorite
                                  ? appText('取消关注', 'Remove from focused panel')
                                  : appText('加入关注', 'Add to focused panel'),
                              visualDensity: VisualDensity.compact,
                              splashRadius: 12,
                              onPressed: () async {
                                await widget.onToggleFavorite?.call();
                              },
                              icon: Icon(
                                widget.favorite
                                    ? Icons.star_rounded
                                    : Icons.star_outline_rounded,
                                size: 18,
                                color: widget.favorite
                                    ? palette.accent
                                    : palette.textMuted,
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

  IconData _sectionIcon(WorkspaceDestination section, {required bool active}) {
    return switch (section) {
      WorkspaceDestination.assistant =>
        active ? Icons.chat_bubble_rounded : Icons.chat_bubble_outline_rounded,
      WorkspaceDestination.tasks =>
        active ? Icons.layers_rounded : Icons.layers_outlined,
      WorkspaceDestination.skills =>
        active ? Icons.auto_awesome_rounded : Icons.auto_awesome_outlined,
      WorkspaceDestination.nodes =>
        active ? Icons.developer_board_rounded : Icons.developer_board_outlined,
      WorkspaceDestination.agents =>
        active ? Icons.hub_rounded : Icons.hub_outlined,
      WorkspaceDestination.mcpServer =>
        active ? Icons.dns_rounded : Icons.dns_outlined,
      WorkspaceDestination.clawHub =>
        active ? Icons.extension_rounded : Icons.extension_outlined,
      WorkspaceDestination.secrets =>
        active ? Icons.key_rounded : Icons.key_outlined,
      WorkspaceDestination.aiGateway =>
        active ? Icons.smart_toy_rounded : Icons.smart_toy_outlined,
      WorkspaceDestination.settings =>
        active ? Icons.settings_rounded : Icons.settings_outlined,
      WorkspaceDestination.account =>
        active ? Icons.account_circle_rounded : Icons.account_circle_outlined,
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
    this.onOpenOnlineWorkspace,
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
  final VoidCallback? onOpenOnlineWorkspace;

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
          Container(
            height: 1,
            color: palette.chromeStroke.withValues(alpha: 0.9),
          ),
          const SizedBox(height: 6),
          _SidebarLanguageButton(
            appLanguage: appLanguage,
            compact: true,
            tooltip: appText('切换语言', 'Toggle language'),
            onPressed: onToggleLanguage,
          ),
          const SizedBox(height: 6),
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
            const SizedBox(height: 6),
          ],
          _SidebarActionButton(
            icon: Icons.tune_rounded,
            tooltip: appText('设置', 'Settings'),
            onPressed: onOpenSettings,
          ),
          const SizedBox(height: 6),
          if (onOpenOnlineWorkspace != null) ...[
            _SidebarActionButton(
              icon: Icons.open_in_new_rounded,
              tooltip: appText('打开在线版', 'Open online workspace'),
              onPressed: onOpenOnlineWorkspace!,
            ),
            const SizedBox(height: 6),
          ],
          _SidebarAccountTile(
            selected: accountSelected,
            onTap: onOpenAccount,
            name: accountName,
            subtitle: accountSubtitle,
            onlineActionLabel: appText('在线版', 'Online'),
            onOpenOnlineWorkspace: onOpenOnlineWorkspace,
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 1,
          color: palette.chromeStroke.withValues(alpha: 0.9),
        ),
        const SizedBox(height: AppSpacing.xs),
        _SidebarNavItem(
          section: WorkspaceDestination.settings,
          selected: currentSection == WorkspaceDestination.settings,
          collapsed: false,
          emphasis: _SidebarItemEmphasis.secondary,
          favorite: false,
          showFavoriteToggle: false,
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
          onlineActionLabel: appText('在线版', 'Online'),
          onOpenOnlineWorkspace: onOpenOnlineWorkspace,
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
    final resolvedBackground = _hovered
        ? palette.chromeSurfacePressed
        : palette.chromeSurface;

    return Tooltip(
      message: widget.tooltip ?? '',
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                palette.chromeHighlight.withValues(
                  alpha: _hovered ? 0.94 : 0.88,
                ),
                resolvedBackground,
              ],
            ),
            borderRadius: BorderRadius.circular(AppRadius.button),
            border: Border.all(color: palette.chromeStroke),
            boxShadow: [
              _hovered ? palette.chromeShadowLift : palette.chromeShadowAmbient,
            ],
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
    this.onlineActionLabel,
    this.onOpenOnlineWorkspace,
  });

  final bool selected;
  final VoidCallback onTap;
  final String name;
  final String subtitle;
  final String? onlineActionLabel;
  final VoidCallback? onOpenOnlineWorkspace;

  @override
  State<_SidebarAccountTile> createState() => _SidebarAccountTileState();
}

class _SidebarAccountTileState extends State<_SidebarAccountTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final background = widget.selected
        ? palette.chromeSurface
        : _hovered
        ? palette.chromeSurfacePressed
        : Colors.transparent;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Align(
        alignment: Alignment.centerLeft,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            gradient: widget.selected || _hovered
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      palette.chromeHighlight.withValues(
                        alpha: widget.selected ? 0.96 : 0.84,
                      ),
                      background,
                    ],
                  )
                : null,
            color: widget.selected || _hovered ? null : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.button),
            border: Border.all(
              color: widget.selected || _hovered
                  ? palette.chromeStroke
                  : Colors.transparent,
            ),
            boxShadow: widget.selected ? [palette.chromeShadowLift] : const [],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.button),
              onTap: widget.onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs,
                  vertical: 6,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.max,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: palette.accentMuted,
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
                    if (widget.onOpenOnlineWorkspace != null &&
                        widget.onlineActionLabel != null) ...[
                      const SizedBox(width: AppSpacing.xs),
                      TextButton(
                        onPressed: widget.onOpenOnlineWorkspace,
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 28),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        child: Text(widget.onlineActionLabel!),
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
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  palette.chromeHighlight.withValues(
                    alpha: _hovered ? 0.94 : 0.88,
                  ),
                  _hovered
                      ? palette.chromeSurfacePressed
                      : palette.chromeSurface,
                ],
              ),
              borderRadius: BorderRadius.circular(AppRadius.button),
              border: Border.all(color: palette.chromeStroke),
              boxShadow: [
                _hovered
                    ? palette.chromeShadowLift
                    : palette.chromeShadowAmbient,
              ],
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
