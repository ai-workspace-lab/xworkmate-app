import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/device_identity_store.dart';
import 'package:xworkmate/runtime/gateway_runtime.dart';
import 'package:xworkmate/runtime/go_task_service_client.dart';
import 'package:xworkmate/runtime/go_task_service_desktop_service.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';

class _FakeGatewayRuntime extends GatewayRuntime {
  _FakeGatewayRuntime()
    : super(
        store: SecureConfigStore(),
        identityStore: DeviceIdentityStoreForTest(),
      );
}

class DeviceIdentityStoreForTest extends DeviceIdentityStore {
  DeviceIdentityStoreForTest() : super(SecureConfigStore());
}

class _FakeExternalAcpTransport implements ExternalCodeAgentAcpTransport {
  int executeCalls = 0;
  int cancelCalls = 0;
  GoTaskServiceRequest? lastRequest;

  @override
  Future<void> syncExternalProviders(
    List<ExternalCodeAgentAcpSyncedProvider> providers,
  ) async {}

  @override
  Future<ExternalCodeAgentAcpCapabilities> loadExternalAcpCapabilities({
    required AssistantExecutionTarget target,
    bool forceRefresh = false,
  }) async {
    return const ExternalCodeAgentAcpCapabilities.empty();
  }

  @override
  Future<GoTaskServiceResult> executeTask(
    GoTaskServiceRequest request, {
    required void Function(GoTaskServiceUpdate update) onUpdate,
  }) async {
    executeCalls += 1;
    lastRequest = request;
    onUpdate(
      GoTaskServiceUpdate(
        sessionId: request.sessionId,
        threadId: request.threadId,
        turnId: 'turn-1',
        type: 'delta',
        text: 'ACP_OK',
        message: '',
        pending: false,
        error: false,
        route: request.route,
        payload: const <String, dynamic>{'type': 'delta'},
      ),
    );
    return GoTaskServiceResult(
      success: true,
      message: 'ACP_OK',
      turnId: 'turn-1',
      raw: <String, dynamic>{},
      errorMessage: '',
      resolvedModel: '',
      route: request.route,
    );
  }

  @override
  Future<void> cancelTask({
    required AssistantExecutionTarget target,
    required String sessionId,
    required String threadId,
  }) async {
    cancelCalls += 1;
  }

  @override
  Future<void> closeTask({
    required AssistantExecutionTarget target,
    required String sessionId,
    required String threadId,
  }) async {}

  @override
  Future<void> dispose() async {}
}

GoTaskServiceRequest _request({
  required AssistantExecutionTarget target,
  bool multiAgent = false,
}) {
  return GoTaskServiceRequest(
    sessionId: 'thread-1',
    threadId: 'thread-1',
    target: target,
    prompt: 'hello',
    workingDirectory: '/tmp/workspace',
    model: '',
    thinking: 'medium',
    selectedSkills: const <String>[],
    inlineAttachments: const <GatewayChatAttachmentPayload>[],
    localAttachments: const <CollaborationAttachment>[],
    aiGatewayBaseUrl: '',
    aiGatewayApiKey: '',
    agentId: 'agent-1',
    metadata: const <String, dynamic>{'threadMode': 'test'},
    multiAgent: multiAgent,
  );
}

void main() {
  group('DesktopGoTaskService', () {
    test(
      'routes standard and multi-agent tasks through ACP transport',
      () async {
        final gateway = _FakeGatewayRuntime();
        final acp = _FakeExternalAcpTransport();
        final service = DesktopGoTaskService(
          gateway: gateway,
          acpTransport: acp,
        );

        final singleResult = await service.executeTask(
          _request(target: AssistantExecutionTarget.singleAgent),
          onUpdate: (_) {},
        );
        final gatewayResult = await service.executeTask(
          _request(target: AssistantExecutionTarget.local),
          onUpdate: (_) {},
        );
        final multiResult = await service.executeTask(
          _request(target: AssistantExecutionTarget.remote, multiAgent: true),
          onUpdate: (_) {},
        );

        expect(acp.executeCalls, 3);
        expect(singleResult.route, GoTaskServiceRoute.externalAcpSingle);
        expect(gatewayResult.route, GoTaskServiceRoute.externalAcpSingle);
        expect(multiResult.route, GoTaskServiceRoute.externalAcpMulti);
      },
    );

    test('cancel delegates to ACP transport', () async {
      final gateway = _FakeGatewayRuntime();
      final acp = _FakeExternalAcpTransport();
      final service = DesktopGoTaskService(gateway: gateway, acpTransport: acp);

      await service.cancelTask(
        route: GoTaskServiceRoute.externalAcpSingle,
        target: AssistantExecutionTarget.remote,
        sessionId: 'thread-1',
        threadId: 'thread-1',
      );

      expect(acp.cancelCalls, 1);
    });
  });
}
