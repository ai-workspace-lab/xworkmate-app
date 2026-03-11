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

  testWidgets('SettingsPage diagnostics tab filters and clears runtime logs', (
    WidgetTester tester,
  ) async {
    final controller = await createTestController(tester);
    controller.runtime.addRuntimeLogForTest(
      level: 'info',
      category: 'connect',
      message: 'connected remote gateway',
    );
    controller.runtime.addRuntimeLogForTest(
      level: 'warn',
      category: 'pairing',
      message: 'pairing required',
    );

    await pumpPage(tester, child: SettingsPage(controller: controller));

    await tester.tap(find.text('诊断'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('runtime-log-card')), findsOneWidget);
    expect(find.textContaining('connected remote gateway'), findsOneWidget);
    expect(find.textContaining('pairing required'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('runtime-log-filter')),
      'pairing',
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('connected remote gateway'), findsNothing);
    expect(find.textContaining('pairing required'), findsOneWidget);

    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();

    expect(find.text('当前没有运行日志。'), findsOneWidget);
  });
}
