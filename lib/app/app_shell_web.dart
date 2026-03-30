import 'package:flutter/material.dart';

import '../i18n/app_language.dart';
import '../models/app_models.dart';
import '../theme/app_palette.dart';
import '../web/web_assistant_page.dart';
import '../web/web_settings_page.dart';
import '../web/web_workspace_pages.dart';
import '../widgets/pane_resize_handle.dart';
import '../widgets/sidebar_navigation.dart';
import 'app_controller_web.dart';
import 'ui_feature_manifest.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.controller});

  final AppController controller;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const _sidebarMinWidth = 56.0;
  static const _sidebarViewportPadding = 72.0;
  static const _mainContentMinWidth = 760.0;
  static const _sidebarExpandedBaseWidth = 336.0;

  AppSidebarState _sidebarState = AppSidebarState.expanded;
  double? _sidebarExpandedWidth;

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

  void _toggleSidebarVisibility() {
    setState(() {
      _sidebarState = _sidebarState == AppSidebarState.hidden
          ? AppSidebarState.expanded
          : AppSidebarState.hidden;
    });
  }

  List<SidebarTaskItem> _buildSidebarTaskItems(AppController controller) {
    return controller.conversations
        .map(
          (item) => SidebarTaskItem(
            sessionKey: item.sessionKey,
            title: item.title,
            preview: item.preview,
            updatedAtMs: item.updatedAtMs,
            executionTarget: item.executionTarget,
            isCurrent: item.current,
            pending: item.pending,
            draft: item.sessionKey.startsWith('draft:'),
          ),
        )
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        final uiFeatures = controller.featuresFor(UiFeaturePlatform.web);
        final availableDestinations =
            <WorkspaceDestination>[
                  WorkspaceDestination.assistant,
                  WorkspaceDestination.tasks,
                  WorkspaceDestination.skills,
                  WorkspaceDestination.nodes,
                  WorkspaceDestination.secrets,
                  WorkspaceDestination.aiGateway,
                  WorkspaceDestination.settings,
                ]
                .where(controller.capabilities.supportsDestination)
                .toList(growable: false);
        final currentDestination =
            availableDestinations.contains(controller.destination)
            ? controller.destination
            : (availableDestinations.isEmpty
                  ? WorkspaceDestination.assistant
                  : availableDestinations.first);
        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isMobile = constraints.maxWidth < 900;
                final sidebarTaskItems = _buildSidebarTaskItems(controller);
                final expandedSidebarWidth = _clampSidebarWidth(
                  _sidebarExpandedWidth ??
                      _defaultSidebarWidth(
                        controller.appLanguage,
                        constraints.maxWidth,
                      ),
                  constraints.maxWidth,
                );

                if (isMobile) {
                  final mobileDestinations =
                      <WorkspaceDestination>[
                            WorkspaceDestination.assistant,
                            WorkspaceDestination.tasks,
                            WorkspaceDestination.skills,
                            WorkspaceDestination.settings,
                          ]
                          .where(controller.capabilities.supportsDestination)
                          .toList(growable: false);
                  final selectedIndex =
                      mobileDestinations.contains(currentDestination)
                      ? mobileDestinations.indexOf(currentDestination)
                      : 0;
                  return Column(
                    children: [
                      Expanded(
                        child: _WebShellBody(
                          child: _buildPage(
                            controller,
                            destination: currentDestination,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: NavigationBar(
                            selectedIndex: selectedIndex,
                            onDestinationSelected: (index) {
                              controller.navigateTo(mobileDestinations[index]);
                            },
                            destinations: mobileDestinations
                                .map(
                                  (destination) => NavigationDestination(
                                    icon: Icon(destination.icon),
                                    label: destination.label,
                                  ),
                                )
                                .toList(growable: false),
                          ),
                        ),
                      ),
                    ],
                  );
                }

                return Stack(
                  children: [
                    Row(
                      children: [
                        if (_sidebarState != AppSidebarState.hidden)
                          SidebarNavigation(
                            currentSection: currentDestination,
                            sidebarState: _sidebarState,
                            appLanguage: controller.appLanguage,
                            themeMode: controller.themeMode,
                            onSectionChanged: (destination) {
                              if (destination ==
                                  WorkspaceDestination.settings) {
                                controller.openSettings(
                                  tab: SettingsTab.general,
                                );
                                return;
                              }
                              controller.navigateTo(destination);
                            },
                            onToggleLanguage: controller.toggleAppLanguage,
                            onCycleSidebarState: _toggleSidebarVisibility,
                            onExpandFromCollapsed: _toggleSidebarVisibility,
                            onOpenHome: controller.navigateHome,
                            onOpenAccount: () {},
                            onOpenThemeToggle: () => controller.setThemeMode(
                              controller.themeMode == ThemeMode.dark
                                  ? ThemeMode.light
                                  : ThemeMode.dark,
                            ),
                            accountName:
                                controller.settings.accountUsername
                                    .trim()
                                    .isNotEmpty
                                ? controller.settings.accountUsername
                                : appText('Web 操作员', 'Web operator'),
                            accountSubtitle:
                                controller.settings.accountWorkspace
                                    .trim()
                                    .isNotEmpty
                                ? controller.settings.accountWorkspace
                                : appText('Web 工作区', 'Web workspace'),
                            accountWorkspaceFollowed:
                                controller.settings.accountWorkspaceFollowed,
                            onToggleAccountWorkspaceFollowed:
                                controller.toggleAccountWorkspaceFollowed,
                            expandedWidthOverride:
                                _sidebarState == AppSidebarState.expanded
                                ? expandedSidebarWidth
                                : null,
                            favoriteDestinations: controller
                                .assistantNavigationDestinations
                                .toSet(),
                            onToggleFavorite:
                                controller.toggleAssistantNavigationDestination,
                            availableDestinations:
                                controller.capabilities.allowedDestinations,
                            currentSettingsTab: controller.settingsTab,
                            availableSettingsTabs:
                                uiFeatures.availableSettingsTabs,
                            onSettingsTabChanged: (tab) =>
                                controller.openSettings(tab: tab),
                            taskItems: sidebarTaskItems,
                            assistantSkillCount:
                                controller.currentAssistantSkillCount,
                            onRefreshTasks: controller.refreshSessions,
                            onCreateTask: () async {
                              await controller.createConversation(
                                target: controller.assistantExecutionTarget,
                              );
                              controller.navigateTo(
                                WorkspaceDestination.assistant,
                              );
                            },
                            onSelectTask: (sessionKey) async {
                              controller.navigateTo(
                                WorkspaceDestination.assistant,
                              );
                              await controller.switchConversation(sessionKey);
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
                        if (_sidebarState == AppSidebarState.expanded)
                          PaneResizeHandle(
                            axis: Axis.horizontal,
                            onDelta: (delta) {
                              setState(() {
                                _sidebarExpandedWidth = _clampSidebarWidth(
                                  expandedSidebarWidth + delta,
                                  constraints.maxWidth,
                                );
                              });
                            },
                          ),
                        Expanded(
                          child: _WebShellBody(
                            child: _buildPage(
                              controller,
                              destination: currentDestination,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_sidebarState == AppSidebarState.hidden)
                      Positioned(
                        left: 8,
                        bottom: 8,
                        child: _SidebarRevealRail(
                          onExpand: _toggleSidebarVisibility,
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildPage(
    AppController controller, {
    required WorkspaceDestination destination,
  }) {
    return switch (destination) {
      WorkspaceDestination.tasks => WebTasksPage(controller: controller),
      WorkspaceDestination.skills => WebSkillsPage(controller: controller),
      WorkspaceDestination.nodes => WebNodesPage(controller: controller),
      WorkspaceDestination.secrets => WebSecretsPage(controller: controller),
      WorkspaceDestination.aiGateway => WebAiGatewayPage(
        controller: controller,
      ),
      WorkspaceDestination.settings => WebSettingsPage(
        controller: controller,
        showSectionTabs: false,
      ),
      _ => WebAssistantPage(controller: controller),
    };
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
        message: appText('展开左栏', 'Expand sidebar'),
        child: GestureDetector(
          onTap: widget.onExpand,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: _hovered ? 40 : 32,
            height: _hovered ? 40 : 32,
            decoration: BoxDecoration(
              color: _hovered ? palette.surfacePrimary : palette.chromeSurface,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: palette.strokeSoft),
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

class _WebShellBody extends StatelessWidget {
  const _WebShellBody({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(top: 4, right: 4),
      child: DecoratedBox(
        decoration: BoxDecoration(color: palette.canvas),
        child: child,
      ),
    );
  }
}
