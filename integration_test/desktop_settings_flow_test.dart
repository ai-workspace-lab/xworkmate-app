import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void main() {
  initializeIntegrationHarness();

  setUp(resetIntegrationPreferences);

  testWidgets('desktop shell routes module entry into gateway settings', (
    WidgetTester tester,
  ) async {
    await pumpDesktopApp(tester);

    await tester.tap(find.text('模块'));
    await settleIntegrationUi(tester);
    await tester.tap(find.text('接入模块'));
    await settleIntegrationUi(tester);

    expect(find.textContaining('工作区、网关默认项'), findsOneWidget);
    await tester.tap(find.text('集成'));
    await settleIntegrationUi(tester);
    expect(find.text('网关连接'), findsOneWidget);
  });
}
