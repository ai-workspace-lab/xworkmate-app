@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/agent_registry.dart';
import 'package:xworkmate/runtime/device_identity_store.dart';
import 'package:xworkmate/runtime/gateway_runtime.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';
import '../test_support.dart';

// Mock GatewayRuntime for testing
class MockGatewayRuntime extends GatewayRuntime {
  factory MockGatewayRuntime() {
    final store = createIsolatedTestStore();
    return MockGatewayRuntime._(store);
  }

  MockGatewayRuntime._(SecureConfigStore store)
    : super(store: store, identityStore: DeviceIdentityStore(store));

  final Map<String, dynamic> _responses = {};
  final List<Map<String, dynamic>> _requests = [];
  GatewayConnectionSnapshot _snapshot = GatewayConnectionSnapshot.initial();

  void setConnected(bool connected) {
    _snapshot =
        GatewayConnectionSnapshot.initial(
          mode: GatewayConnectionProfile.defaults().mode,
        ).copyWith(
          status: connected
              ? RuntimeConnectionStatus.connected
              : RuntimeConnectionStatus.offline,
          statusText: connected ? 'Connected' : 'Offline',
        );
    notifyListeners();
  }

  void setResponse(String method, Map<String, dynamic> response) {
    _responses[method] = response;
  }

  List<Map<String, dynamic>> getRequests() => List.unmodifiable(_requests);

  @override
  bool get isConnected => _snapshot.status == RuntimeConnectionStatus.connected;

  @override
  GatewayConnectionSnapshot get snapshot => _snapshot;

