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
import 'package:xworkmate/runtime/go_task_service_client.dart';
import 'package:xworkmate/runtime/runtime_coordinator.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';
import 'app_controller_ai_gateway_chat_suite_core.dart';
import 'app_controller_ai_gateway_chat_suite_fakes.dart';
import 'app_controller_ai_gateway_chat_suite_fixtures.dart';

void registerAppControllerAiGatewayChatSuiteSingleAgentTestsInternal() {
  group('Single Agent provider resolution', () {
    test(
      'AppController uses the selected Single Agent provider before ACP execution',
      () async {
        final tempDirectory = await createTempDirectoryInternal(
          'xworkmate-single-agent-provider-',
        );
        final store = createStoreFromTempDirectoryInternal(tempDirectory);
        final client = FakeGoTaskServiceClientInternal(
          capabilities: ExternalCodeAgentAcpCapabilities(
            singleAgent: true,
            multiAgent: false,
            providers: <SingleAgentProvider>{SingleAgentProvider.opencode},
            raw: <String, dynamic>{},
          ),
          result: const GoTaskServiceResult(
            success: true,
            message: 'CODEX_REPLY',
            turnId: 'turn-1',
            raw: <String, dynamic>{},
            errorMessage: '',
            resolvedModel: 'codex-sonnet',
            route: GoTaskServiceRoute.externalAcpSingle,
          ),
        );
        final controller = AppController(
          store: store,
          runtimeCoordinator: RuntimeCoordinator(
            gateway: FakeGatewayRuntimeInternal(store: store),
            codex: FakeCodexRuntimeInternal(),
          ),
          goTaskServiceClient: client,
        );
        addTearDown(controller.dispose);
        await waitForInternal(() => !controller.initializing);
        await controller.saveSettings(
          controller.settings.copyWith(
            multiAgent: controller.settings.multiAgent.copyWith(
              autoSync: false,
            ),
          ),
          refreshAfterSave: false,
        );

        await controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.singleAgent,
        );
        await controller.setSingleAgentProvider(SingleAgentProvider.opencode);

        await controller.sendChatMessage('请输出 CODEX_REPLY', thinking: 'low');

        expect(client.capabilitiesCalls, greaterThanOrEqualTo(1));
        expect(client.executeCalls, 1);
        expect(client.lastRequest?.provider, SingleAgentProvider.opencode);
        expect(client.lastRequest?.model, isEmpty);
        expect(controller.currentSingleAgentModelDisplayLabel, 'codex-sonnet');
        expect(
          controller.chatMessages.any(
            (message) =>
                message.role == 'assistant' && message.text == 'CODEX_REPLY',
          ),
          isTrue,
        );
        expect(
          controller.chatMessages.any(
            (message) =>
                message.text.contains('单机智能体已切换到') ||
                message.text.contains('Single Agent is using'),
          ),
          isFalse,
        );
        expect(
          controller.chatMessages.any(
            (message) => message.toolName == 'OpenCode',
          ),
          isFalse,
        );
      },
    );

    test(
      'AppController resolves auto Single Agent provider from the current bridge capabilities order',
      () async {
        final tempDirectory = await createTempDirectoryInternal(
          'xworkmate-single-agent-auto-bridge-order-',
        );
        final store = createStoreFromTempDirectoryInternal(tempDirectory);
        final client = FakeGoTaskServiceClientInternal(
          capabilities: ExternalCodeAgentAcpCapabilities(
            singleAgent: true,
            multiAgent: false,
            providers: <SingleAgentProvider>{
              SingleAgentProvider.codex,
              SingleAgentProvider.opencode,
            },
            raw: <String, dynamic>{},
          ),
          result: const GoTaskServiceResult(
            success: true,
            message: 'AUTO_PROVIDER_REPLY',
            turnId: 'turn-auto-provider',
            raw: <String, dynamic>{},
            errorMessage: '',
            resolvedModel: 'codex-sonnet',
            route: GoTaskServiceRoute.externalAcpSingle,
          ),
        );
        final controller = AppController(
          store: store,
          runtimeCoordinator: RuntimeCoordinator(
            gateway: FakeGatewayRuntimeInternal(store: store),
            codex: FakeCodexRuntimeInternal(),
          ),
          goTaskServiceClient: client,
        );
        addTearDown(controller.dispose);
        await waitForInternal(() => !controller.initializing);

        await controller.saveSettings(
          controller.settings.copyWith(
            workspacePath: tempDirectory.path,
            multiAgent: controller.settings.multiAgent.copyWith(
              autoSync: false,
            ),
          ),
          refreshAfterSave: false,
        );
        await controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.singleAgent,
        );
        await controller.setSingleAgentProvider(SingleAgentProvider.auto);

        await controller.sendChatMessage(
          '请输出 AUTO_PROVIDER_REPLY',
          thinking: 'low',
        );

        expect(client.executeCalls, 1);
        expect(client.lastRequest?.provider, SingleAgentProvider.codex);
      },
    );

    test(
      'AppController syncs custom single-agent providers before execution',
      () async {
        final tempDirectory = await createTempDirectoryInternal(
          'xworkmate-single-agent-custom-provider-',
        );
        final store = createStoreFromTempDirectoryInternal(tempDirectory);
        const customProvider = SingleAgentProvider(
          providerId: 'custom-agent-1',
          label: 'Lab Agent',
          badge: 'LA',
        );
        final client = FakeGoTaskServiceClientInternal(
          capabilities: ExternalCodeAgentAcpCapabilities(
            singleAgent: true,
            multiAgent: false,
            providers: <SingleAgentProvider>{customProvider},
            raw: <String, dynamic>{},
          ),
          result: const GoTaskServiceResult(
            success: true,
            message: 'CUSTOM_PROVIDER_REPLY',
            turnId: 'turn-custom',
            raw: <String, dynamic>{},
            errorMessage: '',
            resolvedModel: '',
            route: GoTaskServiceRoute.externalAcpSingle,
          ),
        );
        final controller = await createAppControllerInternal(
          store: store,
          availableSingleAgentProvidersOverride: const <SingleAgentProvider>[
            customProvider,
          ],
          runtimeCoordinator: RuntimeCoordinator(
            gateway: FakeGatewayRuntimeInternal(store: store),
            codex: FakeCodexRuntimeInternal(),
          ),
          goTaskServiceClient: client,
        );
        await controller.saveSettings(
          controller.settings.copyWith(
            externalAcpEndpoints: normalizeExternalAcpEndpoints(
              profiles: const <ExternalAcpEndpointProfile>[
                ExternalAcpEndpointProfile(
                  providerKey: 'custom-agent-1',
                  label: 'Lab Agent',
                  badge: 'LA',
                  endpoint: 'ws://127.0.0.1:9101/acp',
                  authRef: '',
                  enabled: true,
                ),
              ],
            ),
            multiAgent: controller.settings.multiAgent.copyWith(
              autoSync: false,
            ),
          ),
          refreshAfterSave: false,
        );

        await controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.singleAgent,
        );
        await controller.setSingleAgentProvider(customProvider);

        await controller.sendChatMessage(
          '请输出 CUSTOM_PROVIDER_REPLY',
          thinking: 'low',
        );

        expect(client.syncProvidersCalls, greaterThanOrEqualTo(1));
        expect(client.executeCalls, 1);
        expect(client.lastRequest?.provider, customProvider);
        expect(
          client.syncedProvidersHistory.any(
            (batch) => batch.any(
              (provider) =>
                  provider.providerId == 'custom-agent-1' &&
                  provider.endpoint == 'ws://127.0.0.1:9101/acp',
            ),
          ),
          isTrue,
        );
      },
    );

    test(
      'AppController keeps persisted Single Agent bindings but reports them unavailable when the bridge stops advertising that provider',
      () async {
        final tempDirectory = await createTempDirectoryInternal(
          'xworkmate-single-agent-bridge-unavailable-provider-',
        );
        final store = createStoreFromTempDirectoryInternal(tempDirectory);
        final client = FakeGoTaskServiceClientInternal(
          capabilities: ExternalCodeAgentAcpCapabilities(
            singleAgent: true,
            multiAgent: false,
            providers: <SingleAgentProvider>{SingleAgentProvider.opencode},
            raw: <String, dynamic>{},
          ),
        );
        final controller = AppController(
          store: store,
          runtimeCoordinator: RuntimeCoordinator(
            gateway: FakeGatewayRuntimeInternal(store: store),
            codex: FakeCodexRuntimeInternal(),
          ),
          goTaskServiceClient: client,
        );
        addTearDown(controller.dispose);
        await waitForInternal(() => !controller.initializing);

        await controller.saveSettings(
          controller.settings.copyWith(
            workspacePath: tempDirectory.path,
            multiAgent: controller.settings.multiAgent.copyWith(
              autoSync: false,
            ),
          ),
          refreshAfterSave: false,
        );
        await controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.singleAgent,
        );
        await controller.setSingleAgentProvider(SingleAgentProvider.codex);

        expect(
          controller.currentSingleAgentProvider,
          SingleAgentProvider.codex,
        );

        await controller.sendChatMessage('你好', thinking: 'low');

        expect(client.capabilitiesCalls, greaterThanOrEqualTo(1));
        expect(client.executeCalls, 0);
        expect(
          controller.currentSingleAgentProvider,
          SingleAgentProvider.codex,
        );
        expect(
          controller.chatMessages.any(
            (message) =>
                message.role == 'assistant' &&
                (message.text.contains('当前 GoTaskService 不支持 Codex') ||
                    message.text.contains(
                      'GoTaskService does not currently support Codex',
                    )),
          ),
          isTrue,
        );
      },
    );

    test(
      'AppController treats automatic ACP provider selection as ready before the first routing resolution when any route is available',
      () async {
        final tempDirectory = await createTempDirectoryInternal(
          'xworkmate-auto-route-ready-',
        );
        final store = createStoreFromTempDirectoryInternal(tempDirectory);
        final client = FakeGoTaskServiceClientInternal(
          capabilities: ExternalCodeAgentAcpCapabilities(
            singleAgent: true,
            multiAgent: false,
            providers: <SingleAgentProvider>{SingleAgentProvider.opencode},
            raw: <String, dynamic>{},
          ),
        );
        final controller = await createAppControllerInternal(
          store: store,
          availableSingleAgentProvidersOverride: const <SingleAgentProvider>[
            SingleAgentProvider.opencode,
          ],
          runtimeCoordinator: RuntimeCoordinator(
            gateway: FakeGatewayRuntimeInternal(store: store),
            codex: FakeCodexRuntimeInternal(),
          ),
          goTaskServiceClient: client,
        );
        await controller.saveSettings(
          controller.settings.copyWith(
            multiAgent: controller.settings.multiAgent.copyWith(
              autoSync: false,
            ),
          ),
          refreshAfterSave: false,
        );
        await controller.setSingleAgentProvider(SingleAgentProvider.opencode);
        await controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.singleAgent,
        );

        expect(
          controller.currentAssistantConnectionState.executionTarget,
          AssistantExecutionTarget.singleAgent,
        );
        expect(controller.currentAssistantConnectionState.connected, isTrue);
        expect(controller.currentAssistantConnectionState.ready, isTrue);
        expect(
          controller.currentAssistantConnectionState.detailLabel,
          contains('OpenCode'),
        );
      },
    );

    test(
      'AppController shows Single Agent runtime status only when debug runtime is enabled',
      () async {
        final tempDirectory = await createTempDirectoryInternal(
          'xworkmate-single-agent-provider-debug-',
        );
        final store = createStoreFromTempDirectoryInternal(tempDirectory);
        final client = FakeGoTaskServiceClientInternal(
          capabilities: ExternalCodeAgentAcpCapabilities(
            singleAgent: true,
            multiAgent: false,
            providers: <SingleAgentProvider>{SingleAgentProvider.opencode},
            raw: <String, dynamic>{},
          ),
          result: const GoTaskServiceResult(
            success: true,
            message: 'CODEX_REPLY',
            turnId: 'turn-1',
            raw: <String, dynamic>{},
            errorMessage: '',
            resolvedModel: 'codex-sonnet',
            route: GoTaskServiceRoute.externalAcpSingle,
          ),
        );
        final controller = await createAppControllerInternal(
          store: store,
          availableSingleAgentProvidersOverride: const <SingleAgentProvider>[
            SingleAgentProvider.opencode,
          ],
          runtimeCoordinator: RuntimeCoordinator(
            gateway: FakeGatewayRuntimeInternal(store: store),
            codex: FakeCodexRuntimeInternal(),
          ),
          goTaskServiceClient: client,
        );

        await controller.saveSettings(
          controller.settings.copyWith(experimentalDebug: true),
          refreshAfterSave: false,
        );
        await controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.singleAgent,
        );
        await controller.setSingleAgentProvider(SingleAgentProvider.opencode);

        await controller.sendChatMessage('请输出 CODEX_REPLY', thinking: 'low');

        expect(
          controller.chatMessages.any(
            (message) =>
                message.toolName == 'OpenCode' &&
                (message.text.contains('单机智能体已切换到') ||
                    message.text.contains('Single Agent is using')),
          ),
          isTrue,
        );
      },
    );

    test(
      'AppController executes local single-agent threads from the bound workspace path',
      () async {
        final tempDirectory = await createTempDirectoryInternal(
          'xworkmate-single-agent-bound-workspace-',
        );
        final store = createStoreFromTempDirectoryInternal(tempDirectory);
        await store.initialize();
        await store.saveSettingsSnapshot(
          SettingsSnapshot.defaults().copyWith(
            workspacePath: tempDirectory.path,
          ),
        );
        final client = FakeGoTaskServiceClientInternal(
          capabilities: ExternalCodeAgentAcpCapabilities(
            singleAgent: true,
            multiAgent: false,
            providers: <SingleAgentProvider>{SingleAgentProvider.opencode},
            raw: <String, dynamic>{},
          ),
          result: const GoTaskServiceResult(
            success: true,
            message: 'WORKSPACE_OK',
            turnId: 'turn-1',
            raw: <String, dynamic>{},
            errorMessage: '',
            resolvedModel: 'codex-sonnet',
            route: GoTaskServiceRoute.externalAcpSingle,
          ),
        );
        final controller = await createAppControllerInternal(
          store: store,
          availableSingleAgentProvidersOverride: const <SingleAgentProvider>[
            SingleAgentProvider.opencode,
          ],
          runtimeCoordinator: RuntimeCoordinator(
            gateway: FakeGatewayRuntimeInternal(store: store),
            codex: FakeCodexRuntimeInternal(),
          ),
          goTaskServiceClient: client,
        );
        await controller.saveSettings(
          controller.settings.copyWith(
            multiAgent: controller.settings.multiAgent.copyWith(
              autoSync: false,
            ),
          ),
          refreshAfterSave: false,
        );

        await controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.singleAgent,
        );
        await controller.setSingleAgentProvider(SingleAgentProvider.opencode);

        final initialWorkspacePath = controller
            .assistantWorkspacePathForSession(controller.currentSessionKey);
        expect(initialWorkspacePath, isNotEmpty);

        await controller.sendChatMessage('请输出 WORKSPACE_OK', thinking: 'low');

        expect(client.executeCalls, 1);
        expect(client.lastRequest?.workingDirectory, initialWorkspacePath);
        expect(await Directory(initialWorkspacePath).exists(), isTrue);
        expect(
          controller.assistantWorkspacePathForSession(
            controller.currentSessionKey,
          ),
          initialWorkspacePath,
        );
      },
    );

    test(
      'AppController does not let prompt text override the bound workspace path during single-agent send',
      () async {
        final tempDirectory = await createTempDirectoryInternal(
          'xworkmate-single-agent-bound-workspace-text-',
        );
        final store = createStoreFromTempDirectoryInternal(tempDirectory);
        await store.initialize();
        await store.saveSettingsSnapshot(
          SettingsSnapshot.defaults().copyWith(
            multiAgent: SettingsSnapshot.defaults().multiAgent.copyWith(
              autoSync: false,
            ),
          ),
        );
        final client = FakeGoTaskServiceClientInternal(
          capabilities: ExternalCodeAgentAcpCapabilities(
            singleAgent: true,
            multiAgent: false,
            providers: <SingleAgentProvider>{SingleAgentProvider.opencode},
            raw: <String, dynamic>{},
          ),
          result: const GoTaskServiceResult(
            success: true,
            message: 'WORKSPACE_PLACEHOLDER_OK',
            turnId: 'turn-1',
            raw: <String, dynamic>{},
            errorMessage: '',
            resolvedModel: 'codex-sonnet',
            route: GoTaskServiceRoute.externalAcpSingle,
          ),
        );
        final controller = await createAppControllerInternal(
          store: store,
          availableSingleAgentProvidersOverride: const <SingleAgentProvider>[
            SingleAgentProvider.opencode,
          ],
          runtimeCoordinator: RuntimeCoordinator(
            gateway: FakeGatewayRuntimeInternal(store: store),
            codex: FakeCodexRuntimeInternal(),
          ),
          goTaskServiceClient: client,
        );

        await controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.singleAgent,
        );

        await controller.sendChatMessage(
          'Execution context:\n'
          '- target: single-agent\n'
          '- permission: full-access\n\n'
          '请输出 WORKSPACE_PLACEHOLDER_OK',
          thinking: 'low',
        );

        expect(client.executeCalls, 1);
        final boundWorkspacePath = controller.assistantWorkspacePathForSession(
          controller.currentSessionKey,
        );
        expect(boundWorkspacePath, isNotEmpty);
        expect(client.lastRequest?.workingDirectory, boundWorkspacePath);
        expect(
          controller.assistantWorkspacePathForSession(
            controller.currentSessionKey,
          ),
          boundWorkspacePath,
        );
      },
    );

    test(
      'AppController returns an ACP-only error when no provider is available',
      () async {
        final tempDirectory = await createTempDirectoryInternal(
          'xworkmate-single-agent-acp-unavailable-',
        );
        final server = await FakeAiGatewayServerInternal.start(
          responseMode: AiGatewayResponseModeInternal.json,
        );
        addTearDown(() async {
          await server.close();
        });

        final store = createStoreFromTempDirectoryInternal(tempDirectory);
        final client = FallbackOnlyGoTaskServiceClientInternal();
        final controller = await createAppControllerInternal(
          store: store,
          availableSingleAgentProvidersOverride: const <SingleAgentProvider>[],
          runtimeCoordinator: RuntimeCoordinator(
            gateway: FakeGatewayRuntimeInternal(store: store),
            codex: FakeCodexRuntimeInternal(),
          ),
          goTaskServiceClient: client,
        );

        await controller.settingsController.saveAiGatewayApiKey('live-key');
        await controller.saveSettings(
          controller.settings.copyWith(
            aiGateway: controller.settings.aiGateway.copyWith(
              baseUrl: server.baseUrl,
              availableModels: const <String>['moonshotai/kimi-k2.5'],
              selectedModels: const <String>['moonshotai/kimi-k2.5'],
            ),
            defaultModel: 'moonshotai/kimi-k2.5',
          ),
          refreshAfterSave: false,
        );
        await controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.singleAgent,
        );
        await controller.setSingleAgentProvider(SingleAgentProvider.opencode);

        await controller.sendChatMessage('你好', thinking: 'low');

        expect(client.capabilitiesCalls, greaterThanOrEqualTo(1));
        expect(client.executeCalls, 0);
        expect(server.requestCount, 0);
        expect(
          controller.chatMessages.any(
            (message) =>
                message.role == 'assistant' &&
                message.text.contains('当前没有可用的 Bridge Provider'),
          ),
          isTrue,
        );
      },
    );

    test(
      'AppController auto-binds a thread workspace before reporting ACP unavailability',
      () async {
        final tempDirectory = await createTempDirectoryInternal(
          'xworkmate-single-agent-acp-unavailable-missing-workspace-',
        );
        final server = await FakeAiGatewayServerInternal.start(
          responseMode: AiGatewayResponseModeInternal.json,
        );
        addTearDown(() async {
          await server.close();
        });

        final store = createStoreFromTempDirectoryInternal(tempDirectory);
        final client = FallbackOnlyGoTaskServiceClientInternal();
        final controller = await createAppControllerInternal(
          store: store,
          availableSingleAgentProvidersOverride: const <SingleAgentProvider>[],
          runtimeCoordinator: RuntimeCoordinator(
            gateway: FakeGatewayRuntimeInternal(store: store),
            codex: FakeCodexRuntimeInternal(),
          ),
          goTaskServiceClient: client,
        );

        await controller.settingsController.saveAiGatewayApiKey('live-key');
        await controller.saveSettings(
          controller.settings.copyWith(
            workspacePath: tempDirectory.path,
            aiGateway: controller.settings.aiGateway.copyWith(
              baseUrl: server.baseUrl,
              availableModels: const <String>['moonshotai/kimi-k2.5'],
              selectedModels: const <String>['moonshotai/kimi-k2.5'],
            ),
            defaultModel: 'moonshotai/kimi-k2.5',
          ),
          refreshAfterSave: false,
        );
        await controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.singleAgent,
        );
        await controller.setSingleAgentProvider(SingleAgentProvider.opencode);

        await controller.sendChatMessage('你好', thinking: 'low');

        final workspacePath = controller.assistantWorkspacePathForSession(
          controller.currentSessionKey,
        );
        expect(client.capabilitiesCalls, greaterThanOrEqualTo(1));
        expect(client.executeCalls, 0);
        expect(server.requestCount, 0);
        expect(workspacePath, isNotEmpty);
        expect(workspacePath, contains('.xworkmate/threads/'));
        expect(
          controller.chatMessages.any(
            (message) =>
                message.role == 'assistant' &&
                message.text.contains('当前没有可用的 Bridge Provider'),
          ),
          isTrue,
        );
      },
    );
  });

  group('Single Agent workspace resolution', () {
    test(
      'AppController uses the recorded thread workspace for Single Agent runs',
      () async {
        final tempDirectory = await createTempDirectoryInternal(
          'xworkmate-single-agent-thread-cwd-',
        );
        final defaultWorkspace = Directory(
          '${tempDirectory.path}/default-workspace',
        );
        final threadWorkspace = Directory(
          '${tempDirectory.path}/thread-workspace',
        );
        await defaultWorkspace.create(recursive: true);
        await threadWorkspace.create(recursive: true);

        final store = createStoreFromTempDirectoryInternal(tempDirectory);
        await store.initialize();
        await store.saveSettingsSnapshot(
          SettingsSnapshot.defaults().copyWith(
            workspacePath: defaultWorkspace.path,
            assistantExecutionTarget: AssistantExecutionTarget.singleAgent,
          ),
        );
        await store.saveTaskThreads(<TaskThread>[
          TaskThread(
            threadId: 'main',
            workspaceBinding: WorkspaceBinding(
              workspaceId: 'main',
              workspaceKind: WorkspaceKind.localFs,
              workspacePath: threadWorkspace.path,
              displayPath: threadWorkspace.path,
              writable: true,
            ),
            messages: const <GatewayChatMessage>[],
            updatedAtMs: 1,
            title: 'Main',
            archived: false,
            executionBinding: const ExecutionBinding(
              executionMode: ThreadExecutionMode.localAgent,
              executorId: 'auto',
              providerId: 'auto',
              endpointId: '',
            ),
            messageViewMode: AssistantMessageViewMode.rendered,
          ),
        ]);

        final client = FakeGoTaskServiceClientInternal(
          capabilities: ExternalCodeAgentAcpCapabilities(
            singleAgent: true,
            multiAgent: false,
            providers: <SingleAgentProvider>{SingleAgentProvider.opencode},
            raw: <String, dynamic>{},
          ),
          result: const GoTaskServiceResult(
            success: true,
            message: 'THREAD_OK',
            turnId: 'turn-1',
            raw: <String, dynamic>{},
            errorMessage: '',
            resolvedModel: '',
            route: GoTaskServiceRoute.externalAcpSingle,
          ),
        );
        final controller = await createAppControllerInternal(
          store: store,
          availableSingleAgentProvidersOverride: const <SingleAgentProvider>[
            SingleAgentProvider.opencode,
          ],
          runtimeCoordinator: RuntimeCoordinator(
            gateway: FakeGatewayRuntimeInternal(store: store),
            codex: FakeCodexRuntimeInternal(),
          ),
          goTaskServiceClient: client,
        );

        await controller.sendChatMessage('检查当前线程目录', thinking: 'low');

        expect(client.executeCalls, 1);
        expect(client.lastRequest?.workingDirectory, threadWorkspace.path);
        expect(
          controller.assistantWorkspacePathForSession('main'),
          threadWorkspace.path,
        );
      },
    );

    test(
      'AppController uses an isolated workspace for draft Single Agent threads',
      () async {
        final tempDirectory = await createTempDirectoryInternal(
          'xworkmate-single-agent-isolated-thread-cwd-',
        );
        final defaultWorkspace = Directory(
          '${tempDirectory.path}/default-workspace',
        );
        await defaultWorkspace.create(recursive: true);

        final store = createStoreFromTempDirectoryInternal(tempDirectory);
        await store.initialize();
        await store.saveSettingsSnapshot(
          SettingsSnapshot.defaults().copyWith(
            workspacePath: defaultWorkspace.path,
            assistantExecutionTarget: AssistantExecutionTarget.singleAgent,
          ),
        );

        final client = FakeGoTaskServiceClientInternal(
          capabilities: ExternalCodeAgentAcpCapabilities(
            singleAgent: true,
            multiAgent: false,
            providers: <SingleAgentProvider>{SingleAgentProvider.opencode},
            raw: <String, dynamic>{},
          ),
          result: const GoTaskServiceResult(
            success: true,
            message: 'THREAD_OK',
            turnId: 'turn-1',
            raw: <String, dynamic>{},
            errorMessage: '',
            resolvedModel: '',
            route: GoTaskServiceRoute.externalAcpSingle,
          ),
        );
        final controller = await createAppControllerInternal(
          store: store,
          availableSingleAgentProvidersOverride: const <SingleAgentProvider>[
            SingleAgentProvider.opencode,
          ],
          runtimeCoordinator: RuntimeCoordinator(
            gateway: FakeGatewayRuntimeInternal(store: store),
            codex: FakeCodexRuntimeInternal(),
          ),
          goTaskServiceClient: client,
        );

        controller.initializeAssistantThreadContext(
          'draft:artifact-thread',
          title: 'Artifact Thread',
          executionTarget: AssistantExecutionTarget.singleAgent,
        );
        await controller.switchSession('draft:artifact-thread');
        await controller.sendChatMessage('检查当前线程目录', thinking: 'low');

        const expectedWorkspaceSuffix =
            '.xworkmate/threads/draft-artifact-thread';
        expect(client.executeCalls, 1);
        expect(
          client.lastRequest?.workingDirectory,
          '${defaultWorkspace.path}/$expectedWorkspaceSuffix',
        );
        expect(
          controller.assistantWorkspacePathForSession('draft:artifact-thread'),
          '${defaultWorkspace.path}/$expectedWorkspaceSuffix',
        );
        expect(
          Directory(
            '${defaultWorkspace.path}/$expectedWorkspaceSuffix',
          ).existsSync(),
          isTrue,
        );
      },
    );

    test(
      'AppController keeps local Single Agent threads bound to the local workspace while recording remote metadata',
      () async {
        final tempDirectory = await createTempDirectoryInternal(
          'xworkmate-single-agent-remote-thread-cwd-',
        );
        final defaultWorkspace = Directory(
          '${tempDirectory.path}/default-workspace',
        );
        await defaultWorkspace.create(recursive: true);

        final store = createStoreFromTempDirectoryInternal(tempDirectory);
        await store.initialize();
        await store.saveSettingsSnapshot(
          SettingsSnapshot.defaults().copyWith(
            workspacePath: defaultWorkspace.path,
            assistantExecutionTarget: AssistantExecutionTarget.singleAgent,
          ),
        );

        final client = FakeGoTaskServiceClientInternal(
          capabilities: ExternalCodeAgentAcpCapabilities(
            singleAgent: true,
            multiAgent: false,
            providers: <SingleAgentProvider>{SingleAgentProvider.opencode},
            raw: <String, dynamic>{},
          ),
          result: const GoTaskServiceResult(
            success: true,
            message: 'THREAD_OK',
            turnId: 'turn-1',
            raw: <String, dynamic>{
              'resolvedWorkingDirectory':
                  '/opt/data/.xworkmate/threads/draft-remote-thread',
              'resolvedWorkspaceRefKind': 'localPath',
            },
            errorMessage: '',
            resolvedModel: '',
            route: GoTaskServiceRoute.externalAcpSingle,
          ),
        );
        final controller = await createAppControllerInternal(
          store: store,
          availableSingleAgentProvidersOverride: const <SingleAgentProvider>[
            SingleAgentProvider.opencode,
          ],
          runtimeCoordinator: RuntimeCoordinator(
            gateway: FakeGatewayRuntimeInternal(store: store),
            codex: FakeCodexRuntimeInternal(),
          ),
          goTaskServiceClient: client,
        );

        controller.initializeAssistantThreadContext(
          'draft:remote-thread',
          title: 'Remote Thread',
          executionTarget: AssistantExecutionTarget.singleAgent,
        );
        await controller.switchSession('draft:remote-thread');

        await controller.sendChatMessage('第一次运行', thinking: 'low');
        final localThreadDir =
            '${defaultWorkspace.path}/.xworkmate/threads/draft-remote-thread';
        const remoteThreadDir =
            '/opt/data/.xworkmate/threads/draft-remote-thread';
        expect(
          client.requests.first.workingDirectory,
          localThreadDir,
        );
        expect(
          controller.assistantWorkspacePathForSession('draft:remote-thread'),
          localThreadDir,
        );
        expect(
          controller.assistantWorkspaceKindForSession('draft:remote-thread'),
          WorkspaceRefKind.localPath,
        );
        final thread = controller.requireTaskThreadForSessionInternal(
          'draft:remote-thread',
        );
        expect(thread.lastRemoteWorkingDirectory, remoteThreadDir);
        expect(thread.lastRemoteWorkspaceRefKind, WorkspaceRefKind.localPath);

        await controller.sendChatMessage('第二次运行', thinking: 'low');
        expect(
          client.requests.last.workingDirectory,
          localThreadDir,
        );
        expect(client.requests.last.remoteWorkingDirectoryHint, remoteThreadDir);
      },
    );

    test(
      'AppController keeps remote Single Agent threads on the local workspace and forwards the remote directory as a hint',
      () async {
        final tempDirectory = await createTempDirectoryInternal(
          'xworkmate-single-agent-remote-rebind-cwd-',
        );
        final defaultWorkspace = Directory(
          '${tempDirectory.path}/default-workspace',
        );
        await defaultWorkspace.create(recursive: true);

        final store = createStoreFromTempDirectoryInternal(tempDirectory);
        await store.initialize();
        await store.saveSettingsSnapshot(
          SettingsSnapshot.defaults().copyWith(
            workspacePath: defaultWorkspace.path,
            assistantExecutionTarget: AssistantExecutionTarget.singleAgent,
            externalAcpEndpoints: normalizeExternalAcpEndpoints(
              profiles: <ExternalAcpEndpointProfile>[
                ExternalAcpEndpointProfile.defaultsForProvider(
                  SingleAgentProvider.opencode,
                ).copyWith(
                  enabled: true,
                  endpoint: 'https://remote.example.com/acp',
                ),
              ],
            ),
          ),
        );

        final client = FakeGoTaskServiceClientInternal(
          capabilities: ExternalCodeAgentAcpCapabilities(
            singleAgent: true,
            multiAgent: false,
            providers: <SingleAgentProvider>{SingleAgentProvider.opencode},
            raw: <String, dynamic>{},
          ),
          result: const GoTaskServiceResult(
            success: true,
            message: 'THREAD_OK',
            turnId: 'turn-1',
            raw: <String, dynamic>{
              'resolvedWorkingDirectory': '/remote/threads/task-42',
              'resolvedWorkspaceRefKind': 'remotePath',
            },
            errorMessage: '',
            resolvedModel: '',
            route: GoTaskServiceRoute.externalAcpSingle,
          ),
        );
        final controller = await createAppControllerInternal(
          store: store,
          availableSingleAgentProvidersOverride: const <SingleAgentProvider>[
            SingleAgentProvider.opencode,
          ],
          runtimeCoordinator: RuntimeCoordinator(
            gateway: FakeGatewayRuntimeInternal(store: store),
            codex: FakeCodexRuntimeInternal(),
          ),
          goTaskServiceClient: client,
        );

        await controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.singleAgent,
        );
        await controller.setSingleAgentProvider(SingleAgentProvider.opencode);
        controller.initializeAssistantThreadContext(
          'draft:remote-thread',
          title: 'Remote Thread',
          executionTarget: AssistantExecutionTarget.singleAgent,
        );
        await controller.switchSession('draft:remote-thread');

        await controller.sendChatMessage('第一次运行', thinking: 'low');
        final localThreadDir =
            '${defaultWorkspace.path}/.xworkmate/threads/draft-remote-thread';
        expect(
          client.requests.first.workingDirectory,
          localThreadDir,
        );
        expect(
          controller.assistantWorkspacePathForSession('draft:remote-thread'),
          localThreadDir,
        );
        expect(
          controller.assistantWorkspaceKindForSession('draft:remote-thread'),
          WorkspaceRefKind.localPath,
        );
        final thread = controller.requireTaskThreadForSessionInternal(
          'draft:remote-thread',
        );
        expect(thread.lastRemoteWorkingDirectory, '/remote/threads/task-42');
        expect(thread.lastRemoteWorkspaceRefKind, WorkspaceRefKind.remotePath);

        await controller.sendChatMessage('第二次运行', thinking: 'low');
        expect(
          client.requests.last.workingDirectory,
          localThreadDir,
        );
        expect(
          client.requests.last.remoteWorkingDirectoryHint,
          '/remote/threads/task-42',
        );
      },
    );

    test(
      'AppController writes returned Single Agent artifacts into the local workspace and versions name conflicts',
      () async {
        final tempDirectory = await createTempDirectoryInternal(
          'xworkmate-single-agent-artifact-sync-',
        );
        final defaultWorkspace = Directory(
          '${tempDirectory.path}/default-workspace',
        );
        await defaultWorkspace.create(recursive: true);

        final store = createStoreFromTempDirectoryInternal(tempDirectory);
        await store.initialize();
        await store.saveSettingsSnapshot(
          SettingsSnapshot.defaults().copyWith(
            workspacePath: defaultWorkspace.path,
            assistantExecutionTarget: AssistantExecutionTarget.singleAgent,
          ),
        );

        final artifactPayload = base64Encode(utf8.encode('new report body'));
        final client = FakeGoTaskServiceClientInternal(
          capabilities: ExternalCodeAgentAcpCapabilities(
            singleAgent: true,
            multiAgent: false,
            providers: <SingleAgentProvider>{SingleAgentProvider.opencode},
            raw: <String, dynamic>{},
          ),
          result: GoTaskServiceResult(
            success: true,
            message: 'ARTIFACT_OK',
            turnId: 'turn-artifact-1',
            raw: <String, dynamic>{
              'resolvedWorkingDirectory': '/remote/threads/artifact-thread',
              'resolvedWorkspaceRefKind': 'remotePath',
              'artifacts': <Map<String, dynamic>>[
                <String, dynamic>{
                  'relativePath': 'outputs/report.docx',
                  'label': 'Report',
                  'contentType':
                      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
                  'encoding': 'base64',
                  'content': artifactPayload,
                },
              ],
            },
            errorMessage: '',
            resolvedModel: '',
            route: GoTaskServiceRoute.externalAcpSingle,
          ),
        );
        final controller = await createAppControllerInternal(
          store: store,
          availableSingleAgentProvidersOverride: const <SingleAgentProvider>[
            SingleAgentProvider.opencode,
          ],
          runtimeCoordinator: RuntimeCoordinator(
            gateway: FakeGatewayRuntimeInternal(store: store),
            codex: FakeCodexRuntimeInternal(),
          ),
          goTaskServiceClient: client,
        );

        controller.initializeAssistantThreadContext(
          'draft:artifact-thread',
          title: 'Artifact Thread',
          executionTarget: AssistantExecutionTarget.singleAgent,
        );
        await controller.switchSession('draft:artifact-thread');

        final localThreadDir = Directory(
          '${defaultWorkspace.path}/.xworkmate/threads/draft-artifact-thread',
        );
        await localThreadDir.create(recursive: true);
        final existingArtifact = File('${localThreadDir.path}/outputs/report.docx');
        await existingArtifact.parent.create(recursive: true);
        await existingArtifact.writeAsString('old report body');

        await controller.sendChatMessage('生成文档', thinking: 'low');

        final versionedArtifact = File(
          '${localThreadDir.path}/outputs/report.v2.docx',
        );
        expect(existingArtifact.existsSync(), isTrue);
        expect(versionedArtifact.existsSync(), isTrue);
        expect(await versionedArtifact.readAsString(), 'new report body');
        expect(
          controller.assistantWorkspacePathForSession('draft:artifact-thread'),
          localThreadDir.path,
        );
        expect(
          controller.assistantWorkspaceKindForSession('draft:artifact-thread'),
          WorkspaceRefKind.localPath,
        );
        final thread = controller.requireTaskThreadForSessionInternal(
          'draft:artifact-thread',
        );
        expect(
          thread.lastRemoteWorkingDirectory,
          '/remote/threads/artifact-thread',
        );
        expect(thread.lastRemoteWorkspaceRefKind, WorkspaceRefKind.remotePath);
        expect(thread.lastArtifactSyncStatus, 'synced');
        expect(thread.lastArtifactSyncAtMs, isNotNull);
      },
    );

    test(
      'AppController keeps local Codex-style working directories for remote thread refs',
      () async {
        final tempDirectory = await createTempDirectoryInternal(
          'xworkmate-single-agent-local-codex-remote-ref-',
        );
        final defaultWorkspace = Directory(
          '${tempDirectory.path}/default-workspace',
        );
        await defaultWorkspace.create(recursive: true);

        final store = createStoreFromTempDirectoryInternal(tempDirectory);
        await store.initialize();
        await store.saveSettingsSnapshot(
          SettingsSnapshot.defaults().copyWith(
            workspacePath: defaultWorkspace.path,
            assistantExecutionTarget: AssistantExecutionTarget.singleAgent,
          ),
        );

        final client = FakeGoTaskServiceClientInternal(
          capabilities: ExternalCodeAgentAcpCapabilities(
            singleAgent: true,
            multiAgent: false,
            providers: <SingleAgentProvider>{SingleAgentProvider.codex},
            raw: <String, dynamic>{},
          ),
          result: const GoTaskServiceResult(
            success: true,
            message: 'THREAD_OK',
            turnId: 'turn-1',
            raw: <String, dynamic>{
              'resolvedWorkingDirectory':
                  '/owners/local/user/example/threads/draft:remote-thread',
              'resolvedWorkspaceRefKind': 'remotePath',
            },
            errorMessage: '',
            resolvedModel: '',
            route: GoTaskServiceRoute.externalAcpSingle,
          ),
        );
        final controller = await createAppControllerInternal(
          store: store,
          availableSingleAgentProvidersOverride: const <SingleAgentProvider>[
            SingleAgentProvider.codex,
          ],
          runtimeCoordinator: RuntimeCoordinator(
            gateway: FakeGatewayRuntimeInternal(store: store),
            codex: FakeCodexRuntimeInternal(),
          ),
          goTaskServiceClient: client,
        );

        await controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.singleAgent,
        );
        await controller.setSingleAgentProvider(SingleAgentProvider.codex);
        controller.initializeAssistantThreadContext(
          'draft:remote-thread',
          title: 'Remote Thread',
          executionTarget: AssistantExecutionTarget.singleAgent,
        );
        await controller.switchSession('draft:remote-thread');

        await controller.sendChatMessage('第一次运行', thinking: 'low');
        final expectedLocalThreadDir =
            '${defaultWorkspace.path}/.xworkmate/threads/draft-remote-thread';
        expect(client.requests.first.workingDirectory, expectedLocalThreadDir);

        await controller.sendChatMessage('第二次运行', thinking: 'low');
        expect(client.requests.last.workingDirectory, expectedLocalThreadDir);
      },
    );
  });
}
