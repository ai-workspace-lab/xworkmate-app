import 'package:flutter/material.dart';

import '../models/app_models.dart';
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

                return _buildPage(
                  controller,
                  destination: currentDestination,
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
