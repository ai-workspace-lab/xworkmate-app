import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/external_code_agent_acp_desktop_transport.dart';
import 'package:xworkmate/runtime/gateway_acp_client.dart';
import 'package:xworkmate/runtime/go_task_service_client.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

class _FakeGatewayAcpClient extends GatewayAcpClient {
  _FakeGatewayAcpClient() : super(endpointResolver: () => null);

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
    if (method == 'acp.capabilities') {
      return <String, dynamic>{
        'result': <String, dynamic>{
          'singleAgent': true,
          'multiAgent': true,
          'providerCatalog': <Map<String, dynamic>>[
            <String, dynamic>{'providerId': 'codex', 'label': 'Codex'},
            <String, dynamic>{'providerId': 'opencode', 'label': 'OpenCode'},
            <String, dynamic>{'providerId': 'gemini', 'label': 'Gemini'},
          ],
          'gatewayProviders': <Map<String, dynamic>>[
            <String, dynamic>{'providerId': 'local', 'label': 'Local Gateway'},
            <String, dynamic>{
              'providerId': 'openclaw',
              'label': 'OpenClaw Gateway',
            },
          ],
        },
      };
    }
    if (method == 'xworkmate.routing.resolve') {
      return <String, dynamic>{
        'result': <String, dynamic>{
          'resolvedExecutionTarget': 'single-agent',
          'resolvedEndpointTarget': 'singleAgent',
          'resolvedProviderId': 'gemini',
          'resolvedGatewayProviderId': 'local',
          'resolvedModel': 'gemini-2.5-pro',
          'resolvedSkills': <String>['pptx'],
          'unavailable': false,
        },
      };
    }
    return <String, dynamic>{'result': <String, dynamic>{}};
  }
}

void main() {
  group('ExternalCodeAgentAcpDesktopTransport', () {
    test(
      'reads bridge capabilities without pushing an empty provider sync',
      () async {
        final client = _FakeGatewayAcpClient();
        final transport = ExternalCodeAgentAcpDesktopTransport(
          client: client,
          endpointResolver: (_) => null,
        );

        final capabilities = await transport.loadExternalAcpCapabilities(
          target: AssistantExecutionTarget.singleAgent,
        );

        expect(client.methods, <String>['acp.capabilities']);
        expect(
          capabilities.providerCatalog.map((item) => item.providerId).toList(),
          <String>['codex', 'opencode', 'gemini'],
        );
        expect(
          capabilities.gatewayProviders
              .map((item) => item['providerId']?.toString())
              .toList(),
          <String>['local', 'openclaw'],
        );
      },
    );

    test(
      'uses bridge routing resolve for preflight provider selection',
      () async {
        final client = _FakeGatewayAcpClient();
        final transport = ExternalCodeAgentAcpDesktopTransport(
          client: client,
          endpointResolver: (_) => null,
        );

        final resolution = await transport.resolveExternalAcpRouting(
          taskPrompt: 'make slides',
          workingDirectory: '/tmp/workspace',
          routing: const ExternalCodeAgentAcpRoutingConfig.auto(
            preferredGatewayTarget: 'gateway',
          ),
        );

        expect(client.methods, <String>['xworkmate.routing.resolve']);
        expect(resolution.resolvedExecutionTarget, 'single-agent');
        expect(resolution.resolvedEndpointTarget, 'singleAgent');
        expect(resolution.resolvedProviderId, 'gemini');
        expect(resolution.resolvedGatewayProviderId, 'local');
        expect(resolution.resolvedModel, 'gemini-2.5-pro');
        expect(resolution.resolvedSkills, <String>['pptx']);
      },
    );
  });
}
