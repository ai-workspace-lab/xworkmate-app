import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/external_code_agent_acp_desktop_transport.dart';
import 'package:xworkmate/runtime/go_acp_stdio_bridge.dart';
import 'package:xworkmate/runtime/go_task_service_client.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

class _FakeGoAcpStdioBridgeWithSyncOrder extends GoAcpStdioBridge {
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

  @override
  Future<void> dispose() async {
    await _notifications.close();
  }
}

void main() {
  group('External ACP bridge sync order', () {
    test('syncs providers before capabilities requests', () async {
      final bridge = _FakeGoAcpStdioBridgeWithSyncOrder();
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

      await transport.loadExternalAcpCapabilities(
        target: AssistantExecutionTarget.singleAgent,
      );

      expect(bridge.methods, <String>[
        'xworkmate.providers.sync',
        'xworkmate.providers.sync',
        'acp.capabilities',
      ]);
    });

    test('syncs providers before session start requests', () async {
      final bridge = _FakeGoAcpStdioBridgeWithSyncOrder();
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
          aiGatewayBaseUrl: '',
          aiGatewayApiKey: '',
          agentId: '',
          metadata: <String, dynamic>{},
        ),
        onUpdate: (_) {},
      );

      expect(bridge.methods, <String>[
        'xworkmate.providers.sync',
        'xworkmate.providers.sync',
        'session.start',
      ]);
    });
  });
}
