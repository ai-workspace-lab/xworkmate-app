import 'package:flutter/material.dart';

import '../i18n/app_language.dart';
import '../models/app_models.dart';
import '../theme/app_palette.dart';
import '../theme/app_theme.dart';
import '../web/web_assistant_page.dart';
import '../web/web_settings_page.dart';
import 'app_controller_web.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final mobile = constraints.maxWidth < 900;
                if (mobile) {
                  return Column(
                    children: [
                      Expanded(child: _buildPage(controller)),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: NavigationBar(
                            selectedIndex:
                                controller.destination ==
                                    WorkspaceDestination.settings
                                ? 1
                                : 0,
                            onDestinationSelected: (index) {
                              controller.navigateTo(
                                index == 0
                                    ? WorkspaceDestination.assistant
                                    : WorkspaceDestination.settings,
                              );
                            },
                            destinations: const [
                              NavigationDestination(
                                icon: Icon(Icons.chat_bubble_outline_rounded),
                                label: 'Assistant',
                              ),
                              NavigationDestination(
                                icon: Icon(Icons.tune_rounded),
                                label: 'Settings',
                              ),
                            ],
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
                      width:
                          controller.destination ==
                              WorkspaceDestination.settings
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
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                    color: palette.accentMuted,
                                  ),
                                  child: Icon(
                                    Icons.crop_square_rounded,
                                    color: palette.accent,
                                  ),
                                ),
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
                            _WebNavItem(
                              destination: WorkspaceDestination.assistant,
                              selected:
                                  controller.destination ==
                                  WorkspaceDestination.assistant,
                              onTap: () => controller.navigateTo(
                                WorkspaceDestination.assistant,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _WebNavItem(
                              destination: WorkspaceDestination.settings,
                              selected:
                                  controller.destination ==
                                  WorkspaceDestination.settings,
                              onTap: () => controller.navigateTo(
                                WorkspaceDestination.settings,
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
                    Expanded(child: _buildPage(controller)),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildPage(AppController controller) {
    return switch (controller.destination) {
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
