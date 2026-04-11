import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/external_code_agent_acp_desktop_transport.dart';
import 'package:xworkmate/runtime/go_acp_stdio_bridge.dart';
import 'package:xworkmate/runtime/go_task_service_client.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

class _FakeGoAcpStdioBridge extends GoAcpStdioBridge {
  _FakeGoAcpStdioBridge();

  final List<String> methods = <String>[];
  final StreamController<Map<String, dynamic>> _notifications =
      StreamController<Map<String, dynamic>>.broadcast();

  @override
  Stream<Map<String, dynamic>> get notifications => _notifications.stream;

  @override
  Future<Map<String, dynamic>> request({
    required String method,
    required Map<String, dynamic> params,
    Duration timeout = const Duration(seconds: 120),
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
        },
      };
    }
    if (method == 'xworkmate.routing.resolve') {
      return <String, dynamic>{
        'result': <String, dynamic>{
          'resolvedExecutionTarget': 'single-agent',
          'resolvedEndpointTarget': 'singleAgent',
          'resolvedProviderId': 'gemini',
          'resolvedModel': 'gemini-2.5-pro',
          'resolvedSkills': <String>['pptx'],
          'unavailable': false,
        },
      };
    }
    return <String, dynamic>{'result': <String, dynamic>{}};
  }

  @override
  Future<void> dispose() async {
    await _notifications.close();
  }
}

void main() {
  group('ExternalCodeAgentAcpDesktopTransport', () {
    test(
      'reads bridge capabilities without pushing an empty provider sync',
      () async {
        final bridge = _FakeGoAcpStdioBridge();
        final transport = ExternalCodeAgentAcpDesktopTransport(bridge: bridge);

        final capabilities = await transport.loadExternalAcpCapabilities(
          target: AssistantExecutionTarget.singleAgent,
        );

        expect(bridge.methods, <String>['acp.capabilities']);
        expect(
          capabilities.providerCatalog.map((item) => item.providerId).toList(),
          <String>['codex', 'opencode', 'gemini'],
        );
      },
    );

    test(
      'only syncs when app has explicit provider overrides to send',
      () async {
        final bridge = _FakeGoAcpStdioBridge();
        final transport = ExternalCodeAgentAcpDesktopTransport(bridge: bridge);

        await transport
            .syncExternalProviders(const <ExternalCodeAgentAcpSyncedProvider>[
              ExternalCodeAgentAcpSyncedProvider(
                providerId: 'codex',
                label: 'Codex',
                endpoint: 'https://acp-server.svc.plus/codex/acp/rpc',
                authorizationHeader: '',
                enabled: true,
              ),
            ]);

        expect(bridge.methods, <String>['xworkmate.providers.sync']);
      },
    );

    test(
      'uses bridge routing resolve for preflight provider selection',
      () async {
        final bridge = _FakeGoAcpStdioBridge();
        final transport = ExternalCodeAgentAcpDesktopTransport(bridge: bridge);

        final resolution = await transport.resolveExternalAcpRouting(
          taskPrompt: 'make slides',
          workingDirectory: '/tmp/workspace',
          routing: const ExternalCodeAgentAcpRoutingConfig.auto(
            preferredGatewayTarget: 'local',
          ),
        );

        expect(bridge.methods, <String>['xworkmate.routing.resolve']);
        expect(resolution.resolvedProviderId, 'gemini');
        expect(resolution.resolvedModel, 'gemini-2.5-pro');
        expect(resolution.resolvedSkills, <String>['pptx']);
      },
    );
  });
}
