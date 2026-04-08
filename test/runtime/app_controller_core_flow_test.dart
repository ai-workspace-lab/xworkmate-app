import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/runtime/runtime_coordinator.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';

import 'app_controller_execution_target_switch_suite_fakes.dart';
import 'app_controller_execution_target_switch_suite_fixtures.dart';

void main() {
  group('AppController core execution target flows', () {
    test(
      'core flow 01 opens a new conversation and switches to single agent',
      () async {
        final controller = await createCoreFlowControllerInternal();
        addTearDown(controller.dispose);

        final sessionKey = buildDraftSessionKeyInternal();
        controller.initializeAssistantThreadContext(
          sessionKey,
          title: '新对话',
          executionTarget: AssistantExecutionTarget.local,
        );

        await controller.switchSession(sessionKey);
        await controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.singleAgent,
        );

        expect(controller.currentSessionKey, sessionKey);
        expect(
          controller.currentAssistantExecutionTarget,
          AssistantExecutionTarget.singleAgent,
        );
        expect(controller.currentAssistantConnectionState.isSingleAgent, isTrue);
        expect(controller.assistantConnectionStatusLabel, 'ACP Server');
      },
    );

    test(
      'core flow 02 opens a new conversation and switches to local openclaw gateway',
      () async {
        final controller = await createCoreFlowControllerInternal();
        addTearDown(controller.dispose);

        final sessionKey = buildDraftSessionKeyInternal();
        controller.initializeAssistantThreadContext(
          sessionKey,
          title: '新对话',
          executionTarget: AssistantExecutionTarget.singleAgent,
        );

        await controller.switchSession(sessionKey);
        await controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.local,
        );

        expect(controller.currentSessionKey, sessionKey);
        expect(
          controller.currentAssistantExecutionTarget,
          AssistantExecutionTarget.local,
        );
        expect(controller.currentAssistantConnectionState.isSingleAgent, isFalse);
        expect(controller.assistantConnectionStatusLabel, '已连接');
        expect(controller.assistantConnectionTargetLabel, '127.0.0.1:4317');
      },
    );

    test(
      'core flow 03 opens a new conversation and switches to remote openclaw gateway',
      () async {
        final controller = await createCoreFlowControllerInternal();
        addTearDown(controller.dispose);

        final sessionKey = buildDraftSessionKeyInternal();
        controller.initializeAssistantThreadContext(
          sessionKey,
          title: '新对话',
          executionTarget: AssistantExecutionTarget.singleAgent,
        );

        await controller.switchSession(sessionKey);
        await controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.remote,
        );

        expect(controller.currentSessionKey, sessionKey);
        expect(
          controller.currentAssistantExecutionTarget,
          AssistantExecutionTarget.remote,
        );
        expect(controller.currentAssistantConnectionState.isSingleAgent, isFalse);
        expect(controller.assistantConnectionStatusLabel, '已连接');
        expect(
          controller.assistantConnectionTargetLabel,
          'gateway.example.com:9443',
        );
      },
    );
  });
}

Future<AppController> createCoreFlowControllerInternal() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final tempDirectory = await Directory.systemTemp.createTemp(
    'xworkmate-core-flow-',
  );
  addTearDown(() async {
    await deleteDirectoryWithRetryInternal(tempDirectory);
  });
  final store = SecureConfigStore(
    enableSecureStorage: false,
    databasePathResolver: () async => '${tempDirectory.path}/settings.db',
    fallbackDirectoryPathResolver: () async => tempDirectory.path,
    defaultSupportDirectoryPathResolver: () async => tempDirectory.path,
  );
  final gateway = FakeGatewayRuntimeInternal(store: store);
  final controller = AppController(
    store: store,
    runtimeCoordinator: RuntimeCoordinator(
      gateway: gateway,
      codex: FakeCodexRuntimeInternal(),
    ),
  );

  await waitForInternal(() => !controller.initializing);
  final defaults = controller.settings;
  await controller.saveSettings(
    defaults
        .copyWith(
          workspacePath: tempDirectory.path,
          externalAcpEndpoints: normalizeExternalAcpEndpoints(
            profiles: <ExternalAcpEndpointProfile>[
              ...defaults.externalAcpEndpoints,
              ExternalAcpEndpointProfile.defaultsForProvider(
                SingleAgentProvider.opencode,
              ).copyWith(
                endpoint: 'https://acp-server.svc.plus/opencode',
                enabled: true,
              ),
            ],
          ),
        )
        .copyWithGatewayProfileAt(
          kGatewayLocalProfileIndex,
          defaults.primaryLocalGatewayProfile.copyWith(
            host: '127.0.0.1',
            port: 4317,
            tls: false,
          ),
        )
        .copyWithGatewayProfileAt(
          kGatewayRemoteProfileIndex,
          defaults.primaryRemoteGatewayProfile.copyWith(
            host: 'gateway.example.com',
            port: 9443,
            tls: true,
          ),
        )
        .markGatewayTargetSaved(AssistantExecutionTarget.local)
        .markGatewayTargetSaved(AssistantExecutionTarget.remote),
    refreshAfterSave: false,
  );
  return controller;
}

String buildDraftSessionKeyInternal() =>
    'draft:${DateTime.now().microsecondsSinceEpoch}';
