@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/features/settings/settings_page_core.dart';
import 'package:xworkmate/models/app_models.dart';

import '../test_support.dart';

void main() {
  testWidgets(
    'SettingsPage shows ACP bridge server mode card in advanced custom config',
    (WidgetTester tester) async {
      final controller = await createTestController(tester);
      controller.openSettings(tab: SettingsTab.gateway);

      await pumpPage(
        tester,
        child: SettingsPage(
          controller: controller,
          initialTab: SettingsTab.gateway,
          showSectionTabs: true,
        ),
      );

      await tester.tap(find.byKey(const ValueKey('section-tab-高级自定义配置')));
      await tester.pumpAndSettle();

      expect(find.text('ACP Bridge Server 连接模式'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('acp-bridge-mode-cloud')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('acp-bridge-mode-self-hosted')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('acp-bridge-mode-advanced')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('acp-bridge-self-hosted-url')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('acp-bridge-self-hosted-connect')),
        findsOneWidget,
      );
    },
  );
}
