import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/helpers/test_keys.dart';
import 'test_support.dart';

void main() {
  initializeIntegrationHarness();

  setUp(() async {
    await resetIntegrationPreferences();
  });

  testWidgets(
    'desktop shell exposes settings entry for gateway configuration',
    (WidgetTester tester) async {
      await pumpDesktopApp(tester);
      await waitForIntegrationFinder(
        tester,
        find.byKey(TestKeys.assistantConversationShell),
      );

      await tester.tap(find.byKey(TestKeys.sidebarFooterSettings));
      await settleIntegrationUi(tester);
      expect(
        find.byKey(TestKeys.settingsGatewayTab),
        findsOneWidget,
      );
      expect(find.byKey(TestKeys.settingsIntegrationsTab), findsOneWidget);
      await tester.tap(find.byKey(TestKeys.settingsIntegrationsTab));
      await settleIntegrationUi(tester);
      expect(
        find.byKey(TestKeys.settingsExternalAcpProvider),
        findsOneWidget,
      );
      expect(find.byKey(TestKeys.settingsExternalAcpEndpoint), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await settleIntegrationUi(tester);
    },
  );
}
