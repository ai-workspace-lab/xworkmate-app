import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/widgets/gateway_connect_dialog.dart';

import '../test_support.dart';

void main() {
  testWidgets(
    'GatewayConnectDialog switches between setup and manual connection controls',
    (WidgetTester tester) async {
      final controller = await createTestController(tester);

      await pumpPage(
        tester,
        child: GatewayConnectDialog(controller: controller, compact: true),
      );

      expect(find.text('Gateway 访问'), findsOneWidget);
      expect(find.text('配置码'), findsWidgets);

      await tester.tap(find.text('手动配置'));
      await tester.pumpAndSettle();

      expect(find.text('连接模式'), findsOneWidget);
      expect(find.text('主机'), findsOneWidget);
      expect(find.text('端口'), findsOneWidget);
      expect(find.text('TLS'), findsOneWidget);
      expect(find.text('共享 Token'), findsOneWidget);
    },
  );
}
