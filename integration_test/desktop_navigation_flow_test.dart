import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

Finder _textEither(String zh, String en) {
  return find.byWidgetPredicate(
    (widget) => widget is Text && (widget.data == zh || widget.data == en),
  );
}

void main() {
  initializeIntegrationHarness();

  setUp(resetIntegrationPreferences);

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
    expect(_textEither('设置', 'Settings'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    await settleIntegrationUi(tester);
  });
}
