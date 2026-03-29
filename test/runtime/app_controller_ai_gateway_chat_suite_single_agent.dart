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
import 'package:xworkmate/runtime/go_agent_core_client.dart';
import 'package:xworkmate/runtime/runtime_coordinator.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';
import 'app_controller_ai_gateway_chat_suite_core.dart';
import 'app_controller_ai_gateway_chat_suite_chat.dart';
import 'app_controller_ai_gateway_chat_suite_fakes.dart';
import 'app_controller_ai_gateway_chat_suite_fixtures.dart';

void registerAppControllerAiGatewayChatSuiteSingleAgentTestsInternal() {
  group('Single Agent provider resolution', () {
    test(
      'AppController uses the selected Single Agent provider before AI Chat fallback',
      () async {
        final tempDirectory = await createTempDirectoryInternal(
          'xworkmate-single-agent-provider-',
        );
        final store = createStoreFromTempDirectoryInternal(tempDirectory);
        final client = FakeGoAgentCoreClientInternal(
          capabilities: GoAgentCoreCapabilities(
            singleAgent: true,
            multiAgent: false,
            providers: <SingleAgentProvider>{SingleAgentProvider.opencode},
            raw: <String, dynamic>{},
          ),
          result: const GoAgentCoreRunResult(
            success: true,
            message: 'CODEX_REPLY',
            turnId: 'turn-1',
            raw: <String, dynamic>{},
            errorMessage: '',
            resolvedModel: 'codex-sonnet',
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
          goAgentCoreClient: client,
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
      'AppController shows Single Agent runtime status only when debug runtime is enabled',
      () async {
        final tempDirectory = await createTempDirectoryInternal(
          'xworkmate-single-agent-provider-debug-',
        );
        final store = createStoreFromTempDirectoryInternal(tempDirectory);
        final client = FakeGoAgentCoreClientInternal(
          capabilities: GoAgentCoreCapabilities(
            singleAgent: true,
            multiAgent: false,
            providers: <SingleAgentProvider>{SingleAgentProvider.opencode},
            raw: <String, dynamic>{},
          ),
          result: const GoAgentCoreRunResult(
            success: true,
            message: 'CODEX_REPLY',
            turnId: 'turn-1',
            raw: <String, dynamic>{},
            errorMessage: '',
            resolvedModel: 'codex-sonnet',
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
          goAgentCoreClient: client,
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
      'AppController bootstraps the current thread workspace from execution context before single-agent send',
      () async {
        final tempDirectory = await createTempDirectoryInternal(
          'xworkmate-single-agent-workspace-bootstrap-',
        );
        final workspaceRoot = Directory('${tempDirectory.path}/thread-workspace');
        final store = createStoreFromTempDirectoryInternal(tempDirectory);
        await store.initialize();
        await store.saveSettingsSnapshot(
          SettingsSnapshot.defaults().copyWith(workspacePath: ''),
        );
        final client = FakeGoAgentCoreClientInternal(
          capabilities: GoAgentCoreCapabilities(
            singleAgent: true,
            multiAgent: false,
            providers: <SingleAgentProvider>{SingleAgentProvider.opencode},
            raw: <String, dynamic>{},
          ),
          result: const GoAgentCoreRunResult(
            success: true,
            message: 'WORKSPACE_OK',
            turnId: 'turn-1',
            raw: <String, dynamic>{},
            errorMessage: '',
            resolvedModel: 'codex-sonnet',
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
          goAgentCoreClient: client,
        );

        await controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.singleAgent,
        );
        await controller.setSingleAgentProvider(SingleAgentProvider.opencode);

        final initialWorkspacePath = controller.assistantWorkspacePathForSession(
          controller.currentSessionKey,
        );
        expect(initialWorkspacePath, isNot(workspaceRoot.path));

        await controller.sendChatMessage(
          'Execution context:\n'
          '- target: single-agent\n'
          '- workspace_root: ${workspaceRoot.path}\n'
          '- permission: full-access\n\n'
          '请输出 WORKSPACE_OK',
          thinking: 'low',
        );

        expect(client.executeCalls, 1);
        expect(client.lastRequest?.workingDirectory, workspaceRoot.path);
        expect(await workspaceRoot.exists(), isTrue);
        expect(
          controller.assistantWorkspacePathForSession(
            controller.currentSessionKey,
          ),
          workspaceRoot.path,
        );
      },
    );

    test(
      'AppController keeps the thread provider strict when another external CLI is available',
      () async {
        final tempDirectory = await createTempDirectoryInternal(
          'xworkmate-single-agent-strict-provider-',
        );
        final server = await FakeAiGatewayServerInternal.start(
          responseMode: AiGatewayResponseModeInternal.json,
        );
        addTearDown(() async {
          await server.close();
        });

        final store = createStoreFromTempDirectoryInternal(tempDirectory);
        final client = FallbackOnlyGoAgentCoreClientInternal();
        final controller = await createAppControllerInternal(
          store: store,
          availableSingleAgentProvidersOverride: const <SingleAgentProvider>[
            SingleAgentProvider.claude,
          ],
          runtimeCoordinator: RuntimeCoordinator(
            gateway: FakeGatewayRuntimeInternal(store: store),
            codex: FakeCodexRuntimeInternal(),
          ),
          goAgentCoreClient: client,
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
            multiAgent: controller.settings.multiAgent.copyWith(
              autoSync: false,
              mountTargets: withAvailableMountTargetsInternal(
                controller.settings.multiAgent.mountTargets,
                const <String>['claude'],
              ),
            ),
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
        expect(controller.currentAssistantConnectionState.connected, isFalse);
        expect(
          controller.chatMessages.any(
            (message) => message.text.contains('可切到 Auto'),
          ),
          isTrue,
        );
      },
    );

    test(
      'AppController falls back to AI Chat when no external CLI is available',
      () async {
        final tempDirectory = await createTempDirectoryInternal(
          'xworkmate-single-agent-fallback-',
        );
        final server = await FakeAiGatewayServerInternal.start(
          responseMode: AiGatewayResponseModeInternal.json,
        );
        addTearDown(() async {
          await server.close();
        });

        final store = createStoreFromTempDirectoryInternal(tempDirectory);
        final client = FallbackOnlyGoAgentCoreClientInternal();
        final controller = await createAppControllerInternal(
          store: store,
          availableSingleAgentProvidersOverride: const <SingleAgentProvider>[],
          runtimeCoordinator: RuntimeCoordinator(
            gateway: FakeGatewayRuntimeInternal(store: store),
            codex: FakeCodexRuntimeInternal(),
          ),
          goAgentCoreClient: client,
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
        expect(server.requestCount, 1);
        expect(
          controller.chatMessages.any(
            (message) => message.text.contains('Codex CLI is unavailable'),
          ),
          isFalse,
        );
        expect(
          controller.chatMessages.any(
            (message) => message.toolName == 'AI Chat fallback',
          ),
          isFalse,
        );
        expect(
          controller.chatMessages.any(
            (message) =>
                message.role == 'assistant' && message.text == 'FIRST_REPLY',
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
            sessionKey: 'main',
            messages: const <GatewayChatMessage>[],
            updatedAtMs: 1,
            title: 'Main',
            archived: false,
            executionTarget: AssistantExecutionTarget.singleAgent,
            messageViewMode: AssistantMessageViewMode.rendered,
            workspaceRef: threadWorkspace.path,
            workspaceRefKind: WorkspaceRefKind.localPath,
          ),
        ]);

        final client = FakeGoAgentCoreClientInternal(
          capabilities: GoAgentCoreCapabilities(
            singleAgent: true,
            multiAgent: false,
            providers: <SingleAgentProvider>{SingleAgentProvider.opencode},
            raw: <String, dynamic>{},
          ),
          result: const GoAgentCoreRunResult(
            success: true,
            message: 'THREAD_OK',
            turnId: 'turn-1',
            raw: <String, dynamic>{},
            errorMessage: '',
            resolvedModel: '',
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
          goAgentCoreClient: client,
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

        final client = FakeGoAgentCoreClientInternal(
          capabilities: GoAgentCoreCapabilities(
            singleAgent: true,
            multiAgent: false,
            providers: <SingleAgentProvider>{SingleAgentProvider.opencode},
            raw: <String, dynamic>{},
          ),
          result: const GoAgentCoreRunResult(
            success: true,
            message: 'THREAD_OK',
            turnId: 'turn-1',
            raw: <String, dynamic>{},
            errorMessage: '',
            resolvedModel: '',
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
          goAgentCoreClient: client,
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
      'AppController keeps isolated thread workspace even when runner reports another directory',
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

        final client = FakeGoAgentCoreClientInternal(
          capabilities: GoAgentCoreCapabilities(
            singleAgent: true,
            multiAgent: false,
            providers: <SingleAgentProvider>{SingleAgentProvider.opencode},
            raw: <String, dynamic>{},
          ),
          result: const GoAgentCoreRunResult(
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
          goAgentCoreClient: client,
        );

        controller.initializeAssistantThreadContext(
          'draft:remote-thread',
          title: 'Remote Thread',
          executionTarget: AssistantExecutionTarget.singleAgent,
        );
        await controller.switchSession('draft:remote-thread');

        await controller.sendChatMessage('第一次运行', thinking: 'low');
        expect(
          client.requests.first.workingDirectory,
          '${defaultWorkspace.path}/.xworkmate/threads/draft-remote-thread',
        );
        expect(
          controller.assistantWorkspacePathForSession('draft:remote-thread'),
          '${defaultWorkspace.path}/.xworkmate/threads/draft-remote-thread',
        );
        expect(
          controller.assistantWorkspaceKindForSession('draft:remote-thread'),
          WorkspaceRefKind.localPath,
        );

        await controller.sendChatMessage('第二次运行', thinking: 'low');
        expect(
          client.requests.last.workingDirectory,
          '${defaultWorkspace.path}/.xworkmate/threads/draft-remote-thread',
        );
      },
    );

    test(
      'AppController rebinds remote Single Agent threads to the resolved thread directory',
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

        final client = FakeGoAgentCoreClientInternal(
          capabilities: GoAgentCoreCapabilities(
            singleAgent: true,
            multiAgent: false,
            providers: <SingleAgentProvider>{SingleAgentProvider.opencode},
            raw: <String, dynamic>{},
          ),
          result: const GoAgentCoreRunResult(
            success: true,
            message: 'THREAD_OK',
            turnId: 'turn-1',
            raw: <String, dynamic>{
              'resolvedWorkingDirectory': '/remote/threads/task-42',
              'resolvedWorkspaceRefKind': 'remotePath',
            },
            errorMessage: '',
            resolvedModel: '',
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
          goAgentCoreClient: client,
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
        expect(
          client.requests.first.workingDirectory,
          '${defaultWorkspace.path}/.xworkmate/threads/draft-remote-thread',
        );
        expect(
          controller.assistantWorkspacePathForSession('draft:remote-thread'),
          '/remote/threads/task-42',
        );
        expect(
          controller.assistantWorkspaceKindForSession('draft:remote-thread'),
          WorkspaceRefKind.remotePath,
        );

        await controller.sendChatMessage('第二次运行', thinking: 'low');
        expect(
          client.requests.last.workingDirectory,
          '/remote/threads/task-42',
        );
      },
    );
  });
}