  @override
  Future<dynamic> request(
    String method, {
    Map<String, dynamic>? params,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    _requests.add({
      'method': method,
      'params': params ?? const <String, dynamic>{},
    });

    if (_responses.containsKey(method)) {
      return _responses[method]!;
    }

    return {'success': true};
  }

  // Stub implementations for other methods
  @override
  Future<void> initialize() async {}

  @override
  Future<void> connectProfile(
    GatewayConnectionProfile profile, {
    int? profileIndex,
    String authTokenOverride = '',
    String authPasswordOverride = '',
  }) async {}

  @override
  Future<void> disconnect({bool clearDesiredProfile = true}) async {}
}

void main() {
  group('AgentCapability', () {
    test('fromJson creates correct object', () {
      final json = {
        'name': 'code-generation',
        'description': 'Generate code',
        'parameters': {'language': 'dart'},
      };

      final capability = AgentCapability.fromJson(json);

      expect(capability.name, equals('code-generation'));
      expect(capability.description, equals('Generate code'));
      expect(capability.parameters, isNotNull);
      expect(capability.parameters!['language'], equals('dart'));
    });

    test('toJson produces correct output', () {
      final capability = AgentCapability(
        name: 'code-review',
        description: 'Review code',
      );

      final json = capability.toJson();

      expect(json['name'], equals('code-review'));
      expect(json['description'], equals('Review code'));
      expect(json.containsKey('parameters'), isFalse);
    });
  });

  group('AgentRegistration', () {
    test('fromJson creates correct object', () {
      final json = {
        'agentId': 'agent-123',
        'agentType': 'codex',
        'name': 'Test Agent',
        'version': '1.0.0',
        'token': 'test-token',
        'registeredAt': '2024-01-01T00:00:00Z',
        'expiresAt': '2025-01-01T00:00:00Z',
        'capabilities': [
          {'name': 'code-generation', 'description': 'Generate code'},
        ],
      };

      final registration = AgentRegistration.fromJson(json);

      expect(registration.agentId, equals('agent-123'));
      expect(registration.agentType, equals('codex'));
      expect(registration.name, equals('Test Agent'));
      expect(registration.version, equals('1.0.0'));
      expect(registration.token, equals('test-token'));
      expect(registration.capabilities, hasLength(1));
    });
  });

  group('AgentInfo', () {
    test('fromJson creates correct object', () {
      final json = {
        'agentId': 'agent-456',
        'agentType': 'assistant',
        'name': 'Assistant Agent',
        'status': 'active',
        'capabilities': ['code-generation', 'code-review'],
        'isOnline': true,
        'lastSeen': '2024-01-01T12:00:00Z',
      };

      final info = AgentInfo.fromJson(json);

      expect(info.agentId, equals('agent-456'));
      expect(info.agentType, equals('assistant'));
      expect(info.status, equals('active'));
      expect(info.capabilities, hasLength(2));
      expect(info.isOnline, isTrue);
    });
  });

  group('AgentRegistry', () {
    late MockGatewayRuntime mockGateway;
    late AgentRegistry registry;

    setUp(() {
      mockGateway = MockGatewayRuntime();
      registry = AgentRegistry(mockGateway);
    });

    test('initial state is not registered', () {
      expect(registry.isRegistered, isFalse);
      expect(registry.registration, isNull);
      expect(registry.agents, isEmpty);
    });

    test('register fails when gateway not connected', () async {
      mockGateway.setConnected(false);

      expect(
        () => registry.register(
          agentType: 'codex',
          name: 'Test Agent',
          version: '1.0.0',
          capabilities: [],
        ),
        throwsA(isA<AgentException>()),
      );
    });

    test('register succeeds when gateway connected', () async {
      mockGateway.setConnected(true);
      mockGateway.setResponse('agent/register', {
        'agentId': 'agent-123',
        'agentType': 'codex',
        'name': 'Test Agent',
        'version': '1.0.0',
        'token': 'test-token',
        'registeredAt': '2024-01-01T00:00:00Z',
      });

      final registration = await registry.register(
        agentType: 'codex',
        name: 'Test Agent',
        version: '1.0.0',
        transport: 'stdio-bridge',
        capabilities: [
          AgentCapability(
            name: 'code-generation',
            description: 'Generate code',
          ),
        ],
        metadata: const <String, dynamic>{
          'providerId': 'codex',
          'runtimeMode': 'externalCli',
        },
      );

      expect(registration.agentId, equals('agent-123'));
      expect(registry.isRegistered, isTrue);

      final request = mockGateway.getRequests().single;
      expect(request['params']['transport'], 'stdio-bridge');
      expect(
        request['params']['metadata'],
        containsPair('providerId', 'codex'),
      );
    });

    test('listAgents fails when gateway not connected', () async {
      mockGateway.setConnected(false);

      expect(() => registry.listAgents(), throwsA(isA<AgentException>()));
    });

    test('listAgents returns agents when gateway connected', () async {
      mockGateway.setConnected(true);
      mockGateway.setResponse('agent/list', {
        'agents': [
          {
            'agentId': 'agent-1',
            'agentType': 'codex',
            'name': 'Agent 1',
            'status': 'active',
          },
          {
            'agentId': 'agent-2',
            'agentType': 'assistant',
            'name': 'Agent 2',
            'status': 'idle',
          },
        ],
      });

      final agents = await registry.listAgents();

      expect(agents, hasLength(2));
      expect(agents[0].agentId, equals('agent-1'));
      expect(agents[1].agentId, equals('agent-2'));
    });

    test('invokeAgent sends correct request', () async {
      mockGateway.setConnected(true);
      mockGateway.setResponse('agent/invoke', {
        'content': 'Hello, world!',
        'threadId': 'thread-1',
      });

      final response = await registry.invokeAgent(
        agentId: 'agent-123',
        prompt: 'Say hello',
        context: {'key': 'value'},
      );

      expect(response.content, equals('Hello, world!'));
      expect(response.threadId, equals('thread-1'));

      final requests = mockGateway.getRequests();
      expect(requests, hasLength(1));
      expect(requests[0]['method'], equals('agent/invoke'));
      expect(requests[0]['params']['agentId'], equals('agent-123'));
    });

    test('updateStatus fails when not registered', () async {
      mockGateway.setConnected(true);

      expect(
        () => registry.updateStatus(status: 'active'),
        throwsA(isA<AgentException>()),
      );
    });

    test('syncMemory fails when gateway not connected', () async {
      mockGateway.setConnected(false);

      expect(
        () => registry.syncMemory(direction: 'pull'),
        throwsA(isA<AgentException>()),
      );
    });
  });
}
