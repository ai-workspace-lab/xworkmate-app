import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/external_code_agent_acp_desktop_transport.dart';
import 'package:xworkmate/runtime/gateway_acp_client.dart';
import 'package:xworkmate/runtime/go_task_service_client.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

void main() {
  group('BridgeRoleRoutingCatalog', () {
    test('parses enabled roles and models from capabilities', () {
      final catalog = BridgeRoleRoutingCatalog.fromCapabilities(
        <String, dynamic>{
          'roleRouting': <String, dynamic>{
            'configured': true,
            'valid': true,
            'enabled': true,
            'policyVersion': '0.3-draft',
            'roles': <dynamic>[
              <String, dynamic>{
                'role': 'engineer',
                'enabled': true,
                'requiresWorkspace': true,
                'models': <dynamic>[
                  <String, dynamic>{
                    'key': 'gpt-6.1-sol',
                    'displayName': 'GPT 6.1 Sol',
                  },
                  <String, dynamic>{'key': 'claude-opus-5-5'},
                ],
              },
              <String, dynamic>{'role': 'researcher', 'enabled': false},
            ],
          },
        },
      );
      expect(catalog.enabled, isTrue);
      expect(catalog.policyVersion, '0.3-draft');
      expect(catalog.enabledRoles.map((role) => role.role), <String>[
        'engineer',
      ]);
      final engineer = catalog.role('engineer')!;
      expect(engineer.requiresWorkspace, isTrue);
      expect(engineer.models.map((model) => model.label), <String>[
        'GPT 6.1 Sol',
        'claude-opus-5-5',
      ]);
    });

    test('is unavailable without a policy or with an invalid one', () {
      expect(
        BridgeRoleRoutingCatalog.fromCapabilities(<String, dynamic>{}).enabled,
        isFalse,
      );
      final invalid = BridgeRoleRoutingCatalog.fromCapabilities(
        <String, dynamic>{
          'roleRouting': <String, dynamic>{
            'configured': true,
            'valid': false,
            'enabled': true,
            'error': 'role policy: version is required',
          },
        },
      );
      expect(invalid.enabled, isFalse);
      expect(invalid.error, contains('version'));
    });
  });

  group('RoleRoutingSelection', () {
    test('maps auto and manual choices onto bridge routing fields', () {
      expect(RoleRoutingSelection.off.toRoutingJson(), isEmpty);
      expect(
        const RoleRoutingSelection(mode: RoleRoutingMode.auto).toRoutingJson(),
        <String, dynamic>{'roleMode': 'auto'},
      );
      expect(
        const RoleRoutingSelection(
          mode: RoleRoutingMode.manual,
          role: 'engineer',
        ).toRoutingJson(),
        <String, dynamic>{'roleMode': 'auto', 'role': 'engineer'},
      );
      expect(
        const RoleRoutingSelection(
          mode: RoleRoutingMode.manual,
          role: 'engineer',
          modelKey: 'gpt-6.1-sol',
        ).toRoutingJson(),
        <String, dynamic>{
          'roleMode': 'manual',
          'role': 'engineer',
          'roleModel': 'gpt-6.1-sol',
        },
      );
    });

    test('request params carry role routing inside routing', () {
      final params = _request(
        roleRouting: const RoleRoutingSelection(
          mode: RoleRoutingMode.manual,
          role: 'engineer',
          modelKey: 'gpt-6.1-sol',
        ),
      ).toExternalAcpParams();
      final routing = params['routing'] as Map<String, dynamic>;
      expect(routing['role'], 'engineer');
      expect(routing['roleMode'], 'manual');
      expect(routing['roleModel'], 'gpt-6.1-sol');
      expect(routing['routingMode'], isNotEmpty);

      final plain = _request().toExternalAcpParams();
      expect(
        (plain['routing'] as Map<String, dynamic>).containsKey('roleMode'),
        isFalse,
      );
    });
  });

  group('RoleTaskEvent', () {
    test('parses a permission prompt from a task update', () {
      final event = RoleTaskEvent.fromUpdatePayloadOrNull(<String, dynamic>{
        'type': 'task',
        'event': 'task.permission_requested',
        'task': <String, dynamic>{
          'phase': 'permission_requested',
          'role': 'engineer',
          'providerId': 'opencode-acp',
          'modelId': 'gpt-6.1-sol',
          'detail': <String, dynamic>{
            'requestId': 'perm-1',
            'sessionId': 'session-1',
            'toolCall': <String, dynamic>{
              'title': 'write main.go',
              'kind': 'edit',
            },
            'options': <dynamic>[
              <String, dynamic>{
                'optionId': 'allow-once',
                'name': 'Allow',
                'kind': 'allow_once',
              },
              <String, dynamic>{
                'optionId': 'reject-once',
                'name': 'Reject',
                'kind': 'reject_once',
              },
            ],
          },
        },
      })!;
      expect(event.status.role, 'engineer');
      expect(event.status.modelId, 'gpt-6.1-sol');
      final permission = event.permission!;
      expect(permission.title, 'write main.go');
      expect(permission.options.map((option) => option.allows), <bool>[
        true,
        false,
      ]);
    });

    test('ignores non-task updates and marks terminal phases', () {
      expect(
        RoleTaskEvent.fromUpdatePayloadOrNull(<String, dynamic>{
          'type': 'delta',
        }),
        isNull,
      );
      final rejected = RoleTaskEvent.fromUpdatePayloadOrNull(<String, dynamic>{
        'type': 'task',
        'task': <String, dynamic>{
          'phase': 'rejected',
          'detail': <String, dynamic>{
            'role': 'engineer',
            'message': 'no candidate passed the hard gates',
          },
        },
      })!;
      expect(rejected.status.terminal, isTrue);
      expect(rejected.status.role, 'engineer');
      expect(rejected.status.message, contains('hard gates'));
    });
  });

  group('ExternalCodeAgentAcpDesktopTransport.respondPermission', () {
    test('sends the chosen option or an explicit deny', () async {
      final client = _RecordingGatewayAcpClient();
      final transport = ExternalCodeAgentAcpDesktopTransport(
        client: client,
        endpointResolver: (_) => Uri.parse('https://bridge.example/acp/rpc'),
      );
      await transport.respondPermission(
        target: AssistantExecutionTarget.agent,
        sessionId: 'session-1',
        requestId: 'perm-1',
        optionId: 'allow-once',
      );
      await transport.respondPermission(
        target: AssistantExecutionTarget.agent,
        sessionId: 'session-1',
        requestId: 'perm-2',
      );
      expect(client.methods, <String>[
        'xworkmate.permissions.respond',
        'xworkmate.permissions.respond',
      ]);
      expect(client.params[0], <String, dynamic>{
        'sessionId': 'session-1',
        'requestId': 'perm-1',
        'optionId': 'allow-once',
      });
      expect(client.params[1], <String, dynamic>{
        'sessionId': 'session-1',
        'requestId': 'perm-2',
        'decision': 'cancel',
      });
    });
  });
}

