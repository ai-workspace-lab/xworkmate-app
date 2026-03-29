@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/codex_config_bridge.dart';
import 'package:xworkmate/runtime/codex_runtime.dart';
import 'package:xworkmate/runtime/device_identity_store.dart';
import 'package:xworkmate/runtime/gateway_runtime.dart';
import 'package:xworkmate/runtime/mode_switcher.dart';
import 'package:xworkmate/runtime/runtime_coordinator.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';

class MockGatewayRuntime extends GatewayRuntime {
  factory MockGatewayRuntime() {
    final tempDir = Directory.systemTemp.createTempSync(
      'xworkmate-codex-integration-gateway-',
    );
    final store = SecureConfigStore(
      enableSecureStorage: false,
      fallbackDirectoryPathResolver: () async => tempDir.path,
    );
    return MockGatewayRuntime._(store);
  }

  MockGatewayRuntime._(SecureConfigStore store)
    : super(store: store, identityStore: DeviceIdentityStore(store));

  final StreamController<GatewayPushEvent> _eventsController =
      StreamController<GatewayPushEvent>.broadcast();
  GatewayConnectionSnapshot _snapshot = GatewayConnectionSnapshot.initial();
  bool _connected = false;

  @override
  bool get isConnected => _connected;

  @override
  GatewayConnectionSnapshot get snapshot => _snapshot;

  @override
  Stream<GatewayPushEvent> get events => _eventsController.stream;

  @override
  Future<dynamic> request(
    String method, {
    Map<String, dynamic>? params,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    return <String, dynamic>{
      'success': true,
      'method': method,
      'params': params ?? const <String, dynamic>{},
    };
  }

  @override
  Future<void> connectProfile(
    GatewayConnectionProfile profile, {
    int? profileIndex,
    String authTokenOverride = '',
    String authPasswordOverride = '',
  }) async {
    _connected = true;
    _snapshot = GatewayConnectionSnapshot.initial(mode: profile.mode).copyWith(
      status: RuntimeConnectionStatus.connected,
      statusText: 'Connected',
      serverName: profile.host,
      remoteAddress: '${profile.host}:${profile.port}',
      connectAuthMode: authTokenOverride.isNotEmpty ? 'shared-token' : null,
    );
    notifyListeners();
    unawaited(
      Future<void>.delayed(Duration.zero, () {
        _eventsController.add(
          const GatewayPushEvent(
            event: 'gateway/connected',
            payload: <String, dynamic>{},
          ),
        );
      }),
    );
  }

  @override
  Future<void> disconnect({bool clearDesiredProfile = true}) async {
    _connected = false;
    _snapshot = GatewayConnectionSnapshot.initial(mode: _snapshot.mode);
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_eventsController.close());
    super.dispose();
  }
}

void main() {
  group('CodexConfigBridge integration', () {
    test('configureForGateway writes managed provider block', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'codex_gateway_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final bridge = CodexConfigBridge(codexHome: tempDir.path);

      await bridge.configureForGateway(
        gatewayUrl: 'https://api.svc.plus/v1',
        apiKey: 'test-api-key',
        defaultModel: 'gpt-4.1',
      );

      final configFile = File('${tempDir.path}/config.toml');
      expect(await configFile.exists(), isTrue);

      final content = await configFile.readAsString();
      expect(content, contains('[model_providers.xworkmate]'));
      expect(content, contains('base_url = "https://api.svc.plus/v1"'));
      expect(content, contains('experimental_bearer_token = "test-api-key"'));
      expect(content, contains('wire_api = "responses"'));
      expect(content, contains('model = "gpt-4.1"'));
    });

    test('configureForGateway preserves unmanaged config content', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'codex_gateway_preserve_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final configFile = File('${tempDir.path}/config.toml');
      await configFile.writeAsString('[existing]\nvalue = "keep-me"\n');

      final bridge = CodexConfigBridge(codexHome: tempDir.path);
      await bridge.configureForGateway(
        gatewayUrl: 'https://api.svc.plus/v1',
        apiKey: 'test-api-key',
      );

      final content = await configFile.readAsString();
      expect(content, contains('[existing]'));
      expect(content, contains('value = "keep-me"'));
      expect(
        '# BEGIN XWORKMATE MANAGED BLOCK'.allMatches(content).length,
        equals(1),
      );
    });
  });

  group('RuntimeCoordinator integration', () {
    late MockGatewayRuntime gateway;
    late CodexRuntime codex;
    late RuntimeCoordinator coordinator;
    late Directory tempDir;
    late CodexConfigBridge bridge;

    setUp(() async {
      gateway = MockGatewayRuntime();
      codex = CodexRuntime();
      tempDir = await Directory.systemTemp.createTemp(
        'runtime_coordinator_test_',
      );
      bridge = CodexConfigBridge(codexHome: tempDir.path);
      coordinator = RuntimeCoordinator(
        gateway: gateway,
        codex: codex,
        configBridge: bridge,
      );
    });

    tearDown(() async {
      await coordinator.shutdown();
      gateway.dispose();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'initialize supports offline mode without external services',
      () async {
        await coordinator.initialize(preferredMode: GatewayMode.offline);

        expect(coordinator.state, equals(CoordinatorState.ready));
        expect(coordinator.currentMode, equals(GatewayMode.offline));
        expect(coordinator.capabilities, equals(ModeCapabilities.offline));
      },
    );

    test('switchMode updates the current mode to local', () async {
      await coordinator.switchMode(GatewayMode.local);

      expect(coordinator.currentMode, equals(GatewayMode.local));
      expect(gateway.snapshot.mode, equals(RuntimeConnectionMode.local));
      expect(
        gateway.snapshot.status,
        equals(RuntimeConnectionStatus.connected),
      );
    });

    test('configureCodexForGateway delegates to config bridge', () async {
      await coordinator.configureCodexForGateway(
        gatewayUrl: 'https://api.svc.plus/v1',
        apiKey: 'test-api-key',
      );

      expect(await bridge.hasConfig(), isTrue);
      final providerConfig = await bridge.readProviderConfig('xworkmate');
      expect(providerConfig, isNotNull);
      expect(providerConfig!['base_url'], equals('https://api.svc.plus/v1'));
    });

    test(
      'registerExternalCodeAgent supports capability-filtered discovery',
      () async {
        coordinator.registerExternalCodeAgent(
          const ExternalCodeAgentProvider(
            id: 'opencode',
            name: 'OpenCode',
            command: 'opencode',
            capabilities: <String>['planning', 'review'],
          ),
        );
        coordinator.registerExternalCodeAgent(
          const ExternalCodeAgentProvider(
            id: 'gemini',
            name: 'Gemini CLI',
            command: 'gemini',
            capabilities: <String>['planning'],
          ),
        );

        final matches = coordinator.discoverExternalCodeAgents(
          requiredCapabilities: const <String>['planning'],
        );

        expect(
          matches.map((item) => item.id),
          containsAll(<String>['gemini', 'opencode']),
        );
        expect(
          (await coordinator.selectExternalCodeAgent(
            preferredProviderId: 'opencode',
            requiredCapabilities: const <String>['review'],
          ))?.id,
          equals('opencode'),
        );
      },
    );
  });
}
