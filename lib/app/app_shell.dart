import 'package:flutter/material.dart';

import '../features/account/account_page.dart';
import '../features/assistant/assistant_page.dart';
import '../features/mobile/ios_mobile_shell.dart';
import '../features/modules/modules_page.dart';
import '../features/secrets/secrets_page.dart';
import '../features/settings/settings_page.dart';
import '../features/tasks/tasks_page.dart';
import '../i18n/app_language.dart';
import '../models/app_models.dart';
import '../theme/app_palette.dart';
import '../widgets/detail_drawer.dart';
import '../widgets/pane_resize_handle.dart';
import '../widgets/sidebar_navigation.dart';
import 'app_controller.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.controller});

  final AppController controller;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const _sidebarMinWidth = 180.0;
  static const _sidebarMaxWidth = 320.0;
  double? _sidebarExpandedWidth;

  static const _mobileDestinations = [
    WorkspaceDestination.assistant,
    WorkspaceDestination.tasks,
    WorkspaceDestination.modules,
    WorkspaceDestination.secrets,
    WorkspaceDestination.settings,
  ];

  double _clampSidebarWidth(double value, double viewportWidth) {
    final responsiveMax = (viewportWidth * 0.28).clamp(
      _sidebarMinWidth,
      _sidebarMaxWidth,
    );
    return value.clamp(_sidebarMinWidth, responsiveMax).toDouble();
  }

  double _defaultSidebarWidth(AppLanguage language, double viewportWidth) {
    final baseWidth = language == AppLanguage.zh ? 204.0 : 220.0;
    return _clampSidebarWidth(baseWidth, viewportWidth);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        return Scaffold(
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final palette = context.palette;
                final isIosCompact =
                    Theme.of(context).platform == TargetPlatform.iOS &&
                    constraints.maxWidth < 900;
                final isMobile = constraints.maxWidth < 900;
                final sidebarState = controller.sidebarState;
                final showSidebar = sidebarState != AppSidebarState.hidden;
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
                    constraints.maxWidth > 1460;
                final mobileDestination =
                    controller.destination == WorkspaceDestination.account
                    ? WorkspaceDestination.assistant
                    : controller.destination;

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

                if (isIosCompact) {
                  return IosMobileShell(controller: controller);
                }

                if (isMobile) {
                  return Stack(
                    children: [
                      Column(
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(24),
                                child: Container(
                                  color: palette.canvas.withValues(alpha: 0.18),
                                  child: _pageForDestination(
                                    mobileDestination,
                                    openMobileDetail,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(24),
                              child: NavigationBar(
                                selectedIndex: _mobileDestinations.indexOf(
                                  mobileDestination,
                                ),
                                onDestinationSelected: (index) {
                                  controller.navigateTo(
                                    _mobileDestinations[index],
                                  );
                                },
                                destinations: _mobileDestinations
                                    .map(
                                      (destination) => NavigationDestination(
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
                        child: FloatingActionButton.small(
                          onPressed: openAccountSheet,
                          child: const Icon(Icons.account_circle_rounded),
                        ),
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
                            onSectionChanged: controller.navigateTo,
                            onToggleLanguage: controller.toggleAppLanguage,
                            onCycleSidebarState: controller.cycleSidebarState,
                            onExpandFromCollapsed: () => controller
                                .setSidebarState(AppSidebarState.expanded),
                            onOpenAccount: () => controller.navigateTo(
                              WorkspaceDestination.account,
                            ),
                            onOpenThemeToggle: () => controller.setThemeMode(
                              controller.themeMode == ThemeMode.dark
                                  ? ThemeMode.light
                                  : ThemeMode.dark,
                            ),
                            expandedWidthOverride:
                                sidebarState == AppSidebarState.expanded
                                ? expandedSidebarWidth
                                : null,
                          ),
                        if (sidebarState == AppSidebarState.expanded)
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
                          child: Padding(
                            padding: const EdgeInsets.only(
                              top: 10,
                              right: 10,
                              bottom: 10,
                            ),
                            child: AnimatedPadding(
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOutCubic,
                              padding: EdgeInsets.only(
                                right: showPinnedDetail ? 392 : 0,
                              ),
                              child: Container(
                                color: palette.canvas,
                                child: _buildCurrentPage(controller.openDetail),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (controller.detailPanel != null && !showPinnedDetail)
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
                        left: 0,
                        top: 18,
                        bottom: 18,
                        child: _SidebarRevealRail(
                          onExpand: () => controller.setSidebarState(
                            AppSidebarState.expanded,
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
    return switch (destination) {
      WorkspaceDestination.assistant => AssistantPage(
        controller: widget.controller,
        onOpenDetail: onOpenDetail,
      ),
      WorkspaceDestination.tasks => TasksPage(
        controller: widget.controller,
        onOpenDetail: onOpenDetail,
      ),
      WorkspaceDestination.modules => ModulesPage(
        controller: widget.controller,
        onOpenDetail: onOpenDetail,
      ),
      WorkspaceDestination.secrets => SecretsPage(
        controller: widget.controller,
        onOpenDetail: onOpenDetail,
      ),
      WorkspaceDestination.settings => SettingsPage(
        controller: widget.controller,
      ),
      WorkspaceDestination.account => AccountPage(
        controller: widget.controller,
      ),
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
        message: appText('展开导航', 'Expand sidebar'),
        child: GestureDetector(
          onTap: widget.onExpand,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: _hovered ? 22 : 10,
            decoration: BoxDecoration(
              color: _hovered ? palette.surfaceSecondary : Colors.transparent,
              borderRadius: const BorderRadius.horizontal(
                right: Radius.circular(14),
              ),
              border: Border.all(
                color: _hovered ? palette.strokeSoft : Colors.transparent,
              ),
            ),
            child: _hovered
                ? Icon(
                    Icons.keyboard_double_arrow_right_rounded,
                    size: 16,
                    color: palette.textMuted,
                  )
                : null,
          ),
        ),
      ),
    );
  }
}
