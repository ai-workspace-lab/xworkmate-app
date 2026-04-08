// ignore_for_file: unused_import, unnecessary_import

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/runtime/codex_runtime.dart';
import 'package:xworkmate/runtime/device_identity_store.dart';
import 'package:xworkmate/runtime/gateway_runtime.dart';
import 'package:xworkmate/runtime/runtime_coordinator.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';
import 'app_controller_execution_target_switch_suite_core.dart';
import 'app_controller_execution_target_switch_suite_connection.dart';
import 'app_controller_execution_target_switch_suite_fixtures.dart';
import 'app_controller_execution_target_switch_suite_fakes.dart';

void registerExecutionTargetSwitchThreadTests() {
  group('AppController thread execution target state', () {
    test(
      'AppController switches runtime state when the selected thread changes',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final tempDirectory = await Directory.systemTemp.createTemp(
          'xworkmate-thread-mode-switch-',
        );
        addTearDown(() async {
          await deleteDirectoryWithRetryInternal(tempDirectory);
        });
        final store = SecureConfigStore(
          enableSecureStorage: false,
          databasePathResolver: () async => '${tempDirectory.path}/settings.db',
          fallbackDirectoryPathResolver: () async => tempDirectory.path,
        );
        final gateway = FakeGatewayRuntimeInternal(store: store);
        final controller = AppController(
          store: store,
          runtimeCoordinator: RuntimeCoordinator(
            gateway: gateway,
            codex: FakeCodexRuntimeInternal(),
          ),
        );
        addTearDown(controller.dispose);

        await waitForInternal(() => !controller.initializing);
        await controller.saveSettings(
          withRemoteGatewayProfileInternal(
            controller.settings.copyWith(
              assistantExecutionTarget: AssistantExecutionTarget.local,
              aiGateway: controller.settings.aiGateway.copyWith(
                baseUrl: 'http://127.0.0.1:11434/v1',
                availableModels: const <String>['qwen2.5-coder:latest'],
                selectedModels: const <String>['qwen2.5-coder:latest'],
              ),
            ),
            controller.settings.primaryRemoteGatewayProfile.copyWith(
              mode: RuntimeConnectionMode.remote,
              host: 'gateway.example.com',
              port: 9443,
              tls: true,
            ),
          ),
          refreshAfterSave: false,
        );

        controller.initializeAssistantThreadContext(
          'main',
          executionTarget: AssistantExecutionTarget.singleAgent,
        );
        controller.initializeAssistantThreadContext(
          'remote-thread',
          executionTarget: AssistantExecutionTarget.remote,
        );

        await controller.switchSession('remote-thread');

        expect(
          controller.assistantExecutionTarget,
          AssistantExecutionTarget.remote,
        );
        expect(
          gateway.connectedProfiles.last.mode,
          RuntimeConnectionMode.remote,
        );
        expect(
          controller.settings.assistantExecutionTarget,
          AssistantExecutionTarget.local,
          reason:
              'Thread switching should not overwrite the new-thread default.',
        );

        await controller.switchSession('main');

        expect(
          controller.assistantExecutionTarget,
          AssistantExecutionTarget.singleAgent,
        );
        expect(gateway.disconnectCount, 1);
        expect(controller.assistantConnectionStatusLabel, 'ACP Server Local');
        expect(
          controller.settings.assistantExecutionTarget,
          AssistantExecutionTarget.local,
        );
      },
    );

    test(
      'AppController keeps the thread connection chip aligned with the selected target',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final tempDirectory = await Directory.systemTemp.createTemp(
          'xworkmate-thread-connection-chip-',
        );
        addTearDown(() async {
          await deleteDirectoryWithRetryInternal(tempDirectory);
        });
        final store = SecureConfigStore(
          enableSecureStorage: false,
          databasePathResolver: () async => '${tempDirectory.path}/settings.db',
          fallbackDirectoryPathResolver: () async => tempDirectory.path,
        );
        final gateway = FakeGatewayRuntimeInternal(store: store);
        final controller = AppController(
          store: store,
          runtimeCoordinator: RuntimeCoordinator(
            gateway: gateway,
            codex: FakeCodexRuntimeInternal(),
          ),
        );
        addTearDown(controller.dispose);

        await waitForInternal(() => !controller.initializing);
        await controller.saveSettings(
          withRemoteGatewayProfileInternal(
            controller.settings.copyWith(
              aiGateway: controller.settings.aiGateway.copyWith(
                baseUrl: 'http://127.0.0.1:11434/v1',
                availableModels: const <String>['qwen2.5-coder:latest'],
                selectedModels: const <String>['qwen2.5-coder:latest'],
              ),
              defaultModel: 'qwen2.5-coder:latest',
            ),
            controller.settings.primaryRemoteGatewayProfile.copyWith(
              mode: RuntimeConnectionMode.remote,
              host: 'gateway.example.com',
              port: 9443,
              tls: true,
            ),
          ),
          refreshAfterSave: false,
        );

        await controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.remote,
        );
        await controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.local,
        );
        expect(controller.assistantConnectionStatusLabel, '已连接');
        final expectedLocalProfile =
            controller.settings.primaryLocalGatewayProfile;
        expect(
          controller.assistantConnectionTargetLabel,
          '${expectedLocalProfile.host}:${expectedLocalProfile.port}',
        );

        controller.initializeAssistantThreadContext(
          'remote-thread',
          executionTarget: AssistantExecutionTarget.remote,
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        gateway.failNextConnect(RuntimeConnectionMode.remote);

        await controller.switchSession('remote-thread');

        expect(
          controller.assistantExecutionTarget,
          AssistantExecutionTarget.remote,
        );
        expect(controller.assistantConnectionStatusLabel, '错误');
        expect(
          controller.assistantConnectionTargetLabel,
          'gateway.example.com:9443',
        );
        expect(
          controller.currentAssistantConnectionState.lastError,
          'Failed to connect remote',
        );

        controller.initializeAssistantThreadContext(
          'main',
          executionTarget: AssistantExecutionTarget.singleAgent,
        );
        await controller.switchSession('main');

        expect(controller.assistantConnectionStatusLabel, 'ACP Server Local');
        expect(
          controller.assistantConnectionTargetLabel,
          '没有可用的外部 Agent ACP 端点，请先配置可用的 ACP Server。',
        );
      },
    );

    test(
      'AppController does not attach the previous desktop gateway history to a fresh single-agent task thread',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final tempDirectory = await Directory.systemTemp.createTemp(
          'xworkmate-thread-new-task-history-isolation-',
        );
        addTearDown(() async {
          await deleteDirectoryWithRetryInternal(tempDirectory);
        });
        final store = SecureConfigStore(
          enableSecureStorage: false,
          databasePathResolver: () async => '${tempDirectory.path}/settings.db',
          fallbackDirectoryPathResolver: () async => tempDirectory.path,
        );
        final gateway = FakeGatewayRuntimeInternal(store: store);
        final controller = AppController(
          store: store,
          runtimeCoordinator: RuntimeCoordinator(
            gateway: gateway,
            codex: FakeCodexRuntimeInternal(),
          ),
        );
        addTearDown(controller.dispose);

        await waitForInternal(() => !controller.initializing);
        await controller.saveSettings(
          controller.settings.copyWith(
            workspacePath: tempDirectory.path,
            assistantExecutionTarget: AssistantExecutionTarget.local,
          ),
          refreshAfterSave: false,
        );

        await controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.local,
        );
        controller.chatControllerInternal.messagesInternal =
            <GatewayChatMessage>[
              GatewayChatMessage(
                id: 'gateway-old-message',
                role: 'assistant',
                text: 'previous desktop gateway history',
                timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
                toolCallId: null,
                toolName: null,
                stopReason: null,
                pending: false,
                error: false,
              ),
            ];

        controller.initializeAssistantThreadContext(
          'draft:fresh-thread',
          title: '新对话',
          executionTarget: AssistantExecutionTarget.singleAgent,
        );
        await controller.switchSession('draft:fresh-thread');

        expect(
          controller.gatewayHistoryCacheInternal['draft:fresh-thread'],
          isNull,
        );
        expect(
          controller.assistantThreadMessagesInternal['draft:fresh-thread'] ??
              const <GatewayChatMessage>[],
          isEmpty,
        );
      },
    );

    test('AppController persists markdown view mode per thread', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-thread-view-mode-',
      );
      addTearDown(() async {
        await deleteDirectoryWithRetryInternal(tempDirectory);
      });
      final store = SecureConfigStore(
        enableSecureStorage: false,
        databasePathResolver: () async => '${tempDirectory.path}/settings.db',
        fallbackDirectoryPathResolver: () async => tempDirectory.path,
      );
      final controller = AppController(
        store: store,
        runtimeCoordinator: RuntimeCoordinator(
          gateway: FakeGatewayRuntimeInternal(store: store),
          codex: FakeCodexRuntimeInternal(),
        ),
      );
      addTearDown(controller.dispose);

      await waitForInternal(() => !controller.initializing);

      controller.initializeAssistantThreadContext(
        'main',
        messageViewMode: AssistantMessageViewMode.raw,
      );
      controller.initializeAssistantThreadContext(
        'draft:secondary',
        messageViewMode: AssistantMessageViewMode.rendered,
      );

      await controller.switchSession('main');
      expect(
        controller.currentAssistantMessageViewMode,
        AssistantMessageViewMode.raw,
      );

      await controller.switchSession('draft:secondary');
      expect(
        controller.currentAssistantMessageViewMode,
        AssistantMessageViewMode.rendered,
      );

      await controller.setAssistantMessageViewMode(
        AssistantMessageViewMode.raw,
      );
      expect(
        controller.currentAssistantMessageViewMode,
        AssistantMessageViewMode.raw,
      );

      final reloaded = await store.loadTaskThreads();
      final secondary = reloaded.firstWhere(
        (item) => item.sessionKey == 'draft:secondary',
      );
      expect(secondary.messageViewMode, AssistantMessageViewMode.raw);
    });

    test(
      'AppController restores the last active assistant thread across restart',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final tempDirectory = await Directory.systemTemp.createTemp(
          'xworkmate-thread-restart-',
        );
        addTearDown(() async {
          await deleteDirectoryWithRetryInternal(tempDirectory);
        });
        final databasePath = '${tempDirectory.path}/settings.db';
        final firstStore = SecureConfigStore(
          enableSecureStorage: false,
          databasePathResolver: () async => databasePath,
          fallbackDirectoryPathResolver: () async => tempDirectory.path,
        );
        final firstController = AppController(
          store: firstStore,
          runtimeCoordinator: RuntimeCoordinator(
            gateway: FakeGatewayRuntimeInternal(store: firstStore),
            codex: FakeCodexRuntimeInternal(),
          ),
        );
        addTearDown(firstController.dispose);

        await waitForInternal(() => !firstController.initializing);
        firstController.initializeAssistantThreadContext(
          'draft:alpha',
          title: 'Alpha',
          executionTarget: AssistantExecutionTarget.singleAgent,
        );
        firstController.initializeAssistantThreadContext(
          'draft:beta',
          title: 'Beta',
          executionTarget: AssistantExecutionTarget.local,
        );
        await firstController.saveAssistantTaskTitle('draft:beta', 'Beta Task');
        await firstController.saveAssistantTaskArchived('draft:alpha', true);
        await firstController.switchSession('draft:beta');

        await waitForInternal(
          () =>
              firstController.settings.assistantLastSessionKey == 'draft:beta',
        );

        firstController.dispose();

        final secondStore = SecureConfigStore(
          enableSecureStorage: false,
          databasePathResolver: () async => databasePath,
          fallbackDirectoryPathResolver: () async => tempDirectory.path,
        );
        final secondController = AppController(
          store: secondStore,
          runtimeCoordinator: RuntimeCoordinator(
            gateway: FakeGatewayRuntimeInternal(store: secondStore),
            codex: FakeCodexRuntimeInternal(),
          ),
        );
        addTearDown(secondController.dispose);

        await waitForInternal(() => !secondController.initializing);

        expect(secondController.currentSessionKey, 'draft:beta');
        expect(secondController.settings.assistantLastSessionKey, 'draft:beta');
        expect(
          secondController.assistantCustomTaskTitle('draft:beta'),
          'Beta Task',
        );
        expect(secondController.isAssistantTaskArchived('draft:alpha'), isTrue);
      },
    );

    test(
      'AppController warns once when persisted legacy auto threads are skipped at startup',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final tempDirectory = await Directory.systemTemp.createTemp(
          'xworkmate-thread-legacy-auto-warning-',
        );
        addTearDown(() async {
          await deleteDirectoryWithRetryInternal(tempDirectory);
        });
        final tasksDirectory = Directory('${tempDirectory.path}/tasks');
        await tasksDirectory.create(recursive: true);
        const threadId = 'legacy:auto-thread';
        await File('${tasksDirectory.path}/index.json').writeAsString(
          jsonEncode(<String, dynamic>{
            'version': taskThreadSchemaVersion,
            'sessions': const <String>[threadId],
          }),
          flush: true,
        );
        await File(
          '${tasksDirectory.path}/${encodeStableFileKey(threadId)}.json',
        ).writeAsString(
          jsonEncode(<String, dynamic>{
            'schemaVersion': taskThreadSchemaVersion,
            'threadId': threadId,
            'workspaceBinding': <String, dynamic>{
              'workspaceId': threadId,
              'workspaceKind': WorkspaceKind.localFs.name,
              'workspacePath': '/tmp/$threadId',
              'displayPath': '/tmp/$threadId',
              'writable': true,
            },
            'executionBinding': <String, dynamic>{
              'executionMode': 'auto',
              'executorId': 'auto',
              'providerId': 'auto',
              'endpointId': '',
            },
          }),
          flush: true,
        );

        final store = SecureConfigStore(
          enableSecureStorage: false,
          databasePathResolver: () async => '${tempDirectory.path}/settings.db',
          fallbackDirectoryPathResolver: () async => tempDirectory.path,
        );
        final controller = AppController(
          store: store,
          runtimeCoordinator: RuntimeCoordinator(
            gateway: FakeGatewayRuntimeInternal(store: store),
            codex: FakeCodexRuntimeInternal(),
          ),
        );
        addTearDown(controller.dispose);

        await waitForInternal(() => !controller.initializing);

        expect(controller.currentSessionKey, 'main');
        expect(controller.startupTaskThreadWarning, isNotNull);
        expect(controller.startupTaskThreadWarning, contains('已移除 Auto 执行模式'));
        expect(controller.startupTaskThreadWarning, contains(threadId));
      },
    );

    test(
      'AppController clears local assistant state and resets persisted defaults',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final tempDirectory = await Directory.systemTemp.createTemp(
          'xworkmate-thread-clear-local-',
        );
        addTearDown(() async {
          await deleteDirectoryWithRetryInternal(tempDirectory);
        });
        final databasePath = '${tempDirectory.path}/settings.db';
        final store = SecureConfigStore(
          enableSecureStorage: false,
          databasePathResolver: () async => databasePath,
          fallbackDirectoryPathResolver: () async => tempDirectory.path,
        );
        final controller = AppController(
          store: store,
          runtimeCoordinator: RuntimeCoordinator(
            gateway: FakeGatewayRuntimeInternal(store: store),
            codex: FakeCodexRuntimeInternal(),
          ),
        );
        addTearDown(controller.dispose);

        await waitForInternal(() => !controller.initializing);
        await controller.saveSettings(
          controller.settings.copyWith(accountUsername: 'local-user'),
          refreshAfterSave: false,
        );
        controller.initializeAssistantThreadContext(
          'draft:clear-me',
          title: 'Clear Me',
        );
        await controller.switchSession('draft:clear-me');

        await controller.clearAssistantLocalState();

        expect(controller.currentSessionKey, 'main');
        expect(
          controller.settings.accountUsername,
          SettingsSnapshot.defaults().accountUsername,
        );
        expect(controller.settings.assistantLastSessionKey, 'main');
        expect(controller.assistantCustomTaskTitle('draft:clear-me'), isEmpty);

        final reloadedStore = SecureConfigStore(
          enableSecureStorage: false,
          databasePathResolver: () async => databasePath,
          fallbackDirectoryPathResolver: () async => tempDirectory.path,
        );
        final reloadedSnapshot = await reloadedStore.loadSettingsSnapshot();
        final reloadedThreads = await reloadedStore.loadTaskThreads();

        expect(
          reloadedSnapshot.accountUsername,
          SettingsSnapshot.defaults().accountUsername,
        );
        expect(reloadedSnapshot.assistantLastSessionKey, 'main');
        expect(reloadedThreads, hasLength(1));
        expect(reloadedThreads.single.sessionKey, 'main');
        expect(
          assistantExecutionTargetFromExecutionMode(
            reloadedThreads.single.executionBinding.executionMode,
          ),
          AssistantExecutionTarget.singleAgent,
        );
      },
    );

    test(
      'AppController surfaces pairing-required state on the active assistant thread even if transport still says connected',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final tempDirectory = await Directory.systemTemp.createTemp(
          'xworkmate-thread-pairing-state-',
        );
        addTearDown(() async {
          await deleteDirectoryWithRetryInternal(tempDirectory);
        });
        final store = SecureConfigStore(
          enableSecureStorage: false,
          databasePathResolver: () async => '${tempDirectory.path}/settings.db',
          fallbackDirectoryPathResolver: () async => tempDirectory.path,
        );
        final gateway = FakeGatewayRuntimeInternal(store: store);
        final controller = AppController(
          store: store,
          runtimeCoordinator: RuntimeCoordinator(
            gateway: gateway,
            codex: FakeCodexRuntimeInternal(),
          ),
        );
        addTearDown(controller.dispose);

        await waitForInternal(() => !controller.initializing);
        await controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.local,
        );

        final localProfile = controller.settings.primaryLocalGatewayProfile;
        gateway.fakeSnapshotInternal = gateway.fakeSnapshotInternal.copyWith(
          status: RuntimeConnectionStatus.connected,
          remoteAddress: '${localProfile.host}:${localProfile.port}',
          lastError: 'NOT_PAIRED: pairing required',
          lastErrorCode: 'NOT_PAIRED',
          lastErrorDetailCode: 'PAIRING_REQUIRED',
        );
        gateway.notifyListeners();
        await Future<void>.delayed(Duration.zero);

        expect(
          controller.currentAssistantConnectionState.pairingRequired,
          isTrue,
        );
        expect(controller.currentAssistantConnectionState.connected, isFalse);
        expect(controller.assistantConnectionStatusLabel, '需配对');
        expect(
          controller.assistantConnectionTargetLabel,
          '${localProfile.host}:${localProfile.port}',
        );
      },
    );
  });
}
