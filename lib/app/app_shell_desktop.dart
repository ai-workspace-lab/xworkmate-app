import 'package:flutter/material.dart';

import '../features/account/account_page.dart';
import '../features/mobile/mobile_shell.dart';
import '../i18n/app_language.dart';
import '../models/app_models.dart';
import '../theme/app_palette.dart';
import '../theme/app_theme.dart';
import '../widgets/detail_drawer.dart';
import '../widgets/pane_resize_handle.dart';
import '../widgets/sidebar_navigation.dart';
import 'app_controller.dart';
import 'ui_feature_manifest.dart';
import 'workspace_page_registry.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.controller});

  final AppController controller;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const _sidebarMinWidth = 56.0;
  static const _sidebarViewportPadding = 72.0;
  static const _mainContentMinWidth = 640.0;
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
    final baseWidth = language == AppLanguage.zh
        ? AppSizes.sidebarExpandedWidthZh
        : AppSizes.sidebarExpandedWidthEn;
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
            bottom: false,
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
                final showSidebar = sidebarState != AppSidebarState.hidden;
                final uiFeatures = controller.featuresFor(
                  resolveUiFeaturePlatformFromContext(context),
                );
                final embedSidebarIntoAssistant =
                    controller.destination == WorkspaceDestination.assistant &&
                    showSidebar;
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
                    availableMobileDestinations.contains(mobileDestination)
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
                              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(24),
                                child: Container(
                                  color: palette.canvas.withValues(alpha: 0.18),
                                  child: _pageForDestination(
                                    resolvedMobileDestination,
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
                        child:
                            controller.capabilities.supportsDestination(
                              WorkspaceDestination.account,
                            )
                            ? FloatingActionButton.small(
                                onPressed: openAccountSheet,
                                child: const Icon(Icons.account_circle_rounded),
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
                        if (showSidebar && !embedSidebarIntoAssistant)
                          SidebarNavigation(
                            currentSection: controller.destination,
                            sidebarState: sidebarState,
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
                            onCycleSidebarState: controller.cycleSidebarState,
                            onExpandFromCollapsed: () => controller
                                .setSidebarState(AppSidebarState.expanded),
                            onOpenHome: controller.navigateHome,
                            onOpenAccount: () => controller.navigateTo(
                              WorkspaceDestination.account,
                            ),
                            onOpenThemeToggle: () => controller.setThemeMode(
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
                            accountWorkspaceFollowed:
                                controller.settings.accountWorkspaceFollowed,
                            onToggleAccountWorkspaceFollowed:
                                controller.toggleAccountWorkspaceFollowed,
                            onOpenOnlineWorkspace:
                                controller.openOnlineWorkspace,
                            expandedWidthOverride:
                                sidebarState == AppSidebarState.expanded
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
                          ),
                        if (sidebarState == AppSidebarState.expanded &&
                            !embedSidebarIntoAssistant)
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
                            padding: const EdgeInsets.only(top: 4, right: 4),
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
                        top: 8,
                        bottom: 0,
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
            width: _hovered ? 22 : 10,
            decoration: BoxDecoration(
              color: _hovered ? palette.surfacePrimary : Colors.transparent,
              borderRadius: const BorderRadius.horizontal(
                right: Radius.circular(14),
              ),
              border: Border.all(
                color: _hovered ? palette.strokeSoft : Colors.transparent,
              ),
            ),
            child: _hovered
                ? Icon(
                    Icons.chevron_right_rounded,
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
