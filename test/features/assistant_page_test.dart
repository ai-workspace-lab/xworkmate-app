import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/features/assistant/assistant_page.dart';

import '../test_support.dart';

void main() {
  testWidgets(
    'AssistantPage quick action fills composer and offline send opens gateway dialog',
    (WidgetTester tester) async {
      final controller = await createTestController(tester);

      await pumpPage(
        tester,
        child: AssistantPage(controller: controller, onOpenDetail: (_) {}),
      );

      await tester.tap(find.text('写代码'));
      await tester.pumpAndSettle();
      expect(find.text('写代码'), findsWidgets);

      await tester.tap(find.text('连接'));
      await tester.pumpAndSettle();

      expect(find.text('Gateway 访问'), findsOneWidget);
    },
  );
}
