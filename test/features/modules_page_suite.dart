@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/features/modules/modules_page.dart';
import 'package:xworkmate/features/settings/settings_page.dart';
import 'package:xworkmate/models/app_models.dart';

import '../test_support.dart';

void main() {
  testWidgets(
    'Modules gateway shortcut routes to Settings center and modules page excludes the old gateway tab',
    (WidgetTester tester) async {
      final controller = await createTestController(tester);
      controller.openModules(tab: ModulesTab.gateway);

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

      expect(find.text('OpenClaw Gateway'), findsOneWidget);
      expect(find.text('LLM API'), findsWidgets);

      controller.navigateTo(WorkspaceDestination.nodes);
      await pumpPage(
        tester,
        child: ModulesPage(controller: controller, onOpenDetail: (_) {}),
      );

      await tester.tap(find.text('连接器'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('连接 Gateway 后可加载连接器状态'),
        findsOneWidget,
      );

      await tester.tap(find.text('打开设置中心'));
      await tester.pumpAndSettle();
      expect(controller.destination, WorkspaceDestination.settings);
      expect(controller.settingsTab, SettingsTab.gateway);
      expect(controller.settingsDetail, isNull);
    },
  );
}
