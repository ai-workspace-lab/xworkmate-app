import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:xworkmate/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('desktop settings exposes account and archived task panels', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 960);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    await tester.tap(
      find.byKey(const ValueKey<String>('sidebar-footer-settings')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('settings-account-panel-card')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('settings-tab-selector')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('mobile-settings-page')), findsNothing);

    await tester.tap(find.text('归档任务'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('settings-archived-tasks-panel-card')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('settings-archived-tasks-panel')),
      findsOneWidget,
    );

    await tester.tap(find.text('集成'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('settings-account-panel-card')),
      findsOneWidget,
    );
  });
}
