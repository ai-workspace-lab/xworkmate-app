import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/features/mobile/ios_mobile_shell.dart';
import 'package:xworkmate/theme/app_theme.dart';

import '../../test_support.dart';

void main() {
  testWidgets(
    'IosMobileShell saves local account entry from the account page',
    (WidgetTester tester) async {
      final controller = await createTestController(tester);

      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(430, 1200);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: const [Locale('zh'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: AppTheme.light().copyWith(platform: TargetPlatform.iOS),
          darkTheme: AppTheme.dark().copyWith(platform: TargetPlatform.iOS),
          home: IosMobileShell(controller: controller),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('账号登录').first);
      await tester.pumpAndSettle();

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'https://accounts.qa.example');
      await tester.enterText(fields.at(1), 'qa@example.com');
      await tester.enterText(fields.at(2), 'secret');
      await tester.pumpAndSettle();

      final saveButton = find.widgetWithText(FilledButton, '保存本地入口');
      await tester.ensureVisible(saveButton);
      await tester.pumpAndSettle();
      await tester.tap(saveButton);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(controller.settings.accountBaseUrl, 'https://accounts.qa.example');
      expect(controller.settings.accountUsername, 'qa@example.com');
    },
  );
}
