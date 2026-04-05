@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/go_agent_core_client.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

void main() {
  group('GoAgentCore client mapping', () {
    test('session request maps skills, attachments, and provider into ACP', () {
      const request = GoAgentCoreSessionRequest(
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
        routing: GoAgentCoreRoutingConfig.auto(
          preferredGatewayTarget: 'local',
          availableSkills: <GoAgentCoreAvailableSkill>[
            GoAgentCoreAvailableSkill(
              id: 'pptx',
              label: 'PPTX',
              description: 'deck skill',
            ),
          ],
        ),
        provider: SingleAgentProvider.opencode,
      );

      final params = request.toAcpParams();

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

    test('session request synthesizes routing when caller omits it', () {
      const request = GoAgentCoreSessionRequest(
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

      final params = request.toAcpParams();

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

    test('routing execution target uses gateway while session mode stays compatible', () {
      const request = GoAgentCoreSessionRequest(
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
        provider: SingleAgentProvider.auto,
      );

      final params = request.toAcpParams();

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
    });

    test(
      'run result prefers completion text and preserves resolved workspace',
      () {
        final result = goAgentCoreRunResultFromResponse(
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
      final update = goAgentCoreUpdateFromNotification(<String, dynamic>{
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
