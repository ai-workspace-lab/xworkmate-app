import 'package:flutter/material.dart';
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
    expect(find.text('ACP Server'), findsOneWidget);
  });

  testWidgets(
    'core flow 02 can submit a prompt in single agent mode',
    (WidgetTester tester) async {
      await resetIntegrationPreferences();
      await pumpDesktopApp(tester);
      await waitForIntegrationFinder(
        tester,
        find.byKey(TestKeys.assistantTaskRail),
      );

      await switchNewConversationExecutionTargetForIntegration(
        tester,
        find.byKey(TestKeys.assistantExecutionTargetMenuItemSingleAgent),
      );

      final prompt = '请回复：单机智能体提交成功';
      final composerInput = find.descendant(
        of: find.byKey(TestKeys.assistantComposerInput),
        matching: find.byType(TextField),
      );

      expect(composerInput, findsOneWidget);

      await tester.enterText(composerInput, prompt);
      await tester.tap(find.byKey(TestKeys.assistantSubmitButton));
      await settleIntegrationUi(tester);

      await waitForIntegrationFinder(tester, find.textContaining(prompt));

      expect(find.textContaining(prompt), findsWidgets);
      expect(tester.widget<TextField>(composerInput).controller?.text, isEmpty);
    },
  );

  testWidgets('core flow 03 can switch a new conversation to local openclaw gateway', (
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

  testWidgets('core flow 04 can switch a new conversation to remote openclaw gateway', (
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
