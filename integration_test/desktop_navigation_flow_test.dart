import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

Finder _textEither(String zh, String en) {
  return find.byWidgetPredicate(
    (widget) => widget is Text && (widget.data == zh || widget.data == en),
  );
}

Future<void> _ensureSettingsFocused(WidgetTester tester) async {
  final activeSettings = find.byKey(
    const ValueKey<String>('assistant-focus-active-title-settings'),
  );
  if (activeSettings.evaluate().isNotEmpty) {
    return;
  }
  final addSettingsChip = find.byKey(
    const ValueKey<String>('assistant-focus-add-settings'),
  );
  if (addSettingsChip.evaluate().isNotEmpty) {
    await tester.tap(addSettingsChip);
    await settleIntegrationUi(tester);
    return;
  }
  final addMenu = find.byKey(const Key('assistant-focus-add-menu'));
  expect(addMenu, findsOneWidget);
  await tester.tap(addMenu);
  await settleIntegrationUi(tester);
  final settingsItem = _textEither('设置', 'Settings');
  expect(settingsItem, findsWidgets);
  await tester.tap(settingsItem.last);
  await settleIntegrationUi(tester);
}

void main() {
  initializeIntegrationHarness();

  setUp(() async {
    await resetIntegrationPreferences();
  });

  testWidgets('desktop shell opens focused navigation surface', (
    WidgetTester tester,
  ) async {
    await pumpDesktopApp(tester);

    expect(_textEither('新对话', 'New conversation'), findsWidgets);
    await tester.tap(
      find.byKey(const Key('assistant-side-pane-tab-navigation')),
    );
    await settleIntegrationUi(tester);
    expect(
      find.byKey(const Key('assistant-focus-panel-title')),
      findsOneWidget,
    );
    await _ensureSettingsFocused(tester);
    expect(
      find.byKey(
        const ValueKey<String>('assistant-focus-active-title-settings'),
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await settleIntegrationUi(tester);
  });
}
