import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void main() {
  initializeIntegrationHarness();

  setUp(resetIntegrationPreferences);

  testWidgets('desktop shell navigates across primary surfaces', (
    WidgetTester tester,
  ) async {
    await pumpDesktopApp(tester);

    expect(find.text('新对话'), findsWidgets);

    await tester.tap(find.text('节点'));
    await settleIntegrationUi(tester);
    expect(find.text('管理 Gateway、代理、节点、技能和平台服务。'), findsOneWidget);
  });
}
