import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/features/account/account_page.dart';

import '../test_support.dart';

void main() {
  testWidgets('AccountPage persists workspace label on submit', (
    WidgetTester tester,
  ) async {
    final controller = await createTestController(tester);

    await pumpPage(tester, child: AccountPage(controller: controller));

    await tester.tap(find.text('工作区'));
    await tester.pumpAndSettle();

    final field = find.byType(TextFormField).last;
    await tester.enterText(field, 'QA Workspace');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(controller.settings.accountWorkspace, 'QA Workspace');
  });

  testWidgets('AccountPage saves local entry from current controller values', (
    WidgetTester tester,
  ) async {
    final controller = await createTestController(tester);

    await pumpPage(tester, child: AccountPage(controller: controller));

    await tester.enterText(
      find.byKey(const ValueKey('account-base-url-field')),
      'https://accounts.mobile.example',
    );
    await tester.enterText(
      find.byKey(const ValueKey('account-username-field')),
      'mobile@example.com',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '保存本地入口'));
    await tester.pumpAndSettle();

    expect(
      controller.settings.accountBaseUrl,
      'https://accounts.mobile.example',
    );
    expect(controller.settings.accountUsername, 'mobile@example.com');
  });
}
