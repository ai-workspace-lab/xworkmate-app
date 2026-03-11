import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/features/settings/settings_page.dart';

import '../test_support.dart';

void main() {
  testWidgets('SettingsPage theme chips update controller theme mode', (
    WidgetTester tester,
  ) async {
    final controller = await createTestController(tester);

    await pumpPage(tester, child: SettingsPage(controller: controller));

    await tester.tap(find.text('外观'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('深色'));
    await tester.pumpAndSettle();

    expect(controller.themeMode, ThemeMode.dark);

    await tester.tap(find.text('浅色'));
    await tester.pumpAndSettle();
    expect(controller.themeMode, ThemeMode.light);
  });

  testWidgets('SettingsPage gateway tab exposes device pairing controls', (
    WidgetTester tester,
  ) async {
    final controller = await createTestController(tester);

    await pumpPage(tester, child: SettingsPage(controller: controller));

    await tester.tap(find.text('集成'));
    await tester.pumpAndSettle();

    expect(find.text('打开连接面板'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('gateway-device-security-card')),
      findsOneWidget,
    );
  });
}
