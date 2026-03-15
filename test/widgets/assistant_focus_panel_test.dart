import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/models/app_models.dart';
import 'package:xworkmate/widgets/assistant_focus_panel.dart';

import '../test_support.dart';

void main() {
  testWidgets(
    'AssistantFocusPanel renders focused and available destinations',
    (WidgetTester tester) async {
      final controller = await createTestController(tester);
      await controller.saveSettings(
        controller.settings.copyWith(
          assistantNavigationDestinations: const <WorkspaceDestination>[
            WorkspaceDestination.tasks,
          ],
        ),
        refreshAfterSave: false,
      );

      await pumpPage(
        tester,
        child: AssistantFocusPanel(controller: controller),
      );

      expect(
        find.byKey(const Key('assistant-focus-panel-title')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('assistant-focus-item-tasks')),
        findsOneWidget,
      );

      expect(
        find.byKey(const ValueKey<String>('assistant-focus-add-aiGateway')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('assistant-focus-remove-tasks')),
        findsOneWidget,
      );
    },
  );
}
