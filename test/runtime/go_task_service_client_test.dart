import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/go_task_service_client.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

void main() {
  group('GoTaskServiceRequest routing', () {
    GoTaskServiceRequest buildRequest({
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
        agentId: '',
        metadata: const <String, dynamic>{},
        multiAgent: multiAgent,
      );
    }

    test('routes local and remote targets to the OpenClaw lane', () {
      expect(
        buildRequest(target: AssistantExecutionTarget.local).route,
        GoTaskServiceRoute.openClawTask,
      );
      expect(
        buildRequest(target: AssistantExecutionTarget.remote).route,
        GoTaskServiceRoute.openClawTask,
      );
    });

    test('routes single-agent and auto targets to the ACP single lane', () {
      expect(
        buildRequest(target: AssistantExecutionTarget.singleAgent).route,
        GoTaskServiceRoute.externalAcpSingle,
      );
      expect(
        buildRequest(target: AssistantExecutionTarget.auto).route,
        GoTaskServiceRoute.externalAcpSingle,
      );
    });

    test('routes multi-agent requests to the ACP multi lane', () {
      expect(
        buildRequest(
          target: AssistantExecutionTarget.remote,
          multiAgent: true,
        ).route,
        GoTaskServiceRoute.externalAcpMulti,
      );
    });
  });
}
