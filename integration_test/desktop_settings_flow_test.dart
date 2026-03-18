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

  testWidgets('desktop shell routes module entry into gateway settings', (
    WidgetTester tester,
  ) async {
    await pumpDesktopApp(tester);

    await tester.tap(find.byKey(const Key('assistant-side-pane-tab-navigation')));
    await settleIntegrationUi(tester);
    await tester.tap(find.byKey(const Key('assistant-focus-add-menu')));
    await settleIntegrationUi(tester);
    await tester.tap(_textEither('设置', 'Settings').last);
    await settleIntegrationUi(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('assistant-focus-open-page-settings')),
    );
    await settleIntegrationUi(tester);
    await tester.tap(_textEither('集成', 'Integrations'));
    await settleIntegrationUi(tester);
    expect(find.text('OpenClaw Gateway'), findsOneWidget);
  });
}
