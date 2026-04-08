import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/helpers/test_keys.dart';
import 'test_support.dart';

void main() {
  initializeIntegrationHarness();

  setUp(() async {
    await resetIntegrationPreferences();
  });

  testWidgets('desktop shell can navigate from assistant to settings and back', (
    WidgetTester tester,
  ) async {
    await pumpDesktopApp(tester);
    await waitForIntegrationFinder(
      tester,
      find.byKey(TestKeys.assistantConversationShell),
    );

    expect(find.byKey(TestKeys.workspaceSidebarNewTaskButton), findsOneWidget);
    expect(find.byKey(TestKeys.assistantExecutionTargetButton), findsOneWidget);

    await tester.tap(find.byKey(TestKeys.sidebarFooterSettings));
    await settleIntegrationUi(tester);
    expect(
      find.byKey(TestKeys.settingsGatewayTab),
      findsOneWidget,
    );
    expect(
      find.byKey(TestKeys.settingsIntegrationsTab),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey<String>('workspace-breadcrumb-0')));
    await settleIntegrationUi(tester);
    await waitForIntegrationFinder(
      tester,
      find.byKey(TestKeys.assistantConversationShell),
    );

    expect(find.byKey(TestKeys.assistantConversationShell), findsOneWidget);
    expect(find.byKey(TestKeys.assistantComposerInput), findsOneWidget);
  });
}
