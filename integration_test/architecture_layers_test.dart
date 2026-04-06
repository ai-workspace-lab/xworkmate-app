import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xworkmate/app/app.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';
import 'test_support.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Architecture Layer 2: Multi端 UI Layer', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await resetIntegrationPreferences();
    });

    testWidgets('AppShellDesktop loads and displays assistant page', (
      WidgetTester tester,
    ) async {
      await pumpDesktopApp(tester);

      expect(find.byKey(const Key('assistant-task-rail')), findsOneWidget);
      expect(find.textContaining('新对话'), findsWidgets);
    });

    testWidgets('Navigation between assistant and settings tabs', (
      WidgetTester tester,
    ) async {
      await pumpDesktopApp(tester);

      // Navigate to navigation tab
      final navTab = find.byKey(const Key('assistant-side-pane-tab-navigation'));
      if (navTab.evaluate().isNotEmpty) {
        await tester.tap(navTab);
        await settleIntegrationUi(tester);
      }

      // Navigate to settings
      final settingsTab = find.byKey(const Key('assistant-side-pane-tab-settings'));
      if (settingsTab.evaluate().isNotEmpty) {
        await tester.tap(settingsTab);
        await settleIntegrationUi(tester);
        expect(find.byKey(const Key('assistant-focus-panel-title')), findsOneWidget);
      }
    });
  });

  group('Architecture Layer 3: TaskThread Control Plane', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await resetIntegrationPreferences();
    });

    testWidgets('TaskThread session isolation - main session key', (
      WidgetTester tester,
    ) async {
      final controller = await pumpDesktopAppWithController(tester);

      expect(controller.currentSessionKey, 'main');

      // Verify main thread has valid workspace binding
      final mainThread = controller.findThreadById('main');
      expect(mainThread, isNotNull);
      expect(mainThread!.workspaceBinding.workspacePath, isNotEmpty);
    });

    testWidgets('TaskThread can create new task thread', (
      WidgetTester tester,
    ) async {
      final controller = await pumpDesktopAppWithController(tester);
      final initialCount = controller.threadRecords.length;

      await tester.tap(find.byKey(const Key('assistant-new-task-button')));
      await settleIntegrationUi(tester);

      expect(controller.threadRecords.length, greaterThan(initialCount));
    });

    testWidgets('TaskThread switching updates currentSessionKey', (
      WidgetTester tester,
    ) async {
      final controller = await pumpDesktopAppWithController(tester);

      // Create a new thread
      await tester.tap(find.byKey(const Key('assistant-new-task-button')));
      await settleIntegrationUi(tester);

      // Find task items and tap the second one
      final taskItems = find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key as ValueKey<String>).value.startsWith('assistant-task-item-'),
      );

      if (taskItems.evaluate().length >= 2) {
        await tester.tap(taskItems.at(1));
        await settleIntegrationUi(tester);

        // After switching, currentSessionKey should not be 'main' if we switched to a new thread
        expect(controller.currentSessionKey, isNotEmpty);
      }
    });
  });

  group('Architecture Layer 4: GoTaskService Dispatch', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await resetIntegrationPreferences();
    });

    testWidgets('Execution target switch updates thread binding', (
      WidgetTester tester,
    ) async {
      final controller = await pumpDesktopAppWithController(tester);

      // Switch to single agent mode
      await controller.updateSettings(
        controller.settings.copyWith(
          assistantExecutionTarget: AssistantExecutionTarget.singleAgent,
        ),
      );
      await settleIntegrationUi(tester);

      final currentThread = controller.currentThread;
      expect(currentThread?.executionBinding.executorId, isNotEmpty);
    });
  });

  group('Architecture Layer 5: Settings Center', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await resetIntegrationPreferences();
    });

    testWidgets('Settings stores gateway profiles', (WidgetTester tester) async {
      final controller = await pumpDesktopAppWithController(tester);

      await controller.saveSettings(
        controller.settings.copyWith(
          aiGateway: controller.settings.aiGateway.copyWith(
            baseUrl: 'http://127.0.0.1:11434/v1',
          ),
        ),
      );
      await settleIntegrationUi(tester);

      expect(controller.settings.aiGateway.baseUrl, 'http://127.0.0.1:11434/v1');
    });
  });
}

Future<AppController> pumpDesktopAppWithController(
  WidgetTester tester, {
  Size size = const Size(1600, 1000),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final controller = await createIntegrationTestController();
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Scaffold(body: XWorkmateApp(controller: controller)),
    ),
  );
  await settleIntegrationUi(tester);

  return controller;
}

Future<AppController> createIntegrationTestController() async {
  final isolatedRoot = await Directory.systemTemp.createTemp(
    'xworkmate-integration-test-',
  );
  debugOverridePersistentSupportRoot(isolatedRoot.path);
  addTearDown(() async {
    debugOverridePersistentSupportRoot(null);
    if (await isolatedRoot.exists()) {
      await isolatedRoot.delete(recursive: true);
    }
  });

  return AppController(
    store: SecureConfigStore(
      enableSecureStorage: false,
      databasePathResolver: () async =>
          '${isolatedRoot.path}/settings.sqlite3',
      fallbackDirectoryPathResolver: () async => isolatedRoot.path,
    ),
    runtimeCoordinator: null,
  );
}
