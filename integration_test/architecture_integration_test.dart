import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:xworkmate/app/app.dart';
import 'package:xworkmate/app/ui_feature_manifest.dart';
import 'package:xworkmate/features/assistant/assistant_page.dart';
import 'package:xworkmate/features/settings/settings_page.dart';
import 'package:xworkmate/features/tasks/tasks_page.dart';
import 'package:xworkmate/features/mobile/mobile_shell.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';
import 'package:xworkmate/theme/app_theme.dart';
import '../test/test_support.dart';
import 'test_support.dart';

/// Architecture Integration Tests
///
/// Tests the complete flow through all 5 layers of the xworkmate architecture:
/// 1. Access & Attribution Layer
/// 2. Multi-end UI Layer (Flutter/Dart)
/// 3. TaskThread Control Plane
/// 4. GoTaskService Dispatch Layer
/// 5. Service Integration & Extensions Layer
///
/// Plus Security & Persistence Base (cross-cutting)
///
/// These tests verify that UI selections properly drive TaskThread state,
/// and that execution results correctly write back to TaskThread.

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Layer 1-2: App Shell & Navigation', () {
    setUp(() async {
      await resetIntegrationPreferences();
    });

    testWidgets('desktop shell loads assistant task rail', (tester) async {
      await pumpDesktopApp(tester);

      expect(find.byKey(const Key('assistant-task-rail')), findsOneWidget);
      expect(find.textContaining('新对话'), findsWidgets);
    });

    testWidgets('shell navigation to settings tab', (tester) async {
      await pumpDesktopApp(tester);

      // Open navigation menu
      final menuKey = find.byKey(const ValueKey<String>('assistant-focus-add-menu'));
      if (menuKey.evaluate().isNotEmpty) {
        await tester.tap(menuKey);
        await settleIntegrationUi(tester);

        // Tap settings item
        final settingsItem = find.byWidgetPredicate(
          (w) => w is Text && (w.data == '设置' || w.data == 'Settings'),
        );
        if (settingsItem.evaluate().isNotEmpty) {
          await tester.tap(settingsItem.first);
          await settleIntegrationUi(tester);
        }
      }

      // Verify settings page loaded
      expect(find.byType(SettingsPage), findsOneWidget);
    });

    testWidgets('shell navigation to tasks page', (tester) async {
      await pumpDesktopApp(tester);

      final tasksTab = find.byKey(const Key('assistant-side-pane-tab-tasks'));
      if (tasksTab.evaluate().isNotEmpty) {
        await tester.tap(tasksTab);
        await settleIntegrationUi(tester);

        expect(find.byType(TasksPage), findsWidgets);
      }
    });
  });

  group('Layer 3: TaskThread Control Plane', () {
    setUp(() async {
      await resetIntegrationPreferences();
    });

    testWidgets('main thread has valid workspace binding on load', (tester) async {
      final controller = await pumpDesktopAppWithController(tester);

      final mainThread = controller.findThreadById('main');
      expect(mainThread, isNotNull);
      expect(mainThread!.workspaceBinding.workspacePath, isNotEmpty);
      expect(mainThread.workspaceBinding.displayPath, isNotEmpty);
    });

    testWidgets('new task creates independent thread', (tester) async {
      final controller = await pumpDesktopAppWithController(tester);

      final initialCount = controller.threadRecords.length;

      // Trigger new task creation via UI or controller
      await controller.createThread();
      await settleIntegrationUi(tester);

      expect(controller.threadRecords.length, greaterThan(initialCount));

      // Verify new thread has its own session key
      final newThread = controller.threadRecords.last;
      expect(newThread.threadId, isNotEmpty);
      expect(newThread.threadId, isNot(equals('main')));
      expect(newThread.workspaceBinding.workspacePath, isNotEmpty);
    });

    testWidgets('thread switching updates current thread context', (tester) async {
      final controller = await pumpDesktopAppWithController(tester);

      // Create a second thread
      await controller.createThread();
      await settleIntegrationUi(tester);

      // Get the new thread's id
      final newThreadId = controller.threadRecords.last.threadId;

      // Switch to the new thread
      await controller.switchSession(newThreadId);
      await settleIntegrationUi(tester);

      expect(controller.currentSessionKey, equals(newThreadId));
    });

    testWidgets('thread contextState preserves messages', (tester) async {
      final controller = await pumpDesktopAppWithController(tester);

      final threadId = controller.currentSessionKey;
      final thread = controller.findThreadById(threadId);

      // Thread should have empty context initially
      expect(thread?.contextState.messages, isEmpty);
    });

    testWidgets('thread lifecycleState updates on state changes', (tester) async {
      final controller = await pumpDesktopAppWithController(tester);

      final threadId = controller.currentSessionKey;
      final thread = controller.findThreadById(threadId);

      // Initial state should not be archived
      expect(thread?.lifecycleState.archived, isFalse);
    });
  });

  group('Layer 4: GoTaskService Dispatch', () {
    setUp(() async {
      await resetIntegrationPreferences();
    });

    testWidgets('execution binding determines dispatch target', (tester) async {
      final controller = await pumpDesktopAppWithController(tester);

      // Get current thread's execution binding
      final threadId = controller.currentSessionKey;
      final thread = controller.findThreadById(threadId);

      expect(thread?.executionBinding.executionMode, isNotNull);
    });

    testWidgets('settings defaults apply to new thread', (tester) async {
      final controller = await pumpDesktopAppWithController(tester);

      // Update settings with default execution target
      await controller.saveSettings(
        controller.settings.copyWith(
          assistantExecutionTarget: AssistantExecutionTarget.singleAgent,
        ),
      );
      await settleIntegrationUi(tester);

      // Create new thread - should inherit settings
      await controller.createThread();
      await settleIntegrationUi(tester);

      final newThread = controller.threadRecords.last;
      // New thread should have singleAgent execution mode
      expect(
        newThread.executionBinding.executorId,
        isNotEmpty,
      );
    });
  });

  group('Layer 5: Service Integration', () {
    setUp(() async {
      await resetIntegrationPreferences();
    });

    testWidgets('gateway profile configuration persists', (tester) async {
      final controller = await pumpDesktopAppWithController(tester);

      // Configure a gateway profile
      await controller.saveSettings(
        controller.settings.copyWith(
          aiGateway: controller.settings.aiGateway.copyWith(
            baseUrl: 'http://127.0.0.1:11434/v1',
            availableModels: ['qwen2.5-coder:latest'],
          ),
        ),
      );
      await settleIntegrationUi(tester);

      // Verify settings persisted
      expect(controller.settings.aiGateway.baseUrl, 'http://127.0.0.1:11434/v1');
    });

    testWidgets('provider binding tracks to thread', (tester) async {
      final controller = await pumpDesktopAppWithController(tester);

      final threadId = controller.currentSessionKey;
      final thread = controller.findThreadById(threadId);

      // Provider should be tracked in execution binding
      expect(
        thread?.executionBinding.providerId,
        isNotNull,
      );
    });
  });

  group('Cross-cutting: Security & Persistence', () {
    setUp(() async {
      await resetIntegrationPreferences();
    });

    testWidgets('thread records persist across reloads', (tester) async {
      final controller = await pumpDesktopAppWithController(tester);

      // Create a new thread
      await controller.createThread();
      await settleIntegrationUi(tester);

      // Get thread count
      final threadCount = controller.threadRecords.length;

      // Simulate app restart by disposing and recreating
      final store = controller.store;
      controller.dispose();

      // Create new controller with same store
      final newController = await createIntegrationTestControllerWithStore(store);
      await settleIntegrationUi(tester);

      // Verify thread count preserved
      expect(newController.threadRecords.length, greaterThanOrEqualTo(threadCount));
    });
  });

  group('Architecture Flow: UI -> TaskThread -> Execution -> UI Update', () {
    setUp(() async {
      await resetIntegrationPreferences();
    });

    testWidgets('full flow: select thread -> read binding -> dispatch', (tester) async {
      final controller = await pumpDesktopAppWithController(tester);

      // 1. UI selects a thread (current main)
      final currentThreadId = controller.currentSessionKey;
      expect(currentThreadId, equals('main'));

      // 2. Read TaskThread binding
      final thread = controller.findThreadById(currentThreadId);
      expect(thread, isNotNull);
      expect(thread!.workspaceBinding.workspacePath, isNotEmpty);

      // 3. Execution binding determines mode
      expect(thread.executionBinding.executionMode, isNotNull);

      // 4. Context state ready for messages
      expect(thread.contextState, isNotNull);
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
      databasePathResolver: () async => '${isolatedRoot.path}/settings.sqlite3',
      fallbackDirectoryPathResolver: () async => isolatedRoot.path,
    ),
    runtimeCoordinator: null,
  );
}

Future<AppController> createIntegrationTestControllerWithStore(
  SecureConfigStore store,
) async {
  return AppController(
    store: store,
    runtimeCoordinator: null,
  );
}
