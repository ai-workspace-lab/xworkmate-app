part of 'app_controller_execution_target_switch_suite.dart';

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
          await _deleteDirectoryWithRetry(tempDirectory);
        });
        final store = SecureConfigStore(
          enableSecureStorage: false,
          databasePathResolver: () async => '${tempDirectory.path}/settings.db',
          fallbackDirectoryPathResolver: () async => tempDirectory.path,
        );
        final gateway = _FakeGatewayRuntime(store: store);
        final controller = AppController(
          store: store,
          runtimeCoordinator: RuntimeCoordinator(
            gateway: gateway,
            codex: _FakeCodexRuntime(),
          ),
        );
        addTearDown(controller.dispose);

        await _waitFor(() => !controller.initializing);
        await controller.saveSettings(
          _withRemoteGatewayProfile(
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
        expect(controller.assistantConnectionStatusLabel, '单机智能体');
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
          await _deleteDirectoryWithRetry(tempDirectory);
        });
        final store = SecureConfigStore(
          enableSecureStorage: false,
          databasePathResolver: () async => '${tempDirectory.path}/settings.db',
          fallbackDirectoryPathResolver: () async => tempDirectory.path,
        );
        final gateway = _FakeGatewayRuntime(store: store);
        final controller = AppController(
          store: store,
          runtimeCoordinator: RuntimeCoordinator(
            gateway: gateway,
            codex: _FakeCodexRuntime(),
          ),
        );
        addTearDown(controller.dispose);

        await _waitFor(() => !controller.initializing);
        await controller.saveSettings(
          _withRemoteGatewayProfile(
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

        expect(controller.assistantConnectionStatusLabel, '单机智能体');
        expect(
          controller.assistantConnectionTargetLabel,
          '没有可用的外部 Agent ACP 端点，请配置 LLM API fallback。',
        );
      },
    );

    test('AppController persists markdown view mode per thread', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-thread-view-mode-',
      );
      addTearDown(() async {
        await _deleteDirectoryWithRetry(tempDirectory);
      });
      final store = SecureConfigStore(
        enableSecureStorage: false,
        databasePathResolver: () async => '${tempDirectory.path}/settings.db',
        fallbackDirectoryPathResolver: () async => tempDirectory.path,
      );
      final controller = AppController(
        store: store,
        runtimeCoordinator: RuntimeCoordinator(
          gateway: _FakeGatewayRuntime(store: store),
          codex: _FakeCodexRuntime(),
        ),
      );
      addTearDown(controller.dispose);

      await _waitFor(() => !controller.initializing);

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

      final reloaded = await store.loadAssistantThreadRecords();
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
          await _deleteDirectoryWithRetry(tempDirectory);
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
            gateway: _FakeGatewayRuntime(store: firstStore),
            codex: _FakeCodexRuntime(),
          ),
        );
        addTearDown(firstController.dispose);

        await _waitFor(() => !firstController.initializing);
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

        await _waitFor(
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
            gateway: _FakeGatewayRuntime(store: secondStore),
            codex: _FakeCodexRuntime(),
          ),
        );
        addTearDown(secondController.dispose);

        await _waitFor(() => !secondController.initializing);

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
      'AppController clears local assistant state and resets persisted defaults',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final tempDirectory = await Directory.systemTemp.createTemp(
          'xworkmate-thread-clear-local-',
        );
        addTearDown(() async {
          await _deleteDirectoryWithRetry(tempDirectory);
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
            gateway: _FakeGatewayRuntime(store: store),
            codex: _FakeCodexRuntime(),
          ),
        );
        addTearDown(controller.dispose);

        await _waitFor(() => !controller.initializing);
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
        expect(controller.settings.assistantLastSessionKey, isEmpty);
        expect(controller.assistantCustomTaskTitle('draft:clear-me'), isEmpty);

        final reloadedStore = SecureConfigStore(
          enableSecureStorage: false,
          databasePathResolver: () async => databasePath,
          fallbackDirectoryPathResolver: () async => tempDirectory.path,
        );
        final reloadedSnapshot = await reloadedStore.loadSettingsSnapshot();
        final reloadedThreads = await reloadedStore
            .loadAssistantThreadRecords();

        expect(
          reloadedSnapshot.accountUsername,
          SettingsSnapshot.defaults().accountUsername,
        );
        expect(reloadedSnapshot.assistantLastSessionKey, isEmpty);
        expect(reloadedThreads, isEmpty);
      },
    );
  });
}
