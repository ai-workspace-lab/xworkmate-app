import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/codex_runtime.dart';
import 'package:xworkmate/runtime/codex_config_bridge.dart';
import 'package:xworkmate/runtime/runtime_coordinator.dart';
import 'package:xworkmate/runtime/gateway_runtime.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';
import 'package:xworkmate/runtime/device_identity_store.dart';

/// Integration tests for Codex CLI integration.
/// 
/// These tests require:
/// 1. Codex CLI installed (npm i -g @openai/codex)
/// 2. AI Gateway URL and API Key in .env file
/// 3. Network access to the AI Gateway
/// 
/// Run with: flutter test test/runtime/codex_integration_test.dart
class MockGatewayRuntime extends ChangeNotifier implements GatewayRuntime {
  GatewayConnectionSnapshot _snapshot = GatewayConnectionSnapshot.initial();
  final StreamController<GatewayPushEvent> _events = StreamController.broadcast();

  @override
  bool get isConnected => _snapshot.status == RuntimeConnectionStatus.connected;

  @override
  GatewayConnectionSnapshot get snapshot => _snapshot;

  @override
  Stream<GatewayPushEvent> get events => _events.stream;

  @override
  Future<Map<String, dynamic>> request(String method, {Map<String, dynamic> params = const {}, Duration timeout = const Duration(seconds: 30)}) async {
    return {'success': true};
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<void> connectProfile(GatewayConnectionProfile profile, {String authTokenOverride = '', String authPasswordOverride = ''}) async {
    _snapshot = GatewayConnectionSnapshot(
      profile: profile,
      status: RuntimeConnectionStatus.connected,
    );
    notifyListeners();
  }

  @override
  Future<void> disconnect() async {
    _snapshot = GatewayConnectionSnapshot(
      profile: _snapshot.profile,
      status: RuntimeConnectionStatus.offline,
    );
    notifyListeners();
  }

  @override
  Future<void> clearLogs() async {}

  @override
  List<RuntimeLogEntry> get logs => [];

  @override
  List<RuntimeLogEntry> get logsForTest => [];

  @override
  void addRuntimeLogForTest({required String level, required String category, required String message}) {}
}

/// Load AI Gateway configuration from .env file.
Future<({String url, String apiKey})> loadEnvConfig() async {
  final envFile = File('.env');
  if (!await envFile.exists()) {
    throw StateError('.env file not found. Create it with AI-Gateway-Url and AI-Gateway-apiKey');
  }

  final content = await envFile.readAsString();
  String? url;
  String? apiKey;

  for (final line in content.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

    if (trimmed.contains('AI-Gateway-Url')) {
      // Extract URL from line like: "AI-Gateway-Url": "https://api.svc.plus/v1",
      final match = RegExp(r'"([^"]+)"').firstMatch(trimmed.split(':')[1] ?? '');
      if (match != null) {
        url = match.group(1);
      }
    }

    if (trimmed.contains('AI-Gateway-apiKey')) {
      // Extract API key from line like: "AI-Gateway-apiKey": "xxx",
      final match = RegExp(r'"([^"]+)"').firstMatch(trimmed.split(':')[1] ?? '');
      if (match != null) {
        apiKey = match.group(1);
      }
    }
  }

  if (url == null || apiKey == null) {
    throw StateError('AI-Gateway-Url and AI-Gateway-apiKey must be set in .env');
  }

  return (url: url, apiKey: apiKey);
}

void main() {
  group('Codex CLI Integration Tests', () {
    late CodexRuntime codex;
    late CodexConfigBridge configBridge;

    setUp(() {
      codex = CodexRuntime();
      configBridge = CodexConfigBridge();
    });

    tearDown(() async {
      await codex.stop();
    });

    test('findCodexBinary returns path when codex is installed', () async {
      final path = await codex.findCodexBinary();
      // This test passes whether or not codex is installed
      // It just verifies the method doesn't throw
      print('Codex binary path: $path');
    }, skip: 'Run manually when codex is installed');

    test('startStdio initializes codex app-server', () async {
      final codexPath = await codex.findCodexBinary();
      if (codexPath == null) {
        throw StateError('Codex CLI not found. Install with: npm i -g @openai/codex');
      }

      await codex.startStdio(
        codexPath: codexPath,
        cwd: Directory.current.path,
      );

      expect(codex.isConnected, isTrue);
      expect(codex.state, equals(CodexConnectionState.ready));
      expect(codex.isReady, isTrue);
    }, skip: 'Run manually when codex is installed');

    test('startThread creates a new thread', () async {
      // This test requires a running codex instance
      // It's skipped by default and should be run manually
    }, skip: 'Requires running codex instance');

    test('sendMessage streams events', () async {
      // This test requires a running codex instance
      // It's skipped by default and should be run manually
    }, skip: 'Requires running codex instance');
  });

  group('AI Gateway Configuration Tests', () {
    test('configureForGateway creates valid config for AI Gateway', () async {
      final config = await loadEnvConfig();

      final tempDir = await Directory.systemTemp.createTemp('codex_gateway_test_');
      final bridge = CodexConfigBridge(codexHome: tempDir.path);

      try {
        await bridge.configureForGateway(
          gatewayUrl: config.url,
          apiKey: config.apiKey,
          defaultModel: 'gpt-4.1',
        );

        final configFile = File('${tempDir.path}/config.toml');
        expect(await configFile.exists(), isTrue);

        final content = await configFile.readAsString();
        expect(content, contains('[model_providers.xworkmate]'));
        expect(content, contains(config.url));
        expect(content, contains(config.apiKey));
        expect(content, contains('wire_api = "responses"'));
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('loadEnvConfig reads AI Gateway credentials', () async {
      final config = await loadEnvConfig();

      expect(config.url, isNotEmpty);
      expect(config.apiKey, isNotEmpty);
      expect(config.url, contains('http'));
    });
  });

  group('RuntimeCoordinator Integration Tests', () {
    late RuntimeCoordinator coordinator;
    late MockGatewayRuntime mockGateway;
    late CodexRuntime codex;

    setUp(() {
      mockGateway = MockGatewayRuntime();
      codex = CodexRuntime();
      coordinator = RuntimeCoordinator(
        gateway: mockGateway,
        codex: codex,
      );
    });

    tearDown() async {
      await coordinator.shutdown();
    });

    test('initialize connects to gateway and starts codex', () async {
      final config = await loadEnvConfig();

      final profile = GatewayConnectionProfile.defaults().copyWith(
        host: 'openclaw.svc.plus',
        port: 443,
        tls: true,
      );

      // This test would need a real gateway connection
      // It's skipped by default
    }, skip: 'Requires real gateway connection');

    test('switchMode updates mode correctly', () async {
      // Setup mock connection
      await mockGateway.connectProfile(GatewayConnectionProfile.defaults());

      await coordinator.switchMode(CoordinatorMode.offline);
      expect(coordinator.mode, equals(CoordinatorMode.offline));
    });

    test('getAvailableModels returns models from gateway and codex', () async {
      // This test requires both gateway and codex connections
    }, skip: 'Requires running services');
  });

  group('End-to-End Integration Tests', () {
    test('full workflow: configure, connect, send message', () async {
      final config = await loadEnvConfig();

      // Step 1: Configure Codex for AI Gateway
      final tempDir = await Directory.systemTemp.createTemp('codex_e2e_test_');
      final bridge = CodexConfigBridge(codexHome: tempDir.path);

      try {
        await bridge.configureForGateway(
          gatewayUrl: config.url,
          apiKey: config.apiKey,
        );

        // Step 2: Verify configuration
        expect(await bridge.hasConfig(), isTrue);

        // Step 3: Read back configuration
        final providerConfig = await bridge.readProviderConfig('xworkmate');
        expect(providerConfig, isNotNull);
        expect(providerConfig!['base_url'], equals(config.url));

        print('Successfully configured Codex for AI Gateway: ${config.url}');
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('online/offline mode switching', () async {
      // This test would verify:
      // 1. Online mode: Gateway + Codex
      // 2. Offline mode: Local Codex only
      // 3. Automatic fallback
    }, skip: 'Requires running services');
  });
}
