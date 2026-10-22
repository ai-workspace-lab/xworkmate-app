import 'package:flutter/material.dart';

import '../i18n/app_language.dart';
import '../models/app_models.dart';
import '../runtime/runtime_models.dart';
import '../theme/app_palette.dart';
import '../theme/app_theme.dart';
import 'pane_toggle_icon.dart';

part 'sidebar_navigation_footer.dart';
part 'sidebar_navigation_task_section.dart';

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
    this.accountWorkspaceFollowed = false,
    this.onToggleAccountWorkspaceFollowed,
    this.onOpenOnlineWorkspace,
    this.expandedWidthOverride,
    this.marginOverride,
    this.showCollapseControl = true,
    this.availableDestinations,
    this.favoriteDestinations = const <AssistantFocusEntry>{},
    this.onToggleFavorite,
    this.currentSettingsTab,
    this.availableSettingsTabs = const <SettingsTab>[],
    this.onSettingsTabChanged,
    this.taskItems = const <SidebarTaskItem>[],
    this.visibleExecutionTargets = const <AssistantExecutionTarget>[
      AssistantExecutionTarget.gateway,
    ],
    this.assistantSkillCount = 0,
    this.onRefreshTasks,
    this.onCreateTask,
    this.onOpenBotTeam,
    this.onOpenScheduledTasks,
    this.onReturnToAssistant,
    this.onSelectTask,
    this.onArchiveTask,
    this.onRenameTask,
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
  final bool accountWorkspaceFollowed;
  final Future<void> Function()? onToggleAccountWorkspaceFollowed;
  final VoidCallback? onOpenOnlineWorkspace;
  final double? expandedWidthOverride;
  final EdgeInsetsGeometry? marginOverride;
  final bool showCollapseControl;
  final Set<WorkspaceDestination>? availableDestinations;
  final Set<AssistantFocusEntry> favoriteDestinations;
  final Future<void> Function(AssistantFocusEntry section)? onToggleFavorite;
  final SettingsTab? currentSettingsTab;
  final List<SettingsTab> availableSettingsTabs;
  final ValueChanged<SettingsTab>? onSettingsTabChanged;
  final List<SidebarTaskItem> taskItems;
  final List<AssistantExecutionTarget> visibleExecutionTargets;
  final int assistantSkillCount;
  final Future<void> Function()? onRefreshTasks;
  final Future<void> Function()? onCreateTask;
  final VoidCallback? onOpenBotTeam;
  final VoidCallback? onOpenScheduledTasks;
  final VoidCallback? onReturnToAssistant;
  final Future<void> Function(String sessionKey)? onSelectTask;
  final Future<void> Function(String sessionKey)? onArchiveTask;
  final Future<void> Function(String sessionKey, String title)? onRenameTask;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isCollapsed = sidebarState == AppSidebarState.collapsed;
    final expandedWidth =
        expandedWidthOverride ??
        (appLanguage == AppLanguage.zh
            ? AppSizes.sidebarExpandedWidthZh
            : AppSizes.sidebarExpandedWidthEn);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: isCollapsed ? AppSizes.sidebarCollapsedWidth : expandedWidth,
      height: double.infinity,
      margin: marginOverride ?? EdgeInsets.zero,
      // The pane is not a card: no radius, no border. It sits flush against the
      // content pane and is separated from it by the overlaid 1px boundary in
      // the shell. Radius and stroke belong to the content cards inside.
      decoration: BoxDecoration(color: palette.sidebar),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 4),
            if (isCollapsed && showCollapseControl) ...[
              SidebarHeader(isCollapsed: true, onTap: onExpandFromCollapsed),
              const SizedBox(height: AppSpacing.xs),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!isCollapsed)
                    Expanded(
                      child: SidebarTaskSection(
                        currentSection: currentSection,
                        onOpenHome: onOpenHome,
                        items: taskItems,
                        visibleExecutionTargets: visibleExecutionTargets,
                        skillCount: assistantSkillCount,
                        showCollapseControl: showCollapseControl,
                        onCycleSidebarState: onCycleSidebarState,
                        onRefreshTasks: onRefreshTasks,
                        onCreateTask: onCreateTask,
                        onOpenBotTeam: onOpenBotTeam,
                        onOpenScheduledTasks: onOpenScheduledTasks,
                        onReturnToAssistant: onReturnToAssistant,
                        onSelectTask: onSelectTask,
                        onArchiveTask: onArchiveTask,
                        onRenameTask: onRenameTask,
                      ),
                    )
                  else
                    Expanded(
                      child: Column(
                        children: [
                          _SidebarCollapsedNavButton(
                            key: const Key('sidebar-collapsed-workbench-button'),
                            icon: Icons.view_quilt_outlined,
                            tooltip: appText('工作台', 'Workbench'),
                            selected: currentSection == WorkspaceDestination.workbench,
                            onTap: onOpenHome,
                          ),
                          const SizedBox(height: 6),
                          if (onCreateTask != null) ...[
                            _SidebarCollapsedNavButton(
                              key: const Key('sidebar-collapsed-new-task-button'),
                              icon: Icons.edit_note_rounded,
                              tooltip: appText('新对话', 'New conversation'),
                              selected: false,
                              onTap: () async {
                                await onCreateTask!();
                              },
                            ),
                            const SizedBox(height: 6),
                          ],
                          if (onOpenBotTeam != null) ...[
                            _SidebarCollapsedNavButton(
                              key: const Key('sidebar-collapsed-bot-team-button'),
                              icon: Icons.groups_2_outlined,
                              tooltip: appText('Bot 团队', 'Bot team'),
                              selected: currentSection == WorkspaceDestination.botTeam,
                              onTap: onOpenBotTeam,
                            ),
                            const SizedBox(height: 6),
                          ],
                          if (onOpenScheduledTasks != null) ...[
                            _SidebarCollapsedNavButton(
                              key: const Key('sidebar-collapsed-scheduled-tasks-button'),
                              icon: Icons.access_time_rounded,
                              tooltip: appText('定时任务', 'Scheduled tasks'),
                              selected:
                                  currentSection == WorkspaceDestination.scheduledTasks,
                              onTap: onOpenScheduledTasks,
                            ),
                            const SizedBox(height: 6),
                          ],
                          const Spacer(),
                        ],
                      ),
                    ),
                  const SizedBox(height: AppSpacing.xs),
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
                    onOpenAccount: onOpenAccount,
                    accountName: accountName,
                    accountSubtitle: accountSubtitle,
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
          key: const Key('sidebar-header-expand-button'),
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
        color: palette.surfacePrimary,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: palette.strokeSoft),
      ),
      child: Center(
        child: PaneToggleIcon(
          side: PaneSide.left,
          size: size * 0.6,
          color: palette.textSecondary,
        ),
      ),
    );
  }
}

class _SidebarCollapsedNavButton extends StatefulWidget {
  const _SidebarCollapsedNavButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.selected = false,
    this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback? onTap;

  @override
  State<_SidebarCollapsedNavButton> createState() =>
      _SidebarCollapsedNavButtonState();
}

class _SidebarCollapsedNavButtonState
    extends State<_SidebarCollapsedNavButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final enabled = widget.onTap != null;
    final content = Center(
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Material(
          color: widget.selected
              ? palette.chromeSurfacePressed
              : (_hovered && enabled
                  ? palette.hover
                  : palette.surfacePrimary),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: widget.onTap,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: palette.strokeSoft),
              ),
              child: Center(
                child: Icon(
                  widget.icon,
                  size: 20,
                  color: !enabled
                      ? palette.textMuted
                      : widget.selected
                      ? palette.textPrimary
                      : palette.textSecondary,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 200),
      child: content,
    );
  }
}