GoTaskServiceRequest _request({
  RoleRoutingSelection roleRouting = RoleRoutingSelection.off,
}) {
  return GoTaskServiceRequest(
    sessionId: 'session-1',
    threadId: 'session-1',
    target: AssistantExecutionTarget.agent,
    prompt: 'fix the failing test',
    workingDirectory: '/srv/workspace/demo',
    model: '',
    thinking: 'off',
    selectedSkills: const <String>[],
    inlineAttachments: const <GatewayChatAttachmentPayload>[],
    localAttachments: const <CollaborationAttachment>[],
    agentId: '',
    metadata: const <String, dynamic>{},
    roleRouting: roleRouting,
  );
}

class _RecordingGatewayAcpClient extends GatewayAcpClient {
  _RecordingGatewayAcpClient()
    : super(endpointResolver: () => Uri.parse('https://bridge.example'));

  final List<String> methods = <String>[];
  final List<Map<String, dynamic>> params = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>> request({
    required String method,
    required Map<String, dynamic> params,
    void Function(Map<String, dynamic>)? onNotification,
    Uri? endpointOverride,
    String authorizationOverride = '',
  }) async {
    methods.add(method);
    this.params.add(params);
    return <String, dynamic>{
      'result': <String, dynamic>{'accepted': true},
    };
  }
}
