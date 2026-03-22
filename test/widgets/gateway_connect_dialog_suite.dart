@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
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

      expect(find.text('工作模式'), findsOneWidget);
      expect(find.text('主机'), findsOneWidget);
      expect(find.text('端口'), findsOneWidget);
      expect(find.text('TLS'), findsOneWidget);
      expect(find.text('共享 Token'), findsOneWidget);
      expect(find.text('认证诊断'), findsOneWidget);
      expect(find.textContaining('fields: none'), findsOneWidget);
      expect(find.textContaining('开发预填 token'), findsNothing);

      await tester.tap(
        find.byType(DropdownButtonFormField<RuntimeConnectionMode>),
      );
      await tester.pumpAndSettle();

      expect(find.text('仅 AI Gateway'), findsWidgets);
      expect(find.text('本地 OpenClaw Gateway'), findsWidgets);
      expect(find.text('远程 OpenClaw Gateway'), findsWidgets);

      await tester.tap(find.text('仅 AI Gateway').last);
      await tester.pumpAndSettle();

      expect(find.text('应用模式'), findsOneWidget);
      expect(
        find.text('当前模式仅通过 AI Gateway 处理任务，不会建立 OpenClaw Gateway 会话。'),
        findsOneWidget,
      );
      expect(_textFieldByLabel(tester, '主机').enabled, isFalse);
      expect(_textFieldByLabel(tester, '端口').enabled, isFalse);
      expect(_textFieldByLabel(tester, '共享 Token').enabled, isFalse);
      expect(_textFieldByLabel(tester, '密码').enabled, isFalse);
    },
  );
}

TextField _textFieldByLabel(WidgetTester tester, String label) {
  return tester
      .widgetList<TextField>(find.byType(TextField))
      .firstWhere((field) => field.decoration?.labelText == label);
}
