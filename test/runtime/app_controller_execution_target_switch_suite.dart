@TestOn('vm')
library;

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

class _FakeGatewayRuntime extends GatewayRuntime {
  _FakeGatewayRuntime({required super.store})
    : super(identityStore: DeviceIdentityStore(store));

  final List<GatewayConnectionProfile> connectedProfiles =
      <GatewayConnectionProfile>[];
  final Set<RuntimeConnectionMode> _failingModes = <RuntimeConnectionMode>{};
  Completer<void>? _connectGate;
  Completer<void>? _disconnectGate;
  int disconnectCount = 0;
  GatewayConnectionSnapshot _snapshot = GatewayConnectionSnapshot.initial();

  @override
  bool get isConnected => _snapshot.status == RuntimeConnectionStatus.connected;

  @override
  GatewayConnectionSnapshot get snapshot => _snapshot;

  @override
  Stream<GatewayPushEvent> get events => const Stream<GatewayPushEvent>.empty();

  @override
  Future<void> connectProfile(
    GatewayConnectionProfile profile, {
    String authTokenOverride = '',
    String authPasswordOverride = '',
  }) async {
    connectedProfiles.add(profile);
    final connectGate = _connectGate;
    _connectGate = null;
    if (connectGate != null && !connectGate.isCompleted) {
      await connectGate.future;
    }
    if (_failingModes.remove(profile.mode)) {
      _snapshot = GatewayConnectionSnapshot.initial(mode: profile.mode)
          .copyWith(
            status: RuntimeConnectionStatus.error,
            statusText: 'Error',
            remoteAddress: '${profile.host}:${profile.port}',
            lastError: 'Failed to connect ${profile.mode.name}',
          );
      notifyListeners();
      throw StateError('Failed to connect ${profile.mode.name}');
    }
    _snapshot = GatewayConnectionSnapshot.initial(mode: profile.mode).copyWith(
      status: RuntimeConnectionStatus.connected,
      statusText: 'Connected',
      remoteAddress: '${profile.host}:${profile.port}',
      connectAuthMode: 'none',
    );
    notifyListeners();
  }

  @override
  Future<void> disconnect({bool clearDesiredProfile = true}) async {
    disconnectCount += 1;
    final disconnectGate = _disconnectGate;
    _disconnectGate = null;
    if (disconnectGate != null && !disconnectGate.isCompleted) {
      await disconnectGate.future;
    }
    _snapshot = _snapshot.copyWith(
      status: RuntimeConnectionStatus.offline,
      statusText: 'Offline',
    );
    notifyListeners();
  }

  @override
  Future<dynamic> request(
    String method, {
    Map<String, dynamic>? params,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    switch (method) {
      case 'health':
      case 'status':
        return <String, dynamic>{'ok': true};
      case 'agents.list':
        return <String, dynamic>{'agents': const <Object>[], 'mainKey': 'main'};
      case 'sessions.list':
        return <String, dynamic>{'sessions': const <Object>[]};
      case 'chat.history':
        return <String, dynamic>{'messages': const <Object>[]};
      case 'skills.status':
        return <String, dynamic>{'skills': const <Object>[]};
      case 'channels.status':
        return <String, dynamic>{
          'channelMeta': const <Object>[],
          'channelLabels': const <String, dynamic>{},
          'channelDetailLabels': const <String, dynamic>{},
          'channelAccounts': const <String, dynamic>{},
          'channelOrder': const <Object>[],
        };
      case 'models.list':
        return <String, dynamic>{'models': const <Object>[]};
      case 'cron.list':
        return <String, dynamic>{'jobs': const <Object>[]};
      case 'device.pair.list':
        return <String, dynamic>{
          'pending': const <Object>[],
          'paired': const <Object>[],
        };
      case 'system-presence':
        return const <Object>[];
      default:
        return <String, dynamic>{};
    }
  }

  void failNextConnect(RuntimeConnectionMode mode) {
    _failingModes.add(mode);
  }

  void holdNextConnect(Completer<void> gate) {
    _connectGate = gate;
  }

  void holdNextDisconnect(Completer<void> gate) {
    _disconnectGate = gate;
  }
}

class _FakeCodexRuntime extends CodexRuntime {
  @override
  Future<String?> findCodexBinary() async => null;

