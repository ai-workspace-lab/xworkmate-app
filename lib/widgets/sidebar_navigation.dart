import 'package:flutter/material.dart';

import '../i18n/app_language.dart';
import '../models/app_models.dart';
import '../theme/app_palette.dart';
import '../theme/app_theme.dart';
import 'chrome_quick_action_buttons.dart';

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
    this.onOpenHome,
    required this.accountName,
    required this.accountSubtitle,
    this.onOpenOnlineWorkspace,
    this.expandedWidthOverride,
    this.marginOverride,
    this.showCollapseControl = true,
    this.availableDestinations,
    this.favoriteDestinations = const <AssistantFocusEntry>{},
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
  final VoidCallback? onOpenHome;
  final String accountName;
  final String accountSubtitle;
  final VoidCallback? onOpenOnlineWorkspace;
  final double? expandedWidthOverride;
  final EdgeInsetsGeometry? marginOverride;
  final bool showCollapseControl;
  final Set<WorkspaceDestination>? availableDestinations;
  final Set<AssistantFocusEntry> favoriteDestinations;
  final Future<void> Function(AssistantFocusEntry section)? onToggleFavorite;

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
    final primarySections = _filterSections(_primarySections);
    final workspaceSections = _filterSections(_workspaceSections);
    final toolSections = _filterSections(_toolSections);
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
                          if (primarySections.isNotEmpty)
                            _SidebarSectionGroup(
                              sections: primarySections,
                              currentSection: currentSection,
                              collapsed: isCollapsed,
                              emphasis: _SidebarItemEmphasis.primary,
                              favoriteDestinations: favoriteDestinations,
                              onToggleFavorite: onToggleFavorite,
                              onOpenHome: onOpenHome,
                              onSectionChanged: onSectionChanged,
                            ),
                          if (primarySections.isNotEmpty &&
                              workspaceSections.isNotEmpty)
                            const SizedBox(height: 6),
                          if (workspaceSections.isNotEmpty)
                            _SidebarSectionGroup(
                              title: appText('工作区', 'Workspace'),
                              sections: workspaceSections,
                              currentSection: currentSection,
                              collapsed: isCollapsed,
                              emphasis: _SidebarItemEmphasis.secondary,
                              favoriteDestinations: favoriteDestinations,
                              onToggleFavorite: onToggleFavorite,
                              onOpenHome: onOpenHome,
                              onSectionChanged: onSectionChanged,
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (toolSections.isNotEmpty)
                    _SidebarSectionGroup(
                      title: appText('工具', 'Tools'),
                      sections: toolSections,
                      currentSection: currentSection,
                      collapsed: isCollapsed,
                      emphasis: _SidebarItemEmphasis.secondary,
                      favoriteDestinations: favoriteDestinations,
                      onToggleFavorite: onToggleFavorite,
                      onOpenHome: onOpenHome,
                      onSectionChanged: onSectionChanged,
                    ),
                  if (toolSections.isNotEmpty) const SizedBox(height: 6),
                  SidebarFooter(
                    isCollapsed: isCollapsed,
                    currentSection: currentSection,
                    appLanguage: appLanguage,
                    themeMode: themeMode,
                    onToggleLanguage: onToggleLanguage,
                    onOpenThemeToggle: onOpenThemeToggle,
                    onOpenSettings: () =>
                        onSectionChanged(WorkspaceDestination.settings),
                    showSettingsButton:
                        availableDestinations == null ||
                        availableDestinations!.contains(
                          WorkspaceDestination.settings,
                        ),
                    favoriteDestinations: favoriteDestinations,
                    onToggleFavorite: onToggleFavorite,
                    sidebarState: sidebarState,
                    onCycleSidebarState: onCycleSidebarState,
                    onOpenAccount: onOpenAccount,
                    showAccountButton:
                        availableDestinations == null ||
                        availableDestinations!.contains(
                          WorkspaceDestination.account,
                        ),
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

  List<WorkspaceDestination> _filterSections(
    List<WorkspaceDestination> sections,
  ) {
    final allowed = availableDestinations;
    if (allowed == null) {
      return sections;
    }
    return sections.where(allowed.contains).toList(growable: false);
  }
}

class SidebarHeader extends StatelessWidget {
  const SidebarHeader({super.key, required this.isCollapsed, this.onTap});

  final bool isCollapsed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = _SidebarHeaderChevron(
      size: isCollapsed ? 36 : 28,
      borderRadius: isCollapsed ? 10 : 8,
    );
    final alignedContent = Align(
      alignment: Alignment.centerRight,
      child: content,
    );

    if (onTap == null) {
      return alignedContent;
    }

    return Tooltip(
      message: appText('展开导航', 'Expand sidebar'),
      child: Align(
        alignment: Alignment.centerRight,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.button),
          onTap: onTap,
          child: Padding(padding: EdgeInsets.zero, child: content),
        ),
      ),
    );
  }
}

