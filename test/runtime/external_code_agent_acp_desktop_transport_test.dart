@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/external_code_agent_acp_desktop_transport.dart';
import 'package:xworkmate/runtime/go_acp_stdio_bridge.dart';
import 'package:xworkmate/runtime/go_task_service_client.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

void main() {
  group('ExternalCodeAgentAcpDesktopTransport', () {
    test('uses direct Go ACP stdio bridge for desktop task execution', () async {
      late final _FakeGoAcpStdioBridge bridge;
      bridge = _FakeGoAcpStdioBridge(
        handler: (method, params) async {
          switch (method) {
            case 'acp.capabilities':
              return <String, dynamic>{
                'jsonrpc': '2.0',
                'id': 'capabilities',
                'result': <String, dynamic>{
                  'singleAgent': true,
                  'multiAgent': true,
                  'providers': <String>['codex'],
                  'capabilities': <String, dynamic>{
                    'single_agent': true,
                    'multi_agent': true,
                    'providers': <String>['codex'],
                  },
                },
              };
            case 'xworkmate.providers.sync':
              return <String, dynamic>{
                'jsonrpc': '2.0',
                'id': 'sync',
                'result': <String, dynamic>{'ok': true},
              };
            case 'session.start':
              bridge.emit(<String, dynamic>{
                'jsonrpc': '2.0',
                'method': 'session.update',
                'params': <String, dynamic>{
                  'sessionId': 'session-local',
                  'threadId': 'thread-local',
                  'turnId': 'turn-1',
                  'type': 'delta',
                  'delta': 'gateway-',
                },
              });
              return <String, dynamic>{
                'jsonrpc': '2.0',
                'id': 'start',
                'result': <String, dynamic>{
                  'success': true,
                  'message': 'gateway-ok',
                  'summary': 'gateway-ok',
                  'turnId': 'turn-1',
                },
              };
          }
          throw StateError('Unexpected method: $method');
        },
      );
      final transport = ExternalCodeAgentAcpDesktopTransport(bridge: bridge);

      final updates = <GoTaskServiceUpdate>[];
      final result = await transport.executeTask(
        const GoTaskServiceRequest(
          sessionId: 'session-local',
          threadId: 'thread-local',
          target: AssistantExecutionTarget.local,
          prompt: 'ping local gateway',
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
        onUpdate: updates.add,
      );

      expect(result.success, isTrue);
      expect(result.message, 'gateway-ok');
      expect(
        bridge.recordedMethods,
        containsAll(<String>['xworkmate.providers.sync', 'session.start']),
      );
      expect(updates.single.text, 'gateway-');
    });
  });
}

class _FakeGoAcpStdioBridge extends GoAcpStdioBridge {
  _FakeGoAcpStdioBridge({required this.handler});

  final Future<Map<String, dynamic>> Function(
    String method,
    Map<String, dynamic> params,
  )
  handler;

  final StreamController<Map<String, dynamic>> _notificationsController =
      StreamController<Map<String, dynamic>>.broadcast();
  final List<String> recordedMethods = <String>[];

  @override
  Stream<Map<String, dynamic>> get notifications => _notificationsController.stream;

  void emit(Map<String, dynamic> notification) {
    _notificationsController.add(notification);
  }

  @override
  Future<Map<String, dynamic>> request({
    required String method,
    required Map<String, dynamic> params,
    Duration timeout = const Duration(seconds: 120),
  }) async {
    recordedMethods.add(method);
    return handler(method, params);
  }

  @override
  Future<void> dispose() async {
    await _notificationsController.close();
  }
}
