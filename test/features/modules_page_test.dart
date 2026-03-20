import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/features/modules/modules_page.dart';
import 'package:xworkmate/models/app_models.dart';

import '../test_support.dart';

void main() {
  testWidgets(
    'ModulesPage switches connectors tab and routes module actions to settings',
    (WidgetTester tester) async {
      final controller = await createTestController(tester);
      controller.navigateTo(WorkspaceDestination.skills);

      await pumpPage(
        tester,
        child: ModulesPage(controller: controller, onOpenDetail: (_) {}),
      );

      await tester.tap(find.text('编辑设置').first);
      await tester.pumpAndSettle();
      expect(controller.destination, WorkspaceDestination.settings);
      expect(controller.settingsDetail, SettingsDetailPage.gatewayConnection);
      expect(
        controller.settingsNavigationContext?.modulesTab,
        ModulesTab.gateway,
      );

      await tester.tap(find.text('连接器'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('连接 Gateway 后可加载连接器状态'),
        findsOneWidget,
      );

      await tester.tap(find.text('接入模块'));
      await tester.pumpAndSettle();
      expect(controller.destination, WorkspaceDestination.settings);
      expect(controller.settingsTab, SettingsTab.gateway);
      expect(controller.settingsDetail, isNull);
    },
  );
}
