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
import 'package:xworkmate/runtime/single_agent_runner.dart';
import 'app_controller_ai_gateway_chat_suite_core.dart';
import 'app_controller_ai_gateway_chat_suite_single_agent.dart';
import 'app_controller_ai_gateway_chat_suite_fakes.dart';
import 'app_controller_ai_gateway_chat_suite_fixtures.dart';

void registerAppControllerAiGatewayChatSuiteChatTestsInternal() {
  group('AI Gateway chat streaming', () {
    test(
      'AppController streams and restores persistent Single Agent conversation turns',
      () async {
        final tempDirectory = await createTempDirectoryInternal(
          'xworkmate-ai-gateway-chat-',
        );
        final server = await FakeAiGatewayServerInternal.start(
          responseMode: AiGatewayResponseModeInternal.sse,
        );
        addTearDown(() async {
          await server.close();
        });

        final store = createStoreFromTempDirectoryInternal(tempDirectory);
        final gateway = FakeGatewayRuntimeInternal(store: store);
        final controller = await createAppControllerInternal(
          store: store,
          availableSingleAgentProvidersOverride: const <SingleAgentProvider>[],
          runtimeCoordinator: RuntimeCoordinator(
            gateway: gateway,
            codex: FakeCodexRuntimeInternal(),
          ),
          singleAgentRunner: FallbackOnlySingleAgentRunnerInternal(),
        );

        await controller.settingsController.saveAiGatewayApiKey('live-key');
        await controller.saveSettings(
          controller.settings.copyWith(
            aiGateway: controller.settings.aiGateway.copyWith(
              baseUrl: server.baseUrl,
              availableModels: const <String>['qwen2.5-coder:latest'],
              selectedModels: const <String>['qwen2.5-coder:latest'],
            ),
            defaultModel: 'gpt-5.4',
            multiAgent: controller.settings.multiAgent.copyWith(
              autoSync: false,
              mountTargets: withAvailableMountTargetsInternal(
                controller.settings.multiAgent.mountTargets,
                const <String>[],
              ),
            ),
          ),
          refreshAfterSave: false,
        );
        await controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.singleAgent,
        );

        const firstQuestion =
            'Execution context:\n'
            '- target: single-agent\n'
            '- workspace_root: /opt/data/workspace\n'
            '- permission: full-access\n\n'
            '今天聊点什么';
        const secondQuestion = '继续刚才的话题';

        final firstTurn = controller.sendChatMessage(
          firstQuestion,
          thinking: 'low',
        );
        await waitForInternal(
          () => controller.chatMessages.any(
            (message) => message.role == 'assistant' && message.pending,
          ),
        );
        expect(controller.hasAssistantPendingRun, isTrue);
        server.allowCompletion(1);
        await firstTurn;

        await waitForInternal(
          () => controller.chatMessages.any(
            (message) =>
                message.role == 'assistant' && message.text == 'FIRST_REPLY',
          ),
        );

        final secondStore = createStoreFromTempDirectoryInternal(tempDirectory);
        final secondGateway = FakeGatewayRuntimeInternal(store: secondStore);
        final secondController = await createAppControllerInternal(
          store: secondStore,
          availableSingleAgentProvidersOverride: const <SingleAgentProvider>[],
          runtimeCoordinator: RuntimeCoordinator(
            gateway: secondGateway,
            codex: FakeCodexRuntimeInternal(),
          ),
          singleAgentRunner: FallbackOnlySingleAgentRunnerInternal(),
        );

        await secondController.settingsController.saveAiGatewayApiKey(
          'live-key',
        );

        expect(secondController.chatMessages.last.text, 'FIRST_REPLY');
        expect(
          secondController.settings.assistantExecutionTarget,
          AssistantExecutionTarget.singleAgent,
        );

        final secondTurn = secondController.sendChatMessage(
          secondQuestion,
          thinking: 'low',
        );
        await waitForInternal(
          () => secondController.chatMessages.any(
            (message) => message.role == 'assistant' && message.pending,
          ),
        );
        server.allowCompletion(2);
        await secondTurn;

        await waitForInternal(
          () => secondController.chatMessages.any(
            (message) =>
                message.role == 'assistant' && message.text == 'SECOND_REPLY',
          ),
        );

        expect(server.requestCount, 2);
        expect(server.lastAuthorization, 'Bearer live-key');
        expect(server.requests.first['model'], 'qwen2.5-coder:latest');
        expect(server.requests.first['stream'], isTrue);
        expect(server.requests.first['messages'], <Map<String, dynamic>>[
          <String, dynamic>{'role': 'user', 'content': firstQuestion},
        ]);
        expect(server.requests.last['messages'], <Map<String, dynamic>>[
          <String, dynamic>{'role': 'user', 'content': firstQuestion},
          <String, dynamic>{'role': 'assistant', 'content': 'FIRST_REPLY'},
          <String, dynamic>{'role': 'user', 'content': secondQuestion},
        ]);
        expect(
          secondController.connection.status,
          RuntimeConnectionStatus.offline,
        );
        expect(secondController.assistantConnectionStatusLabel, '单机智能体');
        expect(
          secondController.assistantConnectionTargetLabel,
          'AI Chat fallback · qwen2.5-coder:latest · 127.0.0.1:${server.port}',
        );
        expect(secondController.chatMessages.last.text, 'SECOND_REPLY');
        expect(gateway.connectedProfiles, isEmpty);
        expect(secondGateway.connectedProfiles, isEmpty);
      },
    );

    test('AppController falls back when LLM API ignores stream mode', () async {
      final tempDirectory = await createTempDirectoryInternal(
        'xworkmate-ai-gateway-json-fallback-',
      );
      final server = await FakeAiGatewayServerInternal.start(
        responseMode: AiGatewayResponseModeInternal.json,
      );
      addTearDown(() async {
        await server.close();
      });

      final store = createStoreFromTempDirectoryInternal(tempDirectory);
      final controller = await createAppControllerInternal(
        store: store,
        availableSingleAgentProvidersOverride: const <SingleAgentProvider>[],
        runtimeCoordinator: RuntimeCoordinator(
          gateway: FakeGatewayRuntimeInternal(store: store),
          codex: FakeCodexRuntimeInternal(),
        ),
        singleAgentRunner: FallbackOnlySingleAgentRunnerInternal(),
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
              const <String>[],
            ),
          ),
        ),
        refreshAfterSave: false,
      );
      await controller.setAssistantExecutionTarget(
        AssistantExecutionTarget.singleAgent,
      );

      await controller.sendChatMessage('你好', thinking: 'low');

      await waitForInternal(
        () => controller.chatMessages.any(
          (message) =>
              message.role == 'assistant' && message.text == 'FIRST_REPLY',
        ),
      );

      expect(server.requests.single['stream'], isTrue);
      expect(controller.chatMessages.last.pending, isFalse);
    });

    test(
      'AppController abortRun stops Single Agent streaming requests',
      () async {
        final tempDirectory = await createTempDirectoryInternal(
          'xworkmate-ai-gateway-abort-',
        );
        final server = await FakeAiGatewayServerInternal.start(
          responseMode: AiGatewayResponseModeInternal.sse,
        );
        addTearDown(() async {
          await server.close();
        });

        final store = createStoreFromTempDirectoryInternal(tempDirectory);
        final controller = await createAppControllerInternal(
          store: store,
          availableSingleAgentProvidersOverride: const <SingleAgentProvider>[],
          runtimeCoordinator: RuntimeCoordinator(
            gateway: FakeGatewayRuntimeInternal(store: store),
            codex: FakeCodexRuntimeInternal(),
          ),
          singleAgentRunner: FallbackOnlySingleAgentRunnerInternal(),
        );

        await controller.settingsController.saveAiGatewayApiKey('live-key');
        await controller.saveSettings(
          controller.settings.copyWith(
            aiGateway: controller.settings.aiGateway.copyWith(
              baseUrl: server.baseUrl,
              availableModels: const <String>['z-ai/glm5'],
              selectedModels: const <String>['z-ai/glm5'],
            ),
            defaultModel: 'z-ai/glm5',
            multiAgent: controller.settings.multiAgent.copyWith(
              autoSync: false,
              mountTargets: withAvailableMountTargetsInternal(
                controller.settings.multiAgent.mountTargets,
                const <String>[],
              ),
            ),
          ),
          refreshAfterSave: false,
        );
        await controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.singleAgent,
        );

        final pendingTurn = controller.sendChatMessage(
          '今天聊点什么',
          thinking: 'low',
        );
        await waitForInternal(
          () => controller.chatMessages.any(
            (message) => message.role == 'assistant' && message.pending,
          ),
        );

        await controller.abortRun();
        server.allowCompletion(1);
        await pendingTurn;
        await waitForInternal(() => !controller.hasAssistantPendingRun);

        expect(
          controller.chatMessages.where((message) => message.pending),
          isEmpty,
        );
        expect(
          controller.chatMessages.where((message) => message.error),
          isEmpty,
        );
      },
    );
  });
}
