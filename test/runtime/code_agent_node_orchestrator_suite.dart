@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/code_agent_node_orchestrator.dart';
import 'package:xworkmate/runtime/codex_runtime.dart';
import 'package:xworkmate/runtime/device_identity_store.dart';
import 'package:xworkmate/runtime/gateway_runtime.dart';
import 'package:xworkmate/runtime/runtime_dispatch_resolver.dart';
import 'package:xworkmate/runtime/runtime_coordinator.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';
import '../test_support.dart';

class _FakeGatewayRuntime extends GatewayRuntime {
  factory _FakeGatewayRuntime() {
    final store = createIsolatedTestStore();
    return _FakeGatewayRuntime._(store);
  }

  _FakeGatewayRuntime._(SecureConfigStore store)
    : super(store: store, identityStore: DeviceIdentityStore(store));

  @override
  Future<void> connectProfile(
    GatewayConnectionProfile profile, {
    int? profileIndex,
    String authTokenOverride = '',
    String authPasswordOverride = '',
  }) async {}

  @override
  Future<void> disconnect({bool clearDesiredProfile = true}) async {}

  @override
  Future<dynamic> request(
    String method, {
    Map<String, dynamic>? params,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    return <String, dynamic>{};
  }
}

class _FakeCodexRuntime extends CodexRuntime {}

class _FakeDispatchResolver implements RuntimeDispatchResolver {
  _FakeDispatchResolver(this.resolution);

  final RuntimeDispatchResolution resolution;

  @override
  Future<String?> selectProviderId({
    required List<ExternalCodeAgentProvider> providers,
    String preferredProviderId = '',
    Iterable<String> requiredCapabilities = const <String>[],
  }) async {
    return resolution.providerId;
  }

  @override
  Future<RuntimeDispatchResolution> resolveGatewayDispatch({
    required List<ExternalCodeAgentProvider> providers,
    required String preferredProviderId,
    required Iterable<String> requiredCapabilities,
    required Map<String, dynamic> nodeState,
    required Map<String, dynamic> nodeInfo,
  }) async {
    return resolution;
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  group('CodeAgentNodeOrchestrator', () {
    late RuntimeCoordinator coordinator;
    late CodeAgentNodeOrchestrator orchestrator;

    setUp(() {
      coordinator = RuntimeCoordinator(
        gateway: _FakeGatewayRuntime(),
        codex: _FakeCodexRuntime(),
      );
      orchestrator = CodeAgentNodeOrchestrator(coordinator);
    });

    test('builds cooperative node metadata for an external provider', () async {
      coordinator.registerExternalCodeAgent(
        const ExternalCodeAgentProvider(
          id: 'codex',
          name: 'Codex CLI',
          command: 'codex',
          defaultArgs: <String>['app-server', '--listen', 'stdio://'],
          capabilities: <String>['chat', 'code-edit', 'gateway-bridge'],
        ),
      );

      final dispatch = await orchestrator.buildGatewayDispatch(
        const CodeAgentNodeState(
          selectedAgentId: 'main',
          gatewayConnected: true,
          executionTarget: AssistantExecutionTarget.local,
          runtimeMode: CodeAgentRuntimeMode.externalCli,
          bridgeEnabled: true,
          bridgeState: 'registered',
          preferredProviderId: 'codex',
          resolvedCodexCliPath: '/opt/homebrew/bin/codex',
        ),
      );

      expect(dispatch.agentId, 'main');
      expect(
        dispatch.metadata['node'],
        containsPair('kind', 'app-mediated-cooperative-node'),
      );
      expect(
        dispatch.metadata['dispatch'],
        containsPair('mode', 'cooperative'),
      );
      expect(
        dispatch.metadata['bridge'],
        containsPair('localTransport', 'stdio-jsonrpc'),
      );
      expect(dispatch.metadata['provider'], containsPair('id', 'codex'));
      expect(
        (dispatch.metadata['provider'] as Map<String, dynamic>).containsKey(
          'command',
        ),
        isFalse,
      );
    });

    test('omits provider metadata when bridge is disabled', () async {
      coordinator.registerExternalCodeAgent(
        const ExternalCodeAgentProvider(
          id: 'codex',
          name: 'Codex CLI',
          command: 'codex',
          capabilities: <String>['gateway-bridge'],
        ),
      );

      final dispatch = await orchestrator.buildGatewayDispatch(
        const CodeAgentNodeState(
          selectedAgentId: '',
          gatewayConnected: true,
          executionTarget: AssistantExecutionTarget.remote,
          runtimeMode: CodeAgentRuntimeMode.externalCli,
          bridgeEnabled: false,
          bridgeState: 'notStarted',
          preferredProviderId: 'codex',
        ),
      );

      expect(dispatch.agentId, isNull);
      expect(
        dispatch.metadata['dispatch'],
        containsPair('mode', 'gateway-only'),
      );
      expect(dispatch.metadata.containsKey('provider'), isFalse);
    });

    test('uses dispatch resolver metadata when available', () async {
      coordinator.attachDispatchResolver(
        _FakeDispatchResolver(
          const RuntimeDispatchResolution(
            agentId: 'main',
            providerId: 'codex',
            metadata: <String, dynamic>{
              'dispatch': <String, dynamic>{
                'mode': 'cooperative',
                'executionTarget': 'local',
              },
              'provider': <String, dynamic>{'id': 'codex'},
            },
          ),
        ),
      );

      final dispatch = await orchestrator.buildGatewayDispatch(
        const CodeAgentNodeState(
          selectedAgentId: 'main',
          gatewayConnected: true,
          executionTarget: AssistantExecutionTarget.local,
          runtimeMode: CodeAgentRuntimeMode.externalCli,
          bridgeEnabled: true,
          bridgeState: 'registered',
          preferredProviderId: 'codex',
        ),
      );

      expect(dispatch.agentId, 'main');
      expect(
        dispatch.metadata['dispatch'],
        containsPair('mode', 'cooperative'),
      );
      expect(dispatch.metadata['provider'], containsPair('id', 'codex'));
    });
  });
}
