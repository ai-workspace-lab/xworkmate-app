import 'package:flutter_test/flutter_test.dart';

import '../test/helpers/test_keys.dart';
import 'test_support.dart';

void main() {
  initializeIntegrationHarness();

  testWidgets('core flow 01 can switch a new conversation to single agent', (
    WidgetTester tester,
  ) async {
    await resetIntegrationPreferences();
    await pumpDesktopApp(tester);
    await waitForIntegrationFinder(tester, find.byKey(TestKeys.assistantTaskRail));

    expect(find.byKey(TestKeys.assistantTaskRail), findsOneWidget);
    expect(find.byKey(TestKeys.assistantNewTaskButton), findsOneWidget);
    expect(find.byKey(TestKeys.assistantExecutionTargetButton), findsOneWidget);
    expect(find.byKey(TestKeys.assistantComposerInput), findsOneWidget);
    expect(find.byKey(TestKeys.assistantSubmitButton), findsOneWidget);

    expect(
      find.byKey(TestKeys.assistantExecutionTargetMenuItemSingleAgent),
      findsOneWidget,
    );

    await switchNewConversationExecutionTargetForIntegration(
      tester,
      find.byKey(TestKeys.assistantExecutionTargetMenuItemSingleAgent),
    );

    expect(
      find.byKey(TestKeys.assistantSingleAgentProviderButton),
      findsOneWidget,
    );
    expect(find.text('ACP Server Local'), findsOneWidget);
  });

  testWidgets('core flow 02 can switch a new conversation to local openclaw gateway', (
    WidgetTester tester,
  ) async {
    await resetIntegrationPreferences();
    await pumpDesktopApp(tester);
    await waitForIntegrationFinder(tester, find.byKey(TestKeys.assistantTaskRail));

    await switchNewConversationExecutionTargetForIntegration(
      tester,
      find.byKey(TestKeys.assistantExecutionTargetMenuItemLocal),
    );

    expect(find.textContaining('127.0.0.1:4317'), findsWidgets);
  });

  testWidgets('core flow 03 can switch a new conversation to remote openclaw gateway', (
    WidgetTester tester,
  ) async {
    await resetIntegrationPreferences();
    await pumpDesktopApp(tester);
    await waitForIntegrationFinder(tester, find.byKey(TestKeys.assistantTaskRail));

    await switchNewConversationExecutionTargetForIntegration(
      tester,
      find.byKey(TestKeys.assistantExecutionTargetMenuItemRemote),
    );

    expect(find.textContaining('gateway.example.com:9443'), findsWidgets);
  });
}
