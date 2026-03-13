import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/codex_config_bridge.dart';

void main() {
  group('CodexSandboxMode', () {
    test('has correct values', () {
      expect(CodexSandboxMode.readOnly.value, equals('read-only'));
      expect(CodexSandboxMode.workspaceWrite.value, equals('workspace-write'));
      expect(CodexSandboxMode.dangerFullAccess.value, equals('danger-full-access'));
    });
  });

  group('CodexApprovalPolicy', () {
    test('has correct values', () {
      expect(CodexApprovalPolicy.suggest.value, equals('suggest'));
      expect(CodexApprovalPolicy.autoEdit.value, equals('auto-edit'));
      expect(CodexApprovalPolicy.fullAuto.value, equals('full-auto'));
    });
  });

  group('CodexConfigBridge', () {
    late CodexConfigBridge bridge;
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('codex_config_test_');
      bridge = CodexConfigBridge(codexHome: tempDir.path);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('configureForGateway creates config.toml', () async {
      await bridge.configureForGateway(
        gatewayUrl: 'https://api.example.com/v1',
        apiKey: 'test-api-key',
        providerName: 'test-provider',
        defaultModel: 'gpt-4',
      );

      final configFile = File('${tempDir.path}/config.toml');
      expect(await configFile.exists(), isTrue);

      final content = await configFile.readAsString();
      expect(content, contains('[model_providers.test-provider]'));
      expect(content, contains('base_url = "https://api.example.com/v1"'));
      expect(content, contains('experimental_bearer_token = "test-api-key"'));
      expect(content, contains('model = "gpt-4"'));
    });

    test('configureForGateway uses default values', () async {
      await bridge.configureForGateway(
        gatewayUrl: 'https://api.example.com/v1',
        apiKey: '',
      );

      final configFile = File('${tempDir.path}/config.toml');
      final content = await configFile.readAsString();

      expect(content, contains('[model_providers.xworkmate]'));
      expect(content, contains('model = "gpt-4.1"'));
      expect(content, contains('policy = "suggest"'));
      expect(content, contains('mode = "workspace-write"'));
    });

    test('configureAuth creates auth.json', () async {
      await bridge.configureAuth(
        accessToken: 'test-access-token',
        refreshToken: 'test-refresh-token',
        email: 'test@example.com',
        plan: 'pro',
      );

      final authFile = File('${tempDir.path}/auth.json');
      expect(await authFile.exists(), isTrue);

      final content = await authFile.readAsString();
      expect(content, contains('test-access-token'));
      expect(content, contains('test-refresh-token'));
      expect(content, contains('test@example.com'));
      expect(content, contains('pro'));
    });

    test('configureMcpServers appends MCP config', () async {
      await bridge.configureForGateway(
        gatewayUrl: 'https://api.example.com/v1',
        apiKey: 'test-key',
      );

      await bridge.configureMcpServers(
        servers: [
          CodexMcpServer(
            name: 'test-server',
            command: 'test-mcp',
            args: ['--port', '8080'],
            env: {'TEST': 'value'},
          ),
        ],
        append: true,
      );

      final configFile = File('${tempDir.path}/config.toml');
      final content = await configFile.readAsString();

      expect(content, contains('[mcp_servers.test-server]'));
      expect(content, contains('command = "test-mcp"'));
      expect(content, contains('[mcp_servers.test-server.env]'));
      expect(content, contains('TEST = "value"'));
    });

    test('hasConfig returns correct value', () async {
      expect(await bridge.hasConfig(), isFalse);

      await bridge.configureForGateway(
        gatewayUrl: 'https://api.example.com/v1',
        apiKey: 'test-key',
      );

      expect(await bridge.hasConfig(), isTrue);
    });

    test('clearConfig removes configuration directory', () async {
      await bridge.configureForGateway(
        gatewayUrl: 'https://api.example.com/v1',
        apiKey: 'test-key',
      );

      expect(await Directory(tempDir.path).exists(), isTrue);

      await bridge.clearConfig();

      expect(await Directory(tempDir.path).exists(), isFalse);
    });

    test('readProviderConfig parses existing config', () async {
      await bridge.configureForGateway(
        gatewayUrl: 'https://api.example.com/v1',
        apiKey: 'test-key',
        providerName: 'my-provider',
      );

      final config = await bridge.readProviderConfig('my-provider');

      expect(config, isNotNull);
      expect(config!['name'], equals('XWorkmate AI Gateway'));
      expect(config['base_url'], equals('https://api.example.com/v1'));
    });

    test('readProviderConfig returns null for missing provider', () async {
      final config = await bridge.readProviderConfig('nonexistent');
      expect(config, isNull);
    });
  });
}
