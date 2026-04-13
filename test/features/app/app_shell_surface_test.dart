import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/app/app_shell_desktop.dart';
import 'package:xworkmate/theme/app_theme.dart';

void main() {
  group('AppShell surface cleanup', () {
    testWidgets('mobile shell only exposes assistant and settings tabs', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(430, 932);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = AppController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light().copyWith(platform: TargetPlatform.android),
          home: AppShell(controller: controller),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('助手'), findsOneWidget);
      expect(find.text('设置'), findsOneWidget);
      expect(find.text('任务'), findsNothing);
      expect(find.text('工作区'), findsNothing);
      expect(find.text('密钥'), findsNothing);
    });

    testWidgets('desktop shell switches between assistant and settings', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1440, 960);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = AppController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light().copyWith(platform: TargetPlatform.macOS),
          home: AppShell(controller: controller),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('assistant-conversation-shell')), findsOneWidget);
      expect(find.byKey(const Key('settings-account-panel-card')), findsNothing);

      controller.openSettings();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('settings-account-panel-card')), findsOneWidget);
    });
  });
}
