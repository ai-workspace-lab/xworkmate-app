import 'package:flutter/material.dart';

import '../i18n/app_language.dart';
import '../models/app_models.dart';
import '../runtime/runtime_models.dart';
import '../theme/app_palette.dart';
import '../theme/app_theme.dart';

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
      AssistantExecutionTarget.singleAgent,
      AssistantExecutionTarget.local,
      AssistantExecutionTarget.remote,
    ],
    this.assistantSkillCount = 0,
    this.onRefreshTasks,
    this.onCreateTask,
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
      margin: marginOverride ?? const EdgeInsets.fromLTRB(4, 4, 4, 0),
      decoration: BoxDecoration(
        color: palette.chromeSurface,
        borderRadius: BorderRadius.circular(AppRadius.sidebar),
        border: Border.all(color: palette.strokeSoft),
      ),
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
                        items: taskItems,
                        visibleExecutionTargets: visibleExecutionTargets,
                        skillCount: assistantSkillCount,
                        showCollapseControl: showCollapseControl,
                        onCycleSidebarState: onCycleSidebarState,
                        onRefreshTasks: onRefreshTasks,
                        onCreateTask: onCreateTask,
                        onSelectTask: onSelectTask,
                        onArchiveTask: onArchiveTask,
                        onRenameTask: onRenameTask,
                      ),
                    )
                  else
                    const Spacer(),
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
                    sidebarState: sidebarState,
                    onCycleSidebarState: onCycleSidebarState,
                    onOpenAccount: onOpenAccount,
                    showAccountButton: false,
                    accountSelected: false,
                    showCollapseControl: false,
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
        child: Icon(
          Icons.chevron_right_rounded,
          size: size * 0.72,
          color: palette.textSecondary,
        ),
      ),
    );
  }
}
