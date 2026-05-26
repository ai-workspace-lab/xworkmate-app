import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/app/app_shell_desktop.dart';
import 'package:xworkmate/models/app_models.dart';
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

      final controller = AppController(
        environmentOverride: const <String, String>{},
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light().copyWith(platform: TargetPlatform.android),
          home: AppShell(controller: controller),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('mobile-assistant-page')), findsOneWidget);
      expect(find.byKey(const Key('mobile-settings-page')), findsNothing);

      controller.openSettings();
      await tester.pump();

      expect(find.byKey(const Key('mobile-settings-page')), findsOneWidget);
      expect(find.text('Mobile-safe'), findsNothing);
      expect(find.text('安全审批'), findsNothing);
      expect(find.byKey(const Key('mobile-safe-strip')), findsNothing);
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

      final controller = AppController(
        environmentOverride: const <String, String>{},
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light().copyWith(platform: TargetPlatform.macOS),
          home: AppShell(controller: controller),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const Key('assistant-conversation-shell')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('settings-account-panel-card')),
        findsNothing,
      );

      controller.openSettings();
      await tester.pump();

      expect(
        find.byKey(const Key('settings-account-panel-card')),
        findsOneWidget,
      );

      controller.openSettings(tab: SettingsTab.archivedTasks);
      await tester.pump();

      expect(
        find.byKey(const Key('settings-archived-tasks-panel-card')),
        findsOneWidget,
      );
    });
  });
}
