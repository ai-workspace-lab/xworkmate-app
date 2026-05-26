import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:xworkmate/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('desktop navigation opens settings and returns to assistant', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 960);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.byKey(const Key('xworkmate-app-shell')), findsOneWidget);
    expect(
      find.byKey(const Key('assistant-conversation-shell')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('settings-account-panel-card')), findsNothing);
    expect(find.byKey(const Key('mobile-assistant-page')), findsNothing);
    expect(find.byKey(const Key('mobile-settings-page')), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey<String>('sidebar-footer-settings')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('settings-account-panel-card')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('workspace-sidebar-back-to-chat-button')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('workspace-sidebar-back-to-chat-button')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('assistant-conversation-shell')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('settings-account-panel-card')), findsNothing);
  });
}
