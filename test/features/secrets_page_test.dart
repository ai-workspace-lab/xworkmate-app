import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/features/secrets/secrets_page.dart';
import 'package:xworkmate/models/app_models.dart';

import '../test_support.dart';

void main() {
  testWidgets(
    'SecretsPage switches to audit and routes add secret to settings',
    (WidgetTester tester) async {
      final controller = await createTestController(tester);
      controller.navigateTo(WorkspaceDestination.secrets);
      DetailPanelData? openedDetail;

      await pumpPage(
        tester,
        child: SecretsPage(
          controller: controller,
          onOpenDetail: (detail) => openedDetail = detail,
        ),
      );

      await tester.tap(find.text('审计'));
      await tester.pumpAndSettle();
      expect(find.textContaining('还没有安全审计条目'), findsOneWidget);
      expect(openedDetail, isNull);

      await tester.tap(find.text('新增密钥'));
      await tester.pumpAndSettle();
      expect(controller.destination, WorkspaceDestination.settings);
    },
  );
}
