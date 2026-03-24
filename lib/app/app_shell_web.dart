import 'package:flutter/material.dart';

import '../i18n/app_language.dart';
import '../models/app_models.dart';
import '../theme/app_palette.dart';
import '../web/web_assistant_page.dart';
import '../web/web_settings_page.dart';
import '../widgets/app_brand_logo.dart';
import 'app_controller_web.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final availableDestinations =
            <WorkspaceDestination>[
                  WorkspaceDestination.assistant,
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
                final mobile = constraints.maxWidth < 900;
                if (mobile) {
                  return Column(
                    children: [
                      Expanded(
                        child: _buildPage(
                          controller,
                          destination: currentDestination,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: NavigationBar(
                            selectedIndex: availableDestinations.indexOf(
                              currentDestination,
                            ),
                            onDestinationSelected: (index) {
                              controller.navigateTo(
                                availableDestinations[index],
                              );
                            },
                            destinations: availableDestinations
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

                final palette = context.palette;
                return Row(
                  children: [
                    Container(
                      width: 76,
                      margin: const EdgeInsets.fromLTRB(4, 4, 0, 4),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            palette.chromeHighlight.withValues(alpha: 0.94),
                            palette.chromeSurface.withValues(alpha: 0.92),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: palette.chromeStroke),
                        boxShadow: [palette.chromeShadowAmbient],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
                        child: Column(
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                color: palette.surfacePrimary,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: palette.strokeSoft),
                              ),
                              child: const Center(
                                child: AppBrandLogo(size: 28, borderRadius: 8),
                              ),
                            ),
                            const SizedBox(height: 18),
                            ...availableDestinations.map(
                              (destination) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: _WebNavRailButton(
                                  key: Key('web-shell-nav-${destination.name}'),
                                  destination: destination,
                                  selected: currentDestination == destination,
                                  onTap: () =>
                                      controller.navigateTo(destination),
                                ),
                              ),
                            ),
                            const Spacer(),
                            _WebUtilityButton(
                              key: const Key('web-shell-language-toggle'),
                              tooltip: controller.appLanguage == AppLanguage.zh
                                  ? '中文'
                                  : 'English',
                              icon: Icons.translate_rounded,
                              onTap: controller.toggleAppLanguage,
                            ),
                            const SizedBox(height: 8),
                            _WebUtilityButton(
                              key: const Key('web-shell-theme-toggle'),
                              tooltip: _themeLabel(controller.themeMode),
                              icon: controller.themeMode == ThemeMode.dark
                                  ? Icons.dark_mode_rounded
                                  : Icons.light_mode_rounded,
                              onTap: () => controller.setThemeMode(
                                controller.themeMode == ThemeMode.dark
                                    ? ThemeMode.light
                                    : ThemeMode.dark,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: _buildPage(
                        controller,
                        destination: currentDestination,
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
      WorkspaceDestination.settings => WebSettingsPage(controller: controller),
      _ => WebAssistantPage(controller: controller),
    };
  }
}

class _WebNavRailButton extends StatelessWidget {
  const _WebNavRailButton({
    super.key,
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final WorkspaceDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Tooltip(
      message: destination.label,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: selected ? palette.accentMuted : palette.surfacePrimary,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? palette.accent.withValues(alpha: 0.28)
                  : palette.strokeSoft,
            ),
            boxShadow: selected ? [palette.chromeShadowLift] : null,
          ),
          child: Icon(
            destination.icon,
            size: 22,
            color: selected ? palette.accent : palette.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _WebUtilityButton extends StatelessWidget {
  const _WebUtilityButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          width: 52,
          height: 44,
          decoration: BoxDecoration(
            color: palette.surfacePrimary,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: palette.strokeSoft),
          ),
          child: Icon(icon, size: 20, color: palette.textSecondary),
        ),
      ),
    );
  }
}

String _themeLabel(ThemeMode mode) {
  return switch (mode) {
    ThemeMode.dark => appText('深色', 'Dark'),
    ThemeMode.system => appText('跟随系统', 'System'),
    ThemeMode.light => appText('浅色', 'Light'),
  };
}
