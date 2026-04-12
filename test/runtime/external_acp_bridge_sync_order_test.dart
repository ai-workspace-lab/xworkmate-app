import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/external_code_agent_acp_desktop_transport.dart';
import 'package:xworkmate/runtime/gateway_acp_client.dart';
import 'package:xworkmate/runtime/go_task_service_client.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

class _FakeGatewayAcpClientWithSyncOrder extends GatewayAcpClient {
  _FakeGatewayAcpClientWithSyncOrder() : super(endpointResolver: () => null);

  final List<String> methods = <String>[];

  @override
  Future<Map<String, dynamic>> request({
    required String method,
    required Map<String, dynamic> params,
    void Function(Map<String, dynamic>)? onNotification,
    Uri? endpointOverride,
    String authorizationOverride = '',
  }) async {
    methods.add(method);
    return switch (method) {
      'acp.capabilities' => <String, dynamic>{
        'result': <String, dynamic>{
          'singleAgent': true,
          'multiAgent': true,
          'providers': <String>['codex'],
        },
      },
      _ => <String, dynamic>{
        'result': <String, dynamic>{
          'success': true,
          'output': 'ok',
          'resolvedExecutionTarget': 'single-agent',
        },
      },
    };
  }
}

void main() {
  group('External ACP bridge routing order', () {
    test('loads capabilities without app-side provider sync', () async {
      final client = _FakeGatewayAcpClientWithSyncOrder();
      final transport = ExternalCodeAgentAcpDesktopTransport(
        client: client,
        endpointResolver: (_) => null,
      );

      await transport.loadExternalAcpCapabilities(
        target: AssistantExecutionTarget.singleAgent,
      );

      expect(client.methods, <String>['acp.capabilities']);
    });

    test('starts sessions without app-side provider sync', () async {
      final client = _FakeGatewayAcpClientWithSyncOrder();
      final transport = ExternalCodeAgentAcpDesktopTransport(
        client: client,
        endpointResolver: (_) => null,
      );

      await transport.executeTask(
        const GoTaskServiceRequest(
          sessionId: 's1',
          threadId: 't1',
          target: AssistantExecutionTarget.singleAgent,
          prompt: 'hello',
          workingDirectory: '/tmp',
          model: '',
          thinking: '',
          selectedSkills: <String>[],
          inlineAttachments: <GatewayChatAttachmentPayload>[],
          localAttachments: <CollaborationAttachment>[],
          agentId: '',
          metadata: <String, dynamic>{},
        ),
        onUpdate: (_) {},
      );

      expect(client.methods, <String>['session.start']);
    });
  });
}
