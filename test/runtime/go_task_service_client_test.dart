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

  group('GoTaskService ACP mapping', () {
    test('request maps skills, attachments, and provider into ACP params', () {
      const request = GoTaskServiceRequest(
        sessionId: 'session-1',
        threadId: 'thread-1',
        target: AssistantExecutionTarget.singleAgent,
        prompt: 'hello world',
        workingDirectory: '/tmp/workspace',
        model: 'codex-sonnet',
        thinking: 'medium',
        selectedSkills: <String>['PPT', 'Browser Automation'],
        inlineAttachments: <GatewayChatAttachmentPayload>[
          GatewayChatAttachmentPayload(
            type: 'inline',
            fileName: 'note.txt',
            mimeType: 'text/plain',
            content: 'aGVsbG8=',
          ),
        ],
        localAttachments: <CollaborationAttachment>[
          CollaborationAttachment(
            name: 'spec.md',
            path: '/tmp/workspace/spec.md',
            description: 'workspace spec',
          ),
        ],
        aiGatewayBaseUrl: 'https://gateway.example.com',
        aiGatewayApiKey: 'secret',
        agentId: '',
        metadata: <String, dynamic>{},
        routing: ExternalCodeAgentAcpRoutingConfig.auto(
          preferredGatewayTarget: 'local',
          availableSkills: <ExternalCodeAgentAcpAvailableSkill>[
            ExternalCodeAgentAcpAvailableSkill(
              id: 'pptx',
              label: 'PPTX',
              description: 'deck skill',
            ),
          ],
        ),
        provider: SingleAgentProvider.opencode,
      );

      final params = request.toExternalAcpParams();

      expect(params['sessionId'], 'session-1');
      expect(params['threadId'], 'thread-1');
      expect(params['mode'], 'single-agent');
      expect(params['workingDirectory'], '/tmp/workspace');
      expect(params['provider'], 'opencode');
      expect(params['model'], 'codex-sonnet');
      expect(params['thinking'], 'medium');
      expect(params['selectedSkills'], <String>['PPT', 'Browser Automation']);
      expect(params['attachments'], <Map<String, dynamic>>[
        <String, dynamic>{
          'name': 'spec.md',
          'description': 'workspace spec',
          'path': '/tmp/workspace/spec.md',
        },
        <String, dynamic>{
          'name': 'note.txt',
          'description': 'text/plain',
          'path': '',
        },
      ]);
      expect(params['inlineAttachments'], <Map<String, dynamic>>[
        <String, dynamic>{
          'name': 'note.txt',
          'mimeType': 'text/plain',
          'content': 'aGVsbG8=',
          'sizeBytes': 5,
        },
      ]);
      expect(params['routing'], <String, dynamic>{
        'routingMode': 'auto',
        'preferredGatewayTarget': 'local',
        'explicitSkills': const <String>[],
        'allowSkillInstall': false,
        'availableSkills': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'pptx',
            'label': 'PPTX',
            'description': 'deck skill',
            'installed': true,
          },
        ],
      });
    });

    test('request synthesizes routing when caller omits it', () {
      const request = GoTaskServiceRequest(
        sessionId: 'session-implicit-routing',
        threadId: 'thread-implicit-routing',
        target: AssistantExecutionTarget.singleAgent,
        prompt: 'hello world',
        workingDirectory: '/tmp/workspace',
        model: 'codex-sonnet',
        thinking: '',
        selectedSkills: <String>['PPTX'],
        inlineAttachments: <GatewayChatAttachmentPayload>[],
        localAttachments: <CollaborationAttachment>[],
        aiGatewayBaseUrl: '',
        aiGatewayApiKey: '',
        agentId: '',
        metadata: <String, dynamic>{},
        provider: SingleAgentProvider.opencode,
      );

      final params = request.toExternalAcpParams();

      expect(params['routing'], <String, dynamic>{
        'routingMode': 'explicit',
        'preferredGatewayTarget': 'local',
        'explicitExecutionTarget': 'singleAgent',
        'explicitProviderId': 'opencode',
        'explicitModel': 'codex-sonnet',
        'explicitSkills': const <String>['PPTX'],
        'allowSkillInstall': false,
        'availableSkills': const <Map<String, dynamic>>[],
      });
    });

    test(
      'request keeps gateway ACP compatibility while controller semantics stay route-based',
      () {
        const request = GoTaskServiceRequest(
          sessionId: 'session-2',
          threadId: 'thread-2',
          target: AssistantExecutionTarget.local,
          prompt: 'search latest news',
          workingDirectory: '/tmp/workspace',
          model: '',
          thinking: '',
          selectedSkills: <String>[],
          inlineAttachments: <GatewayChatAttachmentPayload>[],
          localAttachments: <CollaborationAttachment>[],
          aiGatewayBaseUrl: '',
          aiGatewayApiKey: '',
          agentId: 'agent-1',
          metadata: <String, dynamic>{'source': 'test'},
        );

        final params = request.toExternalAcpParams();

        expect(request.routingExecutionTarget, 'gateway');
        expect(params['mode'], 'gateway-chat');
        expect(params['executionTarget'], 'local');
        expect(params['agentId'], 'agent-1');
        expect(params['routing'], <String, dynamic>{
          'routingMode': 'explicit',
          'preferredGatewayTarget': 'local',
          'explicitExecutionTarget': 'local',
          'explicitSkills': const <String>[],
          'allowSkillInstall': false,
          'availableSkills': const <Map<String, dynamic>>[],
        });
      },
    );

    test(
      'run result prefers completion text and preserves resolved workspace',
      () {
        final result = goTaskServiceResultFromAcpResponse(
          <String, dynamic>{
            'result': <String, dynamic>{
              'success': true,
              'turnId': 'turn-7',
              'summary': 'summary text',
              'resolvedModel': 'codex-sonnet',
              'resolvedWorkingDirectory': '/tmp/thread',
              'resolvedWorkspaceRefKind': 'remotePath',
            },
          },
          route: GoTaskServiceRoute.externalAcpSingle,
          streamedText: 'partial output',
          completedMessage: 'final output',
        );

        expect(result.success, isTrue);
        expect(result.turnId, 'turn-7');
        expect(result.message, 'final output');
        expect(result.resolvedModel, 'codex-sonnet');
        expect(result.resolvedWorkingDirectory, '/tmp/thread');
        expect(result.resolvedWorkspaceRefKind, WorkspaceRefKind.remotePath);
      },
    );

    test('session update recognizes delta notifications', () {
      final update = goTaskServiceUpdateFromAcpNotification(<String, dynamic>{
        'method': 'session.update',
        'params': <String, dynamic>{
          'sessionId': 'session-2',
          'threadId': 'thread-2',
          'turnId': 'turn-2',
          'type': 'delta',
          'delta': 'hello',
          'pending': true,
        },
      });

      expect(update, isNotNull);
      expect(update!.sessionId, 'session-2');
      expect(update.threadId, 'thread-2');
      expect(update.turnId, 'turn-2');
      expect(update.isDelta, isTrue);
      expect(update.text, 'hello');
      expect(update.pending, isTrue);
    });
  });
}
