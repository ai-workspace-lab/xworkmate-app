import 'package:flutter/material.dart';

import '../features/account/account_page.dart';
import '../features/mobile/mobile_shell.dart';
import '../i18n/app_language.dart';
import '../models/app_models.dart';
import '../runtime/runtime_models.dart';
import '../theme/app_palette.dart';
import '../widgets/detail_drawer.dart';
import '../widgets/pane_resize_handle.dart';
import '../widgets/sidebar_navigation.dart';
import 'app_controller.dart';
import 'app_controller_desktop_thread_binding.dart';
import 'ui_feature_manifest.dart';
import 'workspace_page_registry.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.controller});

  final AppController controller;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const _sidebarMinWidth = 280.0;
  static const _sidebarViewportPadding = 72.0;
  static const _mainContentMinWidth = 640.0;
  static const _sidebarExpandedBaseWidth = 336.0;
  double? _sidebarExpandedWidth;

  static const _mobileDestinations = [
    WorkspaceDestination.assistant,
    WorkspaceDestination.tasks,
    WorkspaceDestination.skills,
    WorkspaceDestination.secrets,
    WorkspaceDestination.settings,
  ];

  double _clampSidebarWidth(double value, double viewportWidth) {
    final responsiveMax =
        (viewportWidth - _mainContentMinWidth - _sidebarViewportPadding).clamp(
          _sidebarMinWidth,
          viewportWidth - _sidebarViewportPadding,
        );
    return value.clamp(_sidebarMinWidth, responsiveMax).toDouble();
  }

  double _defaultSidebarWidth(AppLanguage language, double viewportWidth) {
    return _clampSidebarWidth(_sidebarExpandedBaseWidth, viewportWidth);
  }

  List<SidebarTaskItem> _buildSidebarTaskItems(AppController controller) {
    final currentSessionKey = controller.currentSessionKey.trim().isEmpty
        ? 'main'
        : controller.currentSessionKey.trim();
    return controller.assistantSessions
        .map((session) {
          final sessionKey = session.key.trim().isEmpty
              ? 'main'
              : session.key.trim();
          final preview = session.lastMessagePreview?.trim() ?? '';
          return SidebarTaskItem(
            sessionKey: sessionKey,
            title: session.label.trim().isEmpty
                ? appText('新对话', 'New conversation')
                : session.label.trim(),
            preview: preview,
            updatedAtMs: session.updatedAtMs,
            executionTarget: controller.assistantExecutionTargetForSession(
              sessionKey,
            ),
            isCurrent: sessionKey == currentSessionKey,
            pending: controller.assistantSessionHasPendingRun(sessionKey),
            draft: sessionKey.startsWith('draft:'),
          );
        })
        .toList(growable: false);
  }

  Future<void> _createSidebarConversation(
    AppController controller,
    List<AssistantExecutionTarget> visibleTargets,
  ) async {
    final sessionKey = 'draft:${DateTime.now().millisecondsSinceEpoch}';
    final target = pickDraftThreadExecutionTargetInternal(
      currentTarget: controller.currentAssistantExecutionTarget,
      visibleTargets: visibleTargets,
      localWorkspaceAvailable: controller.settings.workspacePath
          .trim()
          .isNotEmpty,
    );
    controller.initializeAssistantThreadContext(
      sessionKey,
      title: appText('新对话', 'New conversation'),
      executionTarget: target,
      messageViewMode: controller.currentAssistantMessageViewMode,
      singleAgentProvider: controller.currentSingleAgentProvider,
    );
    controller.navigateTo(WorkspaceDestination.assistant);
    await controller.switchSession(sessionKey);
  }

  void _toggleSidebarVisibility(AppController controller) {
    controller.setSidebarState(
      controller.sidebarState == AppSidebarState.hidden
          ? AppSidebarState.expanded
          : AppSidebarState.hidden,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        final palette = context.palette;
        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                if ((controller.startupTaskThreadWarning ?? '')
                    .trim()
                    .isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: palette.accentMuted,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: palette.warning),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              controller.startupTaskThreadWarning!,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                          const SizedBox(width: 12),
                          TextButton(
                            onPressed:
                                controller.dismissStartupTaskThreadWarning,
                            child: Text(appText('关闭', 'Dismiss')),
                          ),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final palette = context.palette;
                      final platform = Theme.of(context).platform;
                      final isCompactMobile =
                          (platform == TargetPlatform.iOS ||
                              platform == TargetPlatform.android) &&
                          constraints.maxWidth < 900;
                      final isMobile = constraints.maxWidth < 900;
                      final sidebarState = controller.sidebarState;
                      final showSidebar =
                          sidebarState != AppSidebarState.hidden;
                      final uiFeatures = controller.featuresFor(
                        resolveUiFeaturePlatformFromContext(context),
                      );
                      final visibleExecutionTargets = controller
                          .visibleAssistantExecutionTargets(
                            uiFeatures.availableExecutionTargets,
                          );
                      final sidebarTaskItems = _buildSidebarTaskItems(
                        controller,
                      );
                      final expandedSidebarWidth = _clampSidebarWidth(
                        _sidebarExpandedWidth ??
                            _defaultSidebarWidth(
                              controller.appLanguage,
                              constraints.maxWidth,
                            ),
                        constraints.maxWidth,
                      );
                      final showPinnedDetail =
                          controller.detailPanel != null &&
                          constraints.maxWidth > 1280;
                      final mobileDestination =
                          controller.destination == WorkspaceDestination.account
                          ? WorkspaceDestination.assistant
                          : controller.destination;
                      final availableMobileDestinations = _mobileDestinations
                          .where(controller.capabilities.supportsDestination)
                          .toList(growable: false);
                      final resolvedMobileDestination =
                          availableMobileDestinations.contains(
                            mobileDestination,
                          )
                          ? mobileDestination
                          : (availableMobileDestinations.isEmpty
                                ? mobileDestination
                                : availableMobileDestinations.first);

                      void openMobileDetail(DetailPanelData detail) {
                        showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (sheetContext) {
                            return FractionallySizedBox(
                              heightFactor: 0.92,
                              child: DetailSheet(
                                data: detail,
                                onClose: () => Navigator.of(sheetContext).pop(),
                              ),
                            );
                          },
                        );
                      }

                      void openAccountSheet() {
                        showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (sheetContext) {
                            return Container(
                              margin: EdgeInsets.fromLTRB(
                                12,
                                MediaQuery.of(sheetContext).padding.top + 12,
                                12,
                                12,
                              ),
                              decoration: BoxDecoration(
                                color: palette.surfacePrimary,
                                borderRadius: BorderRadius.circular(28),
                                border: Border.all(color: palette.strokeSoft),
                              ),
                              child: SafeArea(
                                top: false,
                                child: AccountPage(controller: controller),
                              ),
                            );
                          },
                        );
                      }

                      if (isCompactMobile) {
                        return MobileShell(controller: controller);
                      }

                      if (isMobile) {
                        return Stack(
                          children: [
                            Column(
                              children: [
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      12,
                                      12,
                                      12,
                                      0,
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(24),
                                      child: Container(
                                        color: palette.canvas.withValues(
                                          alpha: 0.18,
                                        ),
                                        child: _pageForDestination(
                                          resolvedMobileDestination,
                                          openMobileDetail,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    10,
                                    12,
                                    12,
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(24),
                                    child: NavigationBar(
                                      selectedIndex:
                                          availableMobileDestinations.isEmpty
                                          ? 0
                                          : availableMobileDestinations.indexOf(
                                              resolvedMobileDestination,
                                            ),
                                      onDestinationSelected: (index) {
                                        controller.navigateTo(
                                          availableMobileDestinations[index],
                                        );
                                      },
                                      destinations: availableMobileDestinations
                                          .map(
                                            (destination) =>
                                                NavigationDestination(
                                                  icon: Icon(destination.icon),
                                                  label: destination.label,
                                                ),
                                          )
                                          .toList(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Positioned(
                              right: 24,
                              bottom: 96,
                              child:
                                  controller.capabilities.supportsDestination(
                                    WorkspaceDestination.account,
                                  )
                                  ? FloatingActionButton.small(
                                      onPressed: openAccountSheet,
                                      child: const Icon(
                                        Icons.account_circle_rounded,
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        );
                      }

                      return Stack(
                        children: [
                          Row(
                            children: [
                              if (showSidebar)
                                SidebarNavigation(
                                  currentSection: controller.destination,
                                  sidebarState: sidebarState,
                                  appLanguage: controller.appLanguage,
                                  themeMode: controller.themeMode,
                                  onSectionChanged: (destination) {
                                    if (destination ==
                                        WorkspaceDestination.settings) {
                                      controller.openSettings(
                                        tab: SettingsTab.gateway,
                                      );
                                      return;
                                    }
                                    controller.navigateTo(destination);
                                  },
                                  onToggleLanguage:
                                      controller.toggleAppLanguage,
                                  onCycleSidebarState: () =>
                                      _toggleSidebarVisibility(controller),
                                  onExpandFromCollapsed: () =>
                                      _toggleSidebarVisibility(controller),
                                  onOpenHome: controller.navigateHome,
                                  onOpenAccount: () => controller.navigateTo(
                                    WorkspaceDestination.account,
                                  ),
                                  onOpenThemeToggle: () =>
                                      controller.setThemeMode(
                                        controller.themeMode == ThemeMode.dark
                                            ? ThemeMode.light
                                            : ThemeMode.dark,
                                      ),
                                  accountName:
                                      controller.settings.accountUsername
                                          .trim()
                                          .isEmpty
                                      ? appText('本地操作员', 'Local Operator')
                                      : controller.settings.accountUsername,
                                  accountSubtitle:
                                      controller.settings.accountWorkspace
                                          .trim()
                                          .isEmpty
                                      ? appText('账号', 'Account')
                                      : controller.settings.accountWorkspace,
                                  accountWorkspaceFollowed: controller
                                      .settings
                                      .accountWorkspaceFollowed,
                                  onToggleAccountWorkspaceFollowed:
                                      controller.toggleAccountWorkspaceFollowed,
                                  onOpenOnlineWorkspace:
                                      controller.openOnlineWorkspace,
                                  expandedWidthOverride:
                                      sidebarState == AppSidebarState.expanded
                                      ? expandedSidebarWidth
                                      : null,
                                  marginOverride: const EdgeInsets.fromLTRB(
                                    4,
                                    4,
                                    4,
                                    0,
                                  ),
                                  favoriteDestinations: controller
                                      .assistantNavigationDestinations
                                      .toSet(),
                                  onToggleFavorite: controller
                                      .toggleAssistantNavigationDestination,
                                  availableDestinations: controller
                                      .capabilities
                                      .allowedDestinations,
                                  currentSettingsTab: controller.settingsTab,
                                  availableSettingsTabs:
                                      uiFeatures.availableSettingsTabs,
                                  onSettingsTabChanged: (tab) =>
                                      controller.openSettings(tab: tab),
                                  taskItems: sidebarTaskItems,
                                  visibleExecutionTargets:
                                      visibleExecutionTargets,
                                  assistantSkillCount:
                                      controller.currentAssistantSkillCount,
                                  onRefreshTasks: controller.refreshSessions,
                                  onCreateTask: () =>
                                      _createSidebarConversation(
                                        controller,
                                        visibleExecutionTargets,
                                      ),
                                  onSelectTask: (sessionKey) async {
                                    controller.navigateTo(
                                      WorkspaceDestination.assistant,
                                    );
                                    await controller.switchSession(sessionKey);
                                  },
                                  onArchiveTask: (sessionKey) =>
                                      controller.saveAssistantTaskArchived(
                                        sessionKey,
                                        true,
                                      ),
                                  onRenameTask: (sessionKey, title) =>
                                      controller.saveAssistantTaskTitle(
                                        sessionKey,
                                        title,
                                      ),
                                ),
                              if (sidebarState == AppSidebarState.expanded)
                                PaneResizeHandle(
                                  axis: Axis.horizontal,
                                  extent: 8,
                                  onDelta: (delta) {
                                    setState(() {
                                      _sidebarExpandedWidth =
                                          _clampSidebarWidth(
                                            expandedSidebarWidth + delta,
                                            constraints.maxWidth,
                                          );
                                    });
                                  },
                                ),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    0,
                                    4,
                                    4,
                                    0,
                                  ),
                                  child: AnimatedPadding(
                                    duration: const Duration(milliseconds: 220),
                                    curve: Curves.easeOutCubic,
                                    padding: EdgeInsets.only(
                                      right: showPinnedDetail ? 336 : 0,
                                    ),
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: palette.canvas,
                                      ),
                                      child: _buildCurrentPage(
                                        controller.openDetail,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (controller.detailPanel != null &&
                              !showPinnedDetail)
                            Positioned.fill(
                              child: GestureDetector(
                                onTap: controller.closeDetail,
                                child: Container(
                                  color: Colors.black.withValues(alpha: 0.12),
                                ),
                              ),
                            ),
                          if (controller.detailPanel != null)
                            Align(
                              alignment: Alignment.centerRight,
                              child: DetailDrawer(
                                data: controller.detailPanel!,
                                onClose: controller.closeDetail,
                              ),
                            ),
                          if (!showSidebar)
                            Positioned(
                              left: 8,
                              top: 8,
                              child: _SidebarRevealRail(
                                onExpand: () =>
                                    _toggleSidebarVisibility(controller),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCurrentPage(ValueChanged<DetailPanelData> onOpenDetail) {
    return IndexedStack(
      index: widget.controller.destination.index,
      children: WorkspaceDestination.values
          .map((destination) => _pageForDestination(destination, onOpenDetail))
          .toList(),
    );
  }

  Widget _pageForDestination(
    WorkspaceDestination destination,
    ValueChanged<DetailPanelData> onOpenDetail,
  ) {
    return buildWorkspacePage(
      destination: destination,
      controller: widget.controller,
      onOpenDetail: onOpenDetail,
      surface: WorkspacePageSurface.desktop,
    );
  }
}

class _SidebarRevealRail extends StatefulWidget {
  const _SidebarRevealRail({required this.onExpand});

  final VoidCallback onExpand;

  @override
  State<_SidebarRevealRail> createState() => _SidebarRevealRailState();
}

class _SidebarRevealRailState extends State<_SidebarRevealRail> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Tooltip(
        message: appText('展开导航', 'Expand sidebar'),
        child: GestureDetector(
          onTap: widget.onExpand,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: _hovered ? 40 : 32,
            height: _hovered ? 40 : 32,
            decoration: BoxDecoration(
              color: _hovered ? palette.surfacePrimary : palette.chromeSurface,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Icon(
              Icons.keyboard_double_arrow_right_rounded,
              size: 18,
              color: palette.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
