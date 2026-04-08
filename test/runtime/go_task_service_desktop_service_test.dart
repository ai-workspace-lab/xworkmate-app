import 'dart:async';

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

  final StreamController<GatewayPushEvent> controller =
      StreamController<GatewayPushEvent>.broadcast();
  final List<Map<String, Object?>> sendChatCalls = <Map<String, Object?>>[];
  final List<Map<String, String>> abortChatCalls = <Map<String, String>>[];
  List<GatewayChatMessage> history = const <GatewayChatMessage>[];

  @override
  Stream<GatewayPushEvent> get events => controller.stream;

  @override
  bool get isConnected => true;

  @override
  Future<String> sendChat({
    required String sessionKey,
    required String message,
    required String thinking,
    List<GatewayChatAttachmentPayload> attachments =
        const <GatewayChatAttachmentPayload>[],
    String? agentId,
    Map<String, dynamic>? metadata,
  }) async {
    sendChatCalls.add(<String, Object?>{
      'sessionKey': sessionKey,
      'message': message,
      'thinking': thinking,
      'agentId': agentId,
      'metadata': metadata,
    });
    return 'run-1';
  }

  @override
  Future<void> abortChat({required String sessionKey, required String runId}) async {
    abortChatCalls.add(<String, String>{
      'sessionKey': sessionKey,
      'runId': runId,
    });
  }

  @override
  Future<List<GatewayChatMessage>> loadHistory(
    String sessionKey, {
    int limit = 120,
  }) async {
    return history;
  }
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
        route: GoTaskServiceRoute.externalAcpSingle,
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
    test('routes OpenClaw tasks through GatewayRuntime', () async {
      final gateway = _FakeGatewayRuntime();
      final acp = _FakeExternalAcpTransport();
      final service = DesktopGoTaskService(gateway: gateway, acpTransport: acp);

      final updates = <GoTaskServiceUpdate>[];
      final future = service.executeTask(
        _request(target: AssistantExecutionTarget.local),
        onUpdate: updates.add,
      );

      await Future<void>.delayed(Duration.zero);
      gateway.controller.add(
        GatewayPushEvent(
          event: 'chat',
          payload: <String, dynamic>{
            'runId': 'run-1',
            'sessionKey': 'thread-1',
            'state': 'final',
            'message': <String, dynamic>{
              'role': 'assistant',
              'content': <Map<String, dynamic>>[
                <String, dynamic>{'type': 'text', 'text': 'OPENCLAW_OK'},
              ],
            },
          },
        ),
      );

      final result = await future;

      expect(acp.executeCalls, 0);
      expect(gateway.sendChatCalls, hasLength(1));
      expect(gateway.sendChatCalls.single['metadata'], isNull);
      expect(result.route, GoTaskServiceRoute.openClawTask);
      expect(result.message, 'OPENCLAW_OK');
      expect(updates.last.route, GoTaskServiceRoute.openClawTask);
    });

    test('routes single-agent and multi-agent tasks through ACP transport', () async {
      final gateway = _FakeGatewayRuntime();
      final acp = _FakeExternalAcpTransport();
      final service = DesktopGoTaskService(gateway: gateway, acpTransport: acp);

      final singleResult = await service.executeTask(
        _request(target: AssistantExecutionTarget.singleAgent),
        onUpdate: (_) {},
      );
      final multiResult = await service.executeTask(
        _request(
          target: AssistantExecutionTarget.remote,
          multiAgent: true,
        ),
        onUpdate: (_) {},
      );

      expect(gateway.sendChatCalls, isEmpty);
      expect(acp.executeCalls, 2);
      expect(singleResult.route, GoTaskServiceRoute.externalAcpSingle);
      expect(multiResult.route, GoTaskServiceRoute.externalAcpMulti);
    });

    test(
      'recovers OpenClaw task completion from chat history when push events do not arrive',
      () async {
        final gateway = _FakeGatewayRuntime();
        final acp = _FakeExternalAcpTransport();
        final service = DesktopGoTaskService(gateway: gateway, acpTransport: acp);

        unawaited(
          Future<void>.delayed(const Duration(milliseconds: 1200), () {
            gateway.history = <GatewayChatMessage>[
              GatewayChatMessage(
                id: 'assistant-1',
                role: 'assistant',
                text: 'RECOVERED_FROM_HISTORY',
                timestampMs: 2,
                toolCallId: null,
                toolName: null,
                stopReason: null,
                pending: false,
                error: false,
              ),
            ];
          }),
        );

        final result = await service.executeTask(
          _request(target: AssistantExecutionTarget.local),
          onUpdate: (_) {},
        );

        expect(result.route, GoTaskServiceRoute.openClawTask);
        expect(result.message, 'RECOVERED_FROM_HISTORY');
        expect(result.raw['recoveredFromHistory'], isTrue);
      },
    );
  });
}
