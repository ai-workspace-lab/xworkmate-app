import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:xworkmate/app/app.dart';
import 'package:xworkmate/features/assistant/assistant_page.dart';
import 'package:xworkmate/features/settings/settings_page.dart';
import 'package:xworkmate/features/tasks/tasks_page.dart';
import 'package:xworkmate/theme/app_theme.dart';
import '../../test/test_support.dart';

/// Golden UI Tests for Architecture Layers
///
/// These tests capture visual states at each architecture layer:
/// - Layer 2: Multi-end UI Shell
/// - Layer 3: TaskThread Control Plane UI
/// - Layer 4: GoTaskService Dispatch indicators
/// - Layer 5: Service Integration UI

void main() {
  group('Golden Tests: Architecture UI Layers', () {
    setUp(() async {
      await loadAppFonts();
    });

    group('Layer 2: App Shell UI', () {
      testGoldens('desktop shell - main view', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1600, 1000);
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final controller = await createTestController(tester);
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: AppTheme.light(),
            home: Scaffold(body: XWorkmateApp(controller: controller)),
          ),
        );
        await tester.pumpAndSettle();

        await screenMatchesGolden(tester, 'layer2_app_shell_main');
      });

      testGoldens('desktop shell - dark mode', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1600, 1000);
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final controller = await createTestController(tester);
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: AppTheme.dark(),
            home: Scaffold(body: XWorkmateApp(controller: controller)),
          ),
        );
        await tester.pumpAndSettle();

        await screenMatchesGolden(tester, 'layer2_app_shell_dark');
      });
    });

    group('Layer 3: TaskThread Control Plane UI', () {
      testGoldens('task rail with multiple threads', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1600, 1000);
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final controller = await createTestController(tester);
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: AppTheme.light(),
            home: Scaffold(body: XWorkmateApp(controller: controller)),
          ),
        );
        await tester.pumpAndSettle();

        // Create additional threads
        await controller.createThread();
        await tester.pumpAndSettle();
        await controller.createThread();
        await tester.pumpAndSettle();

        await screenMatchesGolden(tester, 'layer3_task_rail_multiple');
      });

      testGoldens('task thread expanded state', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1600, 1000);
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final controller = await createTestController(tester);
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: AppTheme.light(),
            home: Scaffold(body: XWorkmateApp(controller: controller)),
          ),
        );
        await tester.pumpAndSettle();

        // Expand task panel if available
        final taskGroupKey = find.byKey(const ValueKey<String>('assistant-task-group-local'));
        if (taskGroupKey.evaluate().isNotEmpty) {
          await tester.tap(taskGroupKey);
          await tester.pumpAndSettle();
        }

        await screenMatchesGolden(tester, 'layer3_task_thread_expanded');
      });

      testGoldens('thread switch - new thread selected', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1600, 1000);
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final controller = await createTestController(tester);
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: AppTheme.light(),
            home: Scaffold(body: XWorkmateApp(controller: controller)),
          ),
        );
        await tester.pumpAndSettle();

        // Create and switch to new thread
        await controller.createThread();
        await tester.pumpAndSettle();
        await controller.switchSession(controller.threadRecords.last.threadId);
        await tester.pumpAndSettle();

        await screenMatchesGolden(tester, 'layer3_thread_switched');
      });
    });

    group('Layer 4: GoTaskService Dispatch UI', () {
      testGoldens('execution mode - single agent', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1600, 1000);
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final controller = await createTestController(tester);
        await controller.settingsController.saveAiGatewayApiKey('live-key');
        await controller.saveSettings(
          controller.settings.copyWith(
            aiGateway: controller.settings.aiGateway.copyWith(
              baseUrl: 'http://127.0.0.1:11434/v1',
              availableModels: const ['qwen2.5-coder:latest'],
            ),
            assistantExecutionTarget: AssistantExecutionTarget.singleAgent,
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: AppTheme.light(),
            home: Scaffold(body: XWorkmateApp(controller: controller)),
          ),
        );
        await tester.pumpAndSettle();

        await screenMatchesGolden(tester, 'layer4_execution_single_agent');
      });

      testGoldens('execution mode - gateway remote', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1600, 1000);
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final controller = await createTestController(tester);
        await controller.settingsController.saveAiGatewayApiKey('live-key');
        await controller.saveSettings(
          controller.settings.copyWith(
            aiGateway: controller.settings.aiGateway.copyWith(
              baseUrl: 'http://127.0.0.1:11434/v1',
            ),
            assistantExecutionTarget: AssistantExecutionTarget.gatewayRemote,
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: AppTheme.light(),
            home: Scaffold(body: XWorkmateApp(controller: controller)),
          ),
        );
        await tester.pumpAndSettle();

        await screenMatchesGolden(tester, 'layer4_execution_gateway_remote');
      });

      testGoldens('connection status chip', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1600, 1000);
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final controller = await createTestController(tester);
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: AppTheme.light(),
            home: Scaffold(body: XWorkmateApp(controller: controller)),
          ),
        );
        await tester.pumpAndSettle();

        await screenMatchesGolden(tester, 'layer4_connection_chip');
      });
    });

    group('Layer 5: Service Integration UI', () {
      testGoldens('settings page - integration tab', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1600, 1000);
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final controller = await createTestController(tester);
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: AppTheme.light(),
            home: Scaffold(body: XWorkmateApp(controller: controller)),
          ),
        );
        await tester.pumpAndSettle();

        // Navigate to settings
        final menuKey = find.byKey(const ValueKey<String>('assistant-focus-add-menu'));
        if (menuKey.evaluate().isNotEmpty) {
          await tester.tap(menuKey);
          await tester.pumpAndSettle();

          final settingsItem = find.byWidgetPredicate(
            (w) => w is Text && (w.data == '设置' || w.data == 'Settings'),
          );
          if (settingsItem.evaluate().isNotEmpty) {
            await tester.tap(settingsItem.first);
            await tester.pumpAndSettle();
          }
        }

        await screenMatchesGolden(tester, 'layer5_settings_integration');
      });

      testGoldens('settings page - skills tab', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1600, 1000);
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final controller = await createTestController(tester);
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: AppTheme.light(),
            home: Scaffold(body: XWorkmateApp(controller: controller)),
          ),
        );
        await tester.pumpAndSettle();

        await screenMatchesGolden(tester, 'layer5_settings_skills');
      });
    });

    group('Responsive Layout Goldens', () {
      testGoldens('desktop 1600x1000 main view', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1600, 1000);
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final controller = await createTestController(tester);
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: AppTheme.light(),
            home: Scaffold(body: XWorkmateApp(controller: controller)),
          ),
        );
        await tester.pumpAndSettle();

        await screenMatchesGolden(tester, 'responsive_1600x1000');
      });

      testGoldens('desktop 1920x1080 main view', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1920, 1080);
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final controller = await createTestController(tester);
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: AppTheme.light(),
            home: Scaffold(body: XWorkmateApp(controller: controller)),
          ),
        );
        await tester.pumpAndSettle();

        await screenMatchesGolden(tester, 'responsive_1920x1080');
      });

      testGoldens('tablet 768x1024 main view', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(768, 1024);
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final controller = await createTestController(tester);
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: AppTheme.light(),
            home: Scaffold(body: XWorkmateApp(controller: controller)),
          ),
        );
        await tester.pumpAndSettle();

        await screenMatchesGolden(tester, 'responsive_768x1024');
      });
    });
  });
}
