@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:xworkmate/features/settings/settings_page.dart';
import 'package:xworkmate/models/app_models.dart';

import '../test_support.dart';

void main() {
  testWidgets('Secrets shortcut routes to Settings center integrations', (
    WidgetTester tester,
  ) async {
    final controller = await createTestController(tester);
    controller.navigateTo(WorkspaceDestination.secrets);

    expect(controller.destination, WorkspaceDestination.settings);
    expect(controller.settingsTab, SettingsTab.gateway);

    await pumpPage(
      tester,
      child: SettingsPage(
        controller: controller,
        initialTab: controller.settingsTab,
        initialDetail: controller.settingsDetail,
        navigationContext: controller.settingsNavigationContext,
      ),
    );

    expect(find.text('用户登录状态'), findsWidgets);
    expect(find.text('基础连接配置'), findsWidgets);
    expect(find.text('高级自定义模式'), findsNothing);
    expect(
      find.byKey(const ValueKey('gateway-configuration-overview-card')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('gateway-overview-advanced-override')),
      findsNothing,
    );
  });
}
