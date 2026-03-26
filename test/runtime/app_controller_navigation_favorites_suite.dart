@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/models/app_models.dart';

import '../test_support.dart';

void main() {
  test(
    'AppController keeps tasks destination in focused destinations',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final controller = AppController(store: createIsolatedTestStore());
      addTearDown(controller.dispose);

      await _waitFor(() => !controller.initializing);

      await controller.saveSettings(
        controller.settings.copyWith(
          assistantNavigationDestinations: const <AssistantFocusEntry>[
            AssistantFocusEntry.tasks,
            AssistantFocusEntry.skills,
            AssistantFocusEntry.tasks,
            AssistantFocusEntry.aiGateway,
          ],
        ),
        refreshAfterSave: false,
      );

      expect(
        controller.assistantNavigationDestinations,
        const <AssistantFocusEntry>[
          AssistantFocusEntry.tasks,
          AssistantFocusEntry.skills,
          AssistantFocusEntry.aiGateway,
        ],
      );
    },
  );

  test('AppController toggles focused navigation destinations', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final controller = AppController(store: createIsolatedTestStore());
    addTearDown(controller.dispose);

    await _waitFor(() => !controller.initializing);

    await controller.saveSettings(
      controller.settings.copyWith(
        assistantNavigationDestinations: const <AssistantFocusEntry>[
          AssistantFocusEntry.skills,
        ],
      ),
      refreshAfterSave: false,
    );

    await controller.toggleAssistantNavigationDestination(
      AssistantFocusEntry.aiGateway,
    );
    expect(
      controller.assistantNavigationDestinations,
      const <AssistantFocusEntry>[
        AssistantFocusEntry.skills,
        AssistantFocusEntry.aiGateway,
      ],
    );

    await controller.toggleAssistantNavigationDestination(
      AssistantFocusEntry.skills,
    );
    expect(
      controller.assistantNavigationDestinations,
      const <AssistantFocusEntry>[AssistantFocusEntry.aiGateway],
    );
  });
}

Future<void> _waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
