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
}

class _FakeCodexRuntime extends CodexRuntime {
  @override
  Future<String?> findCodexBinary() async => null;

  @override
  Future<void> stop() async {}
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
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
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
        controller.settings.copyWith(
          aiGateway: controller.settings.aiGateway.copyWith(
            baseUrl: 'http://127.0.0.1:11434/v1',
            availableModels: const <String>['qwen2.5-coder:latest'],
            selectedModels: const <String>['qwen2.5-coder:latest'],
          ),
          defaultModel: 'qwen2.5-coder:latest',
          gateway: controller.settings.gateway.copyWith(
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
            .having(
              (item) => item.selectedAgentId,
              'selectedAgentId',
              'assistant-main',
            ),
      );
      expect(
        controller.settings.assistantExecutionTarget,
        AssistantExecutionTarget.local,
      );
      expect(
        controller.settings.gateway.host,
        'gateway.example.com',
        reason: 'Saved remote profile should remain intact after local switch.',
      );
      expect(controller.settings.gateway.port, 9443);
      expect(controller.settings.gateway.mode, RuntimeConnectionMode.remote);

      await controller.setAssistantExecutionTarget(
        AssistantExecutionTarget.aiGatewayOnly,
      );

      expect(
        controller.settings.assistantExecutionTarget,
        AssistantExecutionTarget.aiGatewayOnly,
      );
      expect(
        controller.settings.gateway.mode,
        RuntimeConnectionMode.unconfigured,
      );
      expect(controller.settings.gateway.useSetupCode, isFalse);
      expect(controller.settings.gateway.setupCode, isEmpty);
      expect(
        controller.settings.gateway.host,
        'gateway.example.com',
        reason:
            'AI Gateway-only mode should preserve the saved remote endpoint.',
      );
      expect(controller.settings.gateway.port, 9443);
      expect(controller.settings.gateway.tls, isTrue);
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
