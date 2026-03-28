part of 'app_controller_ai_gateway_chat_suite.dart';

void _registerAppControllerAiGatewayChatSuiteSingleAgentTests() {
  group('Single Agent provider resolution', () {
    test(
      'AppController uses the selected Single Agent provider before AI Chat fallback',
      () async {
        final tempDirectory = await _createTempDirectory(
          'xworkmate-single-agent-provider-',
        );
        final store = _createStoreFromTempDirectory(tempDirectory);
        final runner = _FakeSingleAgentRunner(
          resolvedProvider: SingleAgentProvider.opencode,
          result: const SingleAgentRunResult(
            provider: SingleAgentProvider.opencode,
            output: 'CODEX_REPLY',
            success: true,
            errorMessage: '',
            shouldFallbackToAiChat: false,
            resolvedModel: 'codex-sonnet',
          ),
        );
        final controller = await _createAppController(
          store: store,
          availableSingleAgentProvidersOverride: const <SingleAgentProvider>[
            SingleAgentProvider.opencode,
          ],
          runtimeCoordinator: RuntimeCoordinator(
            gateway: _FakeGatewayRuntime(store: store),
            codex: _FakeCodexRuntime(),
          ),
          singleAgentRunner: runner,
        );

        await controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.singleAgent,
        );
        await controller.setSingleAgentProvider(SingleAgentProvider.opencode);

        await controller.sendChatMessage('请输出 CODEX_REPLY', thinking: 'low');

        expect(runner.resolveCalls, 1);
        expect(runner.runCalls, 1);
        expect(runner.lastRequest?.provider, SingleAgentProvider.opencode);
        expect(runner.lastRequest?.model, isEmpty);
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
        final tempDirectory = await _createTempDirectory(
          'xworkmate-single-agent-provider-debug-',
        );
        final store = _createStoreFromTempDirectory(tempDirectory);
        final runner = _FakeSingleAgentRunner(
          resolvedProvider: SingleAgentProvider.opencode,
          result: const SingleAgentRunResult(
            provider: SingleAgentProvider.opencode,
            output: 'CODEX_REPLY',
            success: true,
            errorMessage: '',
            shouldFallbackToAiChat: false,
            resolvedModel: 'codex-sonnet',
          ),
        );
        final controller = await _createAppController(
          store: store,
          availableSingleAgentProvidersOverride: const <SingleAgentProvider>[
            SingleAgentProvider.opencode,
          ],
          runtimeCoordinator: RuntimeCoordinator(
            gateway: _FakeGatewayRuntime(store: store),
            codex: _FakeCodexRuntime(),
          ),
          singleAgentRunner: runner,
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
      'AppController keeps the thread provider strict when another external CLI is available',
      () async {
        final tempDirectory = await _createTempDirectory(
          'xworkmate-single-agent-strict-provider-',
        );
        final server = await _FakeAiGatewayServer.start(
          responseMode: _AiGatewayResponseMode.json,
        );
        addTearDown(() async {
          await server.close();
        });

        final store = _createStoreFromTempDirectory(tempDirectory);
        final runner = _FakeSingleAgentRunner(
          resolvedProvider: null,
          fallbackReason: 'Codex CLI is unavailable on this device.',
        );
        final controller = await _createAppController(
          store: store,
          availableSingleAgentProvidersOverride: const <SingleAgentProvider>[
            SingleAgentProvider.claude,
          ],
          runtimeCoordinator: RuntimeCoordinator(
            gateway: _FakeGatewayRuntime(store: store),
            codex: _FakeCodexRuntime(),
          ),
          singleAgentRunner: runner,
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
              mountTargets: _withAvailableMountTargets(
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

        expect(runner.resolveCalls, 1);
        expect(runner.runCalls, 0);
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
        final tempDirectory = await _createTempDirectory(
          'xworkmate-single-agent-fallback-',
        );
        final server = await _FakeAiGatewayServer.start(
          responseMode: _AiGatewayResponseMode.json,
        );
        addTearDown(() async {
          await server.close();
        });

        final store = _createStoreFromTempDirectory(tempDirectory);
        final runner = _FakeSingleAgentRunner(
          resolvedProvider: null,
          fallbackReason: 'Codex CLI is unavailable on this device.',
        );
        final controller = await _createAppController(
          store: store,
          availableSingleAgentProvidersOverride: const <SingleAgentProvider>[],
          runtimeCoordinator: RuntimeCoordinator(
            gateway: _FakeGatewayRuntime(store: store),
            codex: _FakeCodexRuntime(),
          ),
          singleAgentRunner: runner,
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

        expect(runner.resolveCalls, 1);
        expect(runner.runCalls, 0);
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
        final tempDirectory = await _createTempDirectory(
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

        final store = _createStoreFromTempDirectory(tempDirectory);
        await store.initialize();
        await store.saveSettingsSnapshot(
          SettingsSnapshot.defaults().copyWith(
            workspacePath: defaultWorkspace.path,
            assistantExecutionTarget: AssistantExecutionTarget.singleAgent,
          ),
        );
        await store.saveAssistantThreadRecords(<AssistantThreadRecord>[
          AssistantThreadRecord(
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

        final runner = _FakeSingleAgentRunner(
          resolvedProvider: SingleAgentProvider.opencode,
          result: const SingleAgentRunResult(
            provider: SingleAgentProvider.opencode,
            output: 'THREAD_OK',
            success: true,
            errorMessage: '',
            shouldFallbackToAiChat: false,
          ),
        );
        final controller = await _createAppController(
          store: store,
          availableSingleAgentProvidersOverride: const <SingleAgentProvider>[
            SingleAgentProvider.opencode,
          ],
          runtimeCoordinator: RuntimeCoordinator(
            gateway: _FakeGatewayRuntime(store: store),
            codex: _FakeCodexRuntime(),
          ),
          singleAgentRunner: runner,
        );

        await controller.sendChatMessage('检查当前线程目录', thinking: 'low');

        expect(runner.runCalls, 1);
        expect(runner.lastRequest?.workingDirectory, threadWorkspace.path);
        expect(
          controller.assistantWorkspaceRefForSession('main'),
          threadWorkspace.path,
        );
      },
    );

    test(
      'AppController uses an isolated workspace for draft Single Agent threads',
      () async {
        final tempDirectory = await _createTempDirectory(
          'xworkmate-single-agent-isolated-thread-cwd-',
        );
        final defaultWorkspace = Directory(
          '${tempDirectory.path}/default-workspace',
        );
        await defaultWorkspace.create(recursive: true);

        final store = _createStoreFromTempDirectory(tempDirectory);
        await store.initialize();
        await store.saveSettingsSnapshot(
          SettingsSnapshot.defaults().copyWith(
            workspacePath: defaultWorkspace.path,
            assistantExecutionTarget: AssistantExecutionTarget.singleAgent,
          ),
        );

        final runner = _FakeSingleAgentRunner(
          resolvedProvider: SingleAgentProvider.opencode,
          result: const SingleAgentRunResult(
            provider: SingleAgentProvider.opencode,
            output: 'THREAD_OK',
            success: true,
            errorMessage: '',
            shouldFallbackToAiChat: false,
          ),
        );
        final controller = await _createAppController(
          store: store,
          availableSingleAgentProvidersOverride: const <SingleAgentProvider>[
            SingleAgentProvider.opencode,
          ],
          runtimeCoordinator: RuntimeCoordinator(
            gateway: _FakeGatewayRuntime(store: store),
            codex: _FakeCodexRuntime(),
          ),
          singleAgentRunner: runner,
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
        expect(runner.runCalls, 1);
        expect(
          runner.lastRequest?.workingDirectory,
          '${defaultWorkspace.path}/$expectedWorkspaceSuffix',
        );
        expect(
          controller.assistantWorkspaceRefForSession('draft:artifact-thread'),
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
        final tempDirectory = await _createTempDirectory(
          'xworkmate-single-agent-remote-thread-cwd-',
        );
        final defaultWorkspace = Directory(
          '${tempDirectory.path}/default-workspace',
        );
        await defaultWorkspace.create(recursive: true);

        final store = _createStoreFromTempDirectory(tempDirectory);
        await store.initialize();
        await store.saveSettingsSnapshot(
          SettingsSnapshot.defaults().copyWith(
            workspacePath: defaultWorkspace.path,
            assistantExecutionTarget: AssistantExecutionTarget.singleAgent,
          ),
        );

        final runner = _FakeSingleAgentRunner(
          resolvedProvider: SingleAgentProvider.opencode,
          result: const SingleAgentRunResult(
            provider: SingleAgentProvider.opencode,
            output: 'THREAD_OK',
            success: true,
            errorMessage: '',
            shouldFallbackToAiChat: false,
            resolvedWorkingDirectory:
                '/opt/data/.xworkmate/threads/draft-remote-thread',
            resolvedWorkspaceRefKind: WorkspaceRefKind.localPath,
          ),
        );
        final controller = await _createAppController(
          store: store,
          availableSingleAgentProvidersOverride: const <SingleAgentProvider>[
            SingleAgentProvider.opencode,
          ],
          runtimeCoordinator: RuntimeCoordinator(
            gateway: _FakeGatewayRuntime(store: store),
            codex: _FakeCodexRuntime(),
          ),
          singleAgentRunner: runner,
        );

        controller.initializeAssistantThreadContext(
          'draft:remote-thread',
          title: 'Remote Thread',
          executionTarget: AssistantExecutionTarget.singleAgent,
        );
        await controller.switchSession('draft:remote-thread');

        await controller.sendChatMessage('第一次运行', thinking: 'low');
        expect(
          runner.requests.first.workingDirectory,
          '${defaultWorkspace.path}/.xworkmate/threads/draft-remote-thread',
        );
        expect(
          controller.assistantWorkspaceRefForSession('draft:remote-thread'),
          '${defaultWorkspace.path}/.xworkmate/threads/draft-remote-thread',
        );
        expect(
          controller.assistantWorkspaceRefKindForSession('draft:remote-thread'),
          WorkspaceRefKind.localPath,
        );

        await controller.sendChatMessage('第二次运行', thinking: 'low');
        expect(
          runner.requests.last.workingDirectory,
          '${defaultWorkspace.path}/.xworkmate/threads/draft-remote-thread',
        );
      },
    );
  });
}