class _SidebarHeaderChevron extends StatelessWidget {
  const _SidebarHeaderChevron({required this.size, required this.borderRadius});

  final double size;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            palette.chromeHighlight.withValues(alpha: 0.9),
            palette.chromeSurface,
          ],
        ),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: palette.chromeStroke),
        boxShadow: [palette.chromeShadowAmbient],
      ),
      child: Center(
        child: Icon(
          Icons.chevron_right_rounded,
          size: size * 0.72,
          color: palette.textSecondary,
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
    required this.favoriteDestinations,
    this.onToggleFavorite,
    this.onOpenHome,
    required this.onSectionChanged,
  });

  final String? title;
  final List<WorkspaceDestination> sections;
  final WorkspaceDestination currentSection;
  final bool collapsed;
  final _SidebarItemEmphasis emphasis;
  final Set<AssistantFocusEntry> favoriteDestinations;
  final Future<void> Function(AssistantFocusEntry section)? onToggleFavorite;
  final VoidCallback? onOpenHome;
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
        ...sections.map((section) {
          final useHomeShortcut =
              currentSection == WorkspaceDestination.settings &&
              section == WorkspaceDestination.assistant;
          final focusEntry = switch (section) {
            WorkspaceDestination.tasks => AssistantFocusEntry.tasks,
            WorkspaceDestination.skills => AssistantFocusEntry.skills,
            WorkspaceDestination.nodes => AssistantFocusEntry.nodes,
            WorkspaceDestination.agents => AssistantFocusEntry.agents,
            WorkspaceDestination.mcpServer => AssistantFocusEntry.mcpServer,
            WorkspaceDestination.clawHub => AssistantFocusEntry.clawHub,
            WorkspaceDestination.secrets => AssistantFocusEntry.secrets,
            WorkspaceDestination.aiGateway => AssistantFocusEntry.aiGateway,
            WorkspaceDestination.settings => AssistantFocusEntry.settings,
            WorkspaceDestination.assistant || WorkspaceDestination.account =>
              null,
          };
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
            child: _SidebarNavItem(
              section: section,
              selected: currentSection == section,
              collapsed: collapsed,
              emphasis: emphasis,
              favorite: focusEntry != null && favoriteDestinations.contains(focusEntry),
              showFavoriteToggle:
                  !collapsed &&
                  focusEntry != null &&
                  onToggleFavorite != null &&
                  kAssistantNavigationDestinationCandidates.contains(focusEntry),
              labelOverride: useHomeShortcut
                  ? appText('回到 APP首页', 'Back to app home')
                  : null,
              onToggleFavorite: onToggleFavorite == null || focusEntry == null
                  ? null
                  : () async {
                      await onToggleFavorite!(focusEntry);
                    },
              onTap: useHomeShortcut && onOpenHome != null
                  ? onOpenHome!
                  : () => onSectionChanged(section),
            ),
          );
        }),
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
    this.labelOverride,
    this.onToggleFavorite,
    required this.onTap,
  });

  final WorkspaceDestination section;
  final bool selected;
  final bool collapsed;
  final _SidebarItemEmphasis emphasis;
  final bool favorite;
  final bool showFavoriteToggle;
  final String? labelOverride;
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
    final label = widget.labelOverride ?? _sectionLabel(widget.section);
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
      message: widget.collapsed ? label : '',
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
                              label,
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
      WorkspaceDestination.aiGateway => 'LLM API',
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
    required this.showSettingsButton,
    required this.favoriteDestinations,
    this.onToggleFavorite,
    required this.sidebarState,
    required this.onCycleSidebarState,
    required this.onOpenAccount,
    required this.showAccountButton,
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
  final bool showSettingsButton;
  final Set<AssistantFocusEntry> favoriteDestinations;
  final Future<void> Function(AssistantFocusEntry entry)? onToggleFavorite;
  final AppSidebarState sidebarState;
  final VoidCallback onCycleSidebarState;
  final VoidCallback onOpenAccount;
  final bool showAccountButton;
  final String accountName;
  final String accountSubtitle;
  final bool accountSelected;
  final bool showCollapseControl;
  final VoidCallback? onOpenOnlineWorkspace;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final themeToggleTooltip = chromeThemeToggleTooltip(themeMode);

    if (isCollapsed) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 1,
            color: palette.chromeStroke.withValues(alpha: 0.9),
          ),
          const SizedBox(height: 6),
          ChromeLanguageActionButton(
            appLanguage: appLanguage,
            compact: true,
            tooltip: appText('切换语言', 'Toggle language'),
            onPressed: onToggleLanguage,
            favorite: favoriteDestinations.contains(AssistantFocusEntry.language),
            showFavoriteToggle: onToggleFavorite != null,
            favoriteButtonKey: const ValueKey<String>(
              'sidebar-favorite-language',
            ),
            onToggleFavorite: onToggleFavorite == null
                ? null
                : () => onToggleFavorite!(AssistantFocusEntry.language),
          ),
          const SizedBox(height: 6),
          ChromeIconActionButton(
            icon: chromeThemeToggleIcon(themeMode),
            tooltip: themeToggleTooltip,
            onPressed: onOpenThemeToggle,
            favorite: favoriteDestinations.contains(AssistantFocusEntry.theme),
            showFavoriteToggle: onToggleFavorite != null,
            favoriteButtonKey: const ValueKey<String>('sidebar-favorite-theme'),
            onToggleFavorite: onToggleFavorite == null
                ? null
                : () => onToggleFavorite!(AssistantFocusEntry.theme),
          ),
          const SizedBox(height: AppSpacing.xs),
          if (showCollapseControl) ...[
            ChromeIconActionButton(
              icon: _sidebarStateIcon(sidebarState),
              tooltip: _sidebarStateLabel(sidebarState),
              onPressed: onCycleSidebarState,
            ),
            const SizedBox(height: 6),
          ],
          if (showSettingsButton) ...[
            ChromeIconActionButton(
              icon: Icons.tune_rounded,
              tooltip: appText('设置', 'Settings'),
              onPressed: onOpenSettings,
            ),
            const SizedBox(height: 6),
          ],
          if (onOpenOnlineWorkspace != null) ...[
            ChromeIconActionButton(
              icon: Icons.open_in_new_rounded,
              tooltip: appText('打开在线版', 'Open online workspace'),
              onPressed: onOpenOnlineWorkspace!,
            ),
            const SizedBox(height: 6),
          ],
          if (showAccountButton)
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
        if (showSettingsButton) ...[
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
        ],
        Row(
          children: [
            Expanded(
              child: ChromeLanguageActionButton(
                appLanguage: appLanguage,
                compact: false,
                tooltip: appText('切换语言', 'Toggle language'),
                onPressed: onToggleLanguage,
                favorite: favoriteDestinations.contains(
                  AssistantFocusEntry.language,
                ),
                showFavoriteToggle: onToggleFavorite != null,
                favoriteButtonKey: const ValueKey<String>(
                  'sidebar-favorite-language',
                ),
                onToggleFavorite: onToggleFavorite == null
                    ? null
                    : () => onToggleFavorite!(AssistantFocusEntry.language),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            ChromeIconActionButton(
              icon: chromeThemeToggleIcon(themeMode),
              tooltip: themeToggleTooltip,
              onPressed: onOpenThemeToggle,
              favorite: favoriteDestinations.contains(AssistantFocusEntry.theme),
              showFavoriteToggle: onToggleFavorite != null,
              favoriteButtonKey: const ValueKey<String>(
                'sidebar-favorite-theme',
              ),
              onToggleFavorite: onToggleFavorite == null
                  ? null
                  : () => onToggleFavorite!(AssistantFocusEntry.theme),
            ),
            const SizedBox(width: AppSpacing.xs),
            if (showCollapseControl)
              ChromeIconActionButton(
                icon: _sidebarStateIcon(sidebarState),
                tooltip: _sidebarStateLabel(sidebarState),
                onPressed: onCycleSidebarState,
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        if (showAccountButton)
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
