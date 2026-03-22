import 'package:flutter/material.dart';

import '../i18n/app_language.dart';
import '../models/app_models.dart';
import '../theme/app_palette.dart';
import '../theme/app_theme.dart';
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
                      width: currentDestination == WorkspaceDestination.settings
                          ? 248
                          : 236,
                      margin: const EdgeInsets.fromLTRB(4, 4, 4, 0),
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
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const AppBrandLogo(size: 32, borderRadius: 10),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'XWorkmate',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                      Text(
                                        appText(
                                          'Web Workspace',
                                          'Web Workspace',
                                        ),
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: palette.textSecondary,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            ...availableDestinations.map(
                              (destination) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: _WebNavItem(
                                  destination: destination,
                                  selected: currentDestination == destination,
                                  onTap: () =>
                                      controller.navigateTo(destination),
                                ),
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: palette.surfacePrimary,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: palette.strokeSoft),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    appText('平台', 'Platform'),
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(color: palette.textMuted),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    appText(
                                      'Web 仅保留 Assistant / Settings',
                                      'Web keeps only Assistant / Settings',
                                    ),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
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

class _WebNavItem extends StatelessWidget {
  const _WebNavItem({
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
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? palette.accentMuted : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? palette.accent.withValues(alpha: 0.26)
                : palette.strokeSoft,
          ),
        ),
        child: Row(
          children: [
            Icon(destination.icon, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                destination.label,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
