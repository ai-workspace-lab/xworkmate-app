// ignore_for_file: unused_import, unnecessary_import

import 'dart:async';
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
import 'app_controller_execution_target_switch_suite_thread.dart';
import 'app_controller_execution_target_switch_suite_fixtures.dart';
import 'app_controller_execution_target_switch_suite_fakes.dart';

void registerExecutionTargetSwitchConnectionTests() {
  group('AppController execution target connection switching', () {
    test(
      'AppController switches gateway connection when assistant execution target changes',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final tempDirectory = await Directory.systemTemp.createTemp(
          'xworkmate-execution-target-switch-',
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
              assistantExecutionTarget: AssistantExecutionTarget.singleAgent,
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
              selectedAgentId: 'assistant-main',
            ),
          ),
          refreshAfterSave: false,
        );

        await controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.remote,
        );

        expect(
          gateway.connectedProfiles.last,
          isA<GatewayConnectionProfile>()
              .having((item) => item.mode, 'mode', RuntimeConnectionMode.remote)
              .having((item) => item.host, 'host', 'gateway.example.com')
              .having((item) => item.port, 'port', 9443)
              .having((item) => item.tls, 'tls', isTrue)
              .having(
                (item) => item.selectedAgentId,
                'selectedAgentId',
                'assistant-main',
              ),
        );
        expect(
          controller.settings.assistantExecutionTarget,
          AssistantExecutionTarget.remote,
        );

        await controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.local,
        );
        final expectedLocalProfile =
            controller.settings.primaryLocalGatewayProfile;

        expect(
          gateway.connectedProfiles.last,
          isA<GatewayConnectionProfile>()
              .having((item) => item.mode, 'mode', RuntimeConnectionMode.local)
              .having((item) => item.host, 'host', expectedLocalProfile.host)
              .having((item) => item.port, 'port', expectedLocalProfile.port)
              .having((item) => item.tls, 'tls', isFalse)
              .having(
                (item) => item.selectedAgentId,
                'selectedAgentId',
                expectedLocalProfile.selectedAgentId,
              ),
        );
        expect(
          controller.settings.assistantExecutionTarget,
          AssistantExecutionTarget.local,
        );
        expect(
          controller.settings.primaryRemoteGatewayProfile.host,
          'gateway.example.com',
          reason:
              'Saved remote profile should remain intact after local switch.',
        );
        expect(controller.settings.primaryRemoteGatewayProfile.port, 9443);
        expect(
          controller.settings.primaryRemoteGatewayProfile.mode,
          RuntimeConnectionMode.remote,
        );

        await controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.singleAgent,
        );

        expect(
          controller.settings.assistantExecutionTarget,
          AssistantExecutionTarget.singleAgent,
        );
        expect(
          controller.settings.primaryRemoteGatewayProfile.host,
          'gateway.example.com',
          reason:
              'Single Agent mode should preserve the saved remote endpoint.',
        );
        expect(controller.settings.primaryRemoteGatewayProfile.port, 9443);
        expect(controller.settings.primaryRemoteGatewayProfile.tls, isTrue);
        expect(
          controller.settings.primaryRemoteGatewayProfile.mode,
          RuntimeConnectionMode.remote,
        );
        expect(gateway.disconnectCount, 1);
        expect(controller.assistantConnectionStatusLabel, 'ACP Server Local');
        expect(
          controller.assistantConnectionTargetLabel,
          '没有可用的外部 Agent ACP 端点，请配置 LLM API fallback。',
        );
        expect(
          gateway.connectedProfiles,
          hasLength(2),
          reason: 'Single Agent mode should not open another gateway session.',
        );

        await controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.remote,
        );

        expect(
          gateway.connectedProfiles.last,
          isA<GatewayConnectionProfile>()
              .having((item) => item.mode, 'mode', RuntimeConnectionMode.remote)
              .having((item) => item.host, 'host', 'gateway.example.com')
              .having((item) => item.port, 'port', 9443)
              .having((item) => item.tls, 'tls', isTrue)
              .having(
                (item) => item.selectedAgentId,
                'selectedAgentId',
                'assistant-main',
              ),
        );
      },
    );

    test(
      'AppController notifies execution target changes before connect completes',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final tempDirectory = await Directory.systemTemp.createTemp(
          'xworkmate-execution-target-notify-',
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

        int notificationCount = 0;
        controller.addListener(() {
          notificationCount += 1;
        });

        final connectGate = Completer<void>();
        gateway.holdNextConnect(connectGate);

        final switchFuture = controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.remote,
        );
        var completed = false;
        switchFuture.then((_) {
          completed = true;
        });

        await Future<void>.delayed(Duration.zero);

        expect(notificationCount, greaterThan(0));
        expect(
          controller.assistantExecutionTarget,
          AssistantExecutionTarget.remote,
        );
        expect(
          controller.assistantConnectionTargetLabel,
          'gateway.example.com:9443',
        );
        expect(completed, isFalse);

        connectGate.complete();
        await switchFuture;

        expect(
          controller.settings.assistantExecutionTarget,
          AssistantExecutionTarget.remote,
        );
        expect(
          gateway.connectedProfiles.last.mode,
          RuntimeConnectionMode.remote,
        );
      },
    );

    test(
      'AppController applySettingsDraft keeps the active thread manual execution target',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final tempDirectory = await Directory.systemTemp.createTemp(
          'xworkmate-apply-settings-sync-',
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
              workspacePath: tempDirectory.path,
              assistantExecutionTarget: AssistantExecutionTarget.local,
              aiGateway: controller.settings.aiGateway.copyWith(
                baseUrl: 'http://127.0.0.1:11434/v1',
                availableModels: const <String>['qwen2.5-coder:latest'],
                selectedModels: const <String>['qwen2.5-coder:latest'],
              ),
              defaultModel: 'qwen2.5-coder:latest',
            ),
            controller.settings.primaryRemoteGatewayProfile.copyWith(
              mode: RuntimeConnectionMode.remote,
              host: 'openclaw.svc.plus',
              port: 443,
              tls: true,
            ),
          ),
          refreshAfterSave: false,
        );

        await controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.singleAgent,
        );

        await controller.saveSettingsDraft(
          controller.settingsDraft.copyWith(
            assistantExecutionTarget: AssistantExecutionTarget.remote,
          ),
        );
        await controller.applySettingsDraft();

        expect(
          controller.currentAssistantExecutionTarget,
          AssistantExecutionTarget.singleAgent,
        );
        expect(
          controller.assistantExecutionTargetForSession(
            controller.currentSessionKey,
          ),
          AssistantExecutionTarget.singleAgent,
        );
        expect(
          controller.settings.assistantExecutionTarget,
          AssistantExecutionTarget.remote,
        );
        expect(controller.assistantConnectionStatusLabel, 'ACP Server Local');
      },
    );

    test(
      'AppController does not leak the local endpoint into remote thread status while reconnecting',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final tempDirectory = await Directory.systemTemp.createTemp(
          'xworkmate-execution-target-remote-fallback-',
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
          withLocalGatewayProfileInternal(
            controller.settings,
            controller.settings.primaryLocalGatewayProfile.copyWith(
              mode: RuntimeConnectionMode.local,
              host: '127.0.0.1',
              port: 18789,
              tls: false,
            ),
          ),
          refreshAfterSave: false,
        );

        final connectGate = Completer<void>();
        gateway.holdNextConnect(connectGate);

        final switchFuture = controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.remote,
        );

        await Future<void>.delayed(Duration.zero);

        expect(
          controller.assistantExecutionTarget,
          AssistantExecutionTarget.remote,
        );
        expect(controller.assistantConnectionStatusLabel, '离线');
        expect(
          controller.assistantConnectionTargetLabel,
          'openclaw.svc.plus:443',
        );

        connectGate.complete();
        await switchFuture;
      },
    );

    test(
      'AppController notifies singleAgent target changes before disconnect completes',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final tempDirectory = await Directory.systemTemp.createTemp(
          'xworkmate-execution-target-disconnect-notify-',
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
              assistantExecutionTarget: AssistantExecutionTarget.singleAgent,
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

        int notificationCount = 0;
        controller.addListener(() {
          notificationCount += 1;
        });

        final disconnectGate = Completer<void>();
        gateway.holdNextDisconnect(disconnectGate);

        final switchFuture = controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.singleAgent,
        );
        var completed = false;
        switchFuture.then((_) {
          completed = true;
        });

        try {
          await waitForInternal(() => gateway.disconnectCount == 1);

          expect(notificationCount, greaterThan(0));
          expect(
            controller.assistantExecutionTarget,
            AssistantExecutionTarget.singleAgent,
          );
          expect(controller.assistantConnectionStatusLabel, 'ACP Server Local');
          expect(completed, isFalse);
        } finally {
          if (!disconnectGate.isCompleted) {
            disconnectGate.complete();
          }
        }

        await switchFuture;

        expect(
          controller.settings.assistantExecutionTarget,
          AssistantExecutionTarget.singleAgent,
        );
        expect(
          controller.assistantExecutionTarget,
          AssistantExecutionTarget.singleAgent,
        );
        expect(controller.assistantConnectionStatusLabel, 'ACP Server Local');
      },
    );
  });
}