  @override
  Future<void> stop() async {}
}

Future<void> _deleteDirectoryWithRetry(Directory directory) async {
  if (!await directory.exists()) {
    return;
  }
  for (var attempt = 0; attempt < 3; attempt += 1) {
    try {
      await directory.delete(recursive: true);
      return;
    } on FileSystemException {
      if (attempt == 2) {
        rethrow;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
}

void main() {
  test(
    'AppController switches gateway connection when assistant execution target changes',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-execution-target-switch-',
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
            assistantExecutionTarget: AssistantExecutionTarget.aiGatewayOnly,
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

      expect(
        gateway.connectedProfiles.last,
        isA<GatewayConnectionProfile>()
            .having((item) => item.mode, 'mode', RuntimeConnectionMode.local)
            .having((item) => item.host, 'host', '127.0.0.1')
            .having((item) => item.port, 'port', 18789)
            .having((item) => item.tls, 'tls', isFalse)
            .having((item) => item.selectedAgentId, 'selectedAgentId', ''),
      );
      expect(
        controller.settings.assistantExecutionTarget,
        AssistantExecutionTarget.local,
      );
      expect(
        controller.settings.primaryRemoteGatewayProfile.host,
        'gateway.example.com',
        reason: 'Saved remote profile should remain intact after local switch.',
      );
      expect(controller.settings.primaryRemoteGatewayProfile.port, 9443);
      expect(
        controller.settings.primaryRemoteGatewayProfile.mode,
        RuntimeConnectionMode.remote,
      );

      await controller.setAssistantExecutionTarget(
        AssistantExecutionTarget.aiGatewayOnly,
      );

      expect(
        controller.settings.assistantExecutionTarget,
        AssistantExecutionTarget.aiGatewayOnly,
      );
      expect(
        controller.settings.primaryRemoteGatewayProfile.host,
        'gateway.example.com',
        reason:
            'AI Gateway-only mode should preserve the saved remote endpoint.',
      );
      expect(controller.settings.primaryRemoteGatewayProfile.port, 9443);
      expect(controller.settings.primaryRemoteGatewayProfile.tls, isTrue);
      expect(
        controller.settings.primaryRemoteGatewayProfile.mode,
        RuntimeConnectionMode.remote,
      );
      expect(gateway.disconnectCount, 1);
      expect(controller.assistantConnectionStatusLabel, '仅 AI Gateway');
      expect(
        controller.assistantConnectionTargetLabel,
        'qwen2.5-coder:latest · 127.0.0.1:11434',
      );
      expect(
        gateway.connectedProfiles,
        hasLength(2),
        reason: 'AI Gateway-only mode should not open another gateway session.',
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
      expect(gateway.connectedProfiles.last.mode, RuntimeConnectionMode.remote);
    },
  );

  test(
    'AppController applySettingsDraft syncs the active session execution target',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-apply-settings-sync-',
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
        AssistantExecutionTarget.local,
      );

      await controller.saveSettingsDraft(
        controller.settingsDraft.copyWith(
          assistantExecutionTarget: AssistantExecutionTarget.remote,
        ),
      );
      await controller.applySettingsDraft();

      expect(
        controller.currentAssistantExecutionTarget,
        AssistantExecutionTarget.remote,
      );
      expect(
        controller.assistantExecutionTargetForSession(
          controller.currentSessionKey,
        ),
        AssistantExecutionTarget.remote,
      );
      expect(
        controller.assistantConnectionTargetLabel,
        'openclaw.svc.plus:443',
      );
      expect(gateway.connectedProfiles.last.mode, RuntimeConnectionMode.remote);
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
        _withLocalGatewayProfile(
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
    'AppController notifies aiGatewayOnly target changes before disconnect completes',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-execution-target-disconnect-notify-',
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
            assistantExecutionTarget: AssistantExecutionTarget.aiGatewayOnly,
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
        AssistantExecutionTarget.aiGatewayOnly,
      );
      var completed = false;
      switchFuture.then((_) {
        completed = true;
      });

      try {
        await _waitFor(() => gateway.disconnectCount == 1);

        expect(notificationCount, greaterThan(0));
        expect(
          controller.assistantExecutionTarget,
          AssistantExecutionTarget.aiGatewayOnly,
        );
        expect(controller.assistantConnectionStatusLabel, '仅 AI Gateway');
        expect(completed, isFalse);
      } finally {
        if (!disconnectGate.isCompleted) {
          disconnectGate.complete();
        }
      }

      await switchFuture;

      expect(
        controller.settings.assistantExecutionTarget,
        AssistantExecutionTarget.aiGatewayOnly,
      );
      expect(
        controller.assistantExecutionTarget,
        AssistantExecutionTarget.aiGatewayOnly,
      );
      expect(controller.assistantConnectionStatusLabel, '仅 AI Gateway');
    },
  );

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
        executionTarget: AssistantExecutionTarget.aiGatewayOnly,
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
      expect(gateway.connectedProfiles.last.mode, RuntimeConnectionMode.remote);
      expect(
        controller.settings.assistantExecutionTarget,
        AssistantExecutionTarget.local,
        reason: 'Thread switching should not overwrite the new-thread default.',
      );

      await controller.switchSession('main');

      expect(
        controller.assistantExecutionTarget,
        AssistantExecutionTarget.aiGatewayOnly,
      );
      expect(gateway.disconnectCount, 1);
      expect(controller.assistantConnectionStatusLabel, '仅 AI Gateway');
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
      expect(controller.assistantConnectionTargetLabel, '127.0.0.1:18789');

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
        executionTarget: AssistantExecutionTarget.aiGatewayOnly,
      );
      await controller.switchSession('main');

      expect(controller.assistantConnectionStatusLabel, '仅 AI Gateway');
      expect(
        controller.assistantConnectionTargetLabel,
        'qwen2.5-coder:latest · 127.0.0.1:11434',
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

    await controller.setAssistantMessageViewMode(AssistantMessageViewMode.raw);
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
        executionTarget: AssistantExecutionTarget.aiGatewayOnly,
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
        () => firstController.settings.assistantLastSessionKey == 'draft:beta',
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
      final reloadedThreads = await reloadedStore.loadAssistantThreadRecords();

      expect(
        reloadedSnapshot.accountUsername,
        SettingsSnapshot.defaults().accountUsername,
      );
      expect(reloadedSnapshot.assistantLastSessionKey, isEmpty);
      expect(reloadedThreads, isEmpty);
    },
  );
}

Future<void> _waitFor(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition not met before timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

SettingsSnapshot _withRemoteGatewayProfile(
  SettingsSnapshot snapshot,
  GatewayConnectionProfile profile,
) {
  return snapshot.copyWithGatewayProfileAt(kGatewayRemoteProfileIndex, profile);
}

SettingsSnapshot _withLocalGatewayProfile(
  SettingsSnapshot snapshot,
  GatewayConnectionProfile profile,
) {
  return snapshot.copyWithGatewayProfileAt(kGatewayLocalProfileIndex, profile);
}
