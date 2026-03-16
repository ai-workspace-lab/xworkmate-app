import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/models/app_models.dart';

void main() {
  test('AppController omits fixed task entry from focused destinations', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final controller = AppController();
    addTearDown(controller.dispose);

    await _waitFor(() => !controller.initializing);

    await controller.saveSettings(
      controller.settings.copyWith(
        assistantNavigationDestinations: const <WorkspaceDestination>[
          WorkspaceDestination.tasks,
          WorkspaceDestination.skills,
          WorkspaceDestination.aiGateway,
        ],
      ),
      refreshAfterSave: false,
    );

    expect(
      controller.assistantNavigationDestinations,
      const <WorkspaceDestination>[
        WorkspaceDestination.skills,
        WorkspaceDestination.aiGateway,
      ],
    );
  });

  test('AppController toggles focused navigation destinations', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final controller = AppController();
    addTearDown(controller.dispose);

    await _waitFor(() => !controller.initializing);

    await controller.saveSettings(
      controller.settings.copyWith(
        assistantNavigationDestinations: const <WorkspaceDestination>[
          WorkspaceDestination.skills,
        ],
      ),
      refreshAfterSave: false,
    );

    await controller.toggleAssistantNavigationDestination(
      WorkspaceDestination.aiGateway,
    );
    expect(
      controller.assistantNavigationDestinations,
      const <WorkspaceDestination>[
        WorkspaceDestination.skills,
        WorkspaceDestination.aiGateway,
      ],
    );

    await controller.toggleAssistantNavigationDestination(
      WorkspaceDestination.skills,
    );
    expect(
      controller.assistantNavigationDestinations,
      const <WorkspaceDestination>[WorkspaceDestination.aiGateway],
    );
  });
}

Future<void> _waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
