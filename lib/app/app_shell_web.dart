import 'package:flutter/material.dart';

import '../i18n/app_language.dart';
import '../models/app_models.dart';
import '../theme/app_palette.dart';
import '../theme/app_theme.dart';
import '../web/web_assistant_page.dart';
import '../web/web_settings_page.dart';
import '../web/web_workspace_pages.dart';
import '../widgets/pane_resize_handle.dart';
import '../widgets/sidebar_navigation.dart';
import 'app_controller_web.dart';

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
    final baseWidth = language == AppLanguage.zh
        ? AppSizes.sidebarExpandedWidthZh
        : AppSizes.sidebarExpandedWidthEn;
    return _clampSidebarWidth(baseWidth, viewportWidth);
  }

  void _cycleSidebarState() {
    setState(() {
      _sidebarState = switch (_sidebarState) {
        AppSidebarState.expanded => AppSidebarState.collapsed,
        AppSidebarState.collapsed => AppSidebarState.hidden,
        AppSidebarState.hidden => AppSidebarState.expanded,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
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
                final showWorkspaceSidebar =
                    currentDestination != WorkspaceDestination.assistant;
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

                return Row(
                  children: [
                    if (showWorkspaceSidebar &&
                        _sidebarState != AppSidebarState.hidden)
                      SidebarNavigation(
                        currentSection: currentDestination,
                        sidebarState: _sidebarState,
                        appLanguage: controller.appLanguage,
                        themeMode: controller.themeMode,
                        onSectionChanged: controller.navigateTo,
                        onToggleLanguage: controller.toggleAppLanguage,
                        onCycleSidebarState: _cycleSidebarState,
                        onExpandFromCollapsed: () {
                          setState(() {
                            _sidebarState = AppSidebarState.expanded;
                          });
                        },
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
                      ),
                    if (showWorkspaceSidebar &&
                        _sidebarState == AppSidebarState.expanded)
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
      WorkspaceDestination.settings => WebSettingsPage(controller: controller),
      _ => WebAssistantPage(controller: controller),
    };
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
