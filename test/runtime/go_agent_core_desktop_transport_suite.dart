@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/gateway_acp_client.dart';
import 'package:xworkmate/runtime/go_agent_core_client.dart';
import 'package:xworkmate/runtime/go_agent_core_desktop_transport.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

void main() {
  group('GoAgentCoreDesktopTransport', () {
    test('uses resolved gateway endpoint for local gateway sessions', () async {
      final server = await _AcpFakeServer.start();
      addTearDown(server.close);

      final transport = GoAgentCoreDesktopTransport(
        acpClient: GatewayAcpClient(endpointResolver: () => null),
        endpointResolver: (target) => switch (target) {
          AssistantExecutionTarget.local => server.baseHttpUri,
          _ => null,
        },
      );

      final result = await transport.executeSession(
        const GoAgentCoreSessionRequest(
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
        onUpdate: (_) {},
      );

      expect(result.success, isTrue);
      expect(result.message, 'gateway-ok');
      expect(server.lastHttpRequestPath, '/acp/rpc');
      expect(server.rpcMethods, contains('session.start'));
      expect(server.lastSessionMode, 'gateway-chat');
    });

    test('reports missing endpoint when gateway target cannot resolve', () async {
      final transport = GoAgentCoreDesktopTransport(
        acpClient: GatewayAcpClient(endpointResolver: () => null),
        endpointResolver: (_) => null,
      );

      await expectLater(
        () => transport.executeSession(
          const GoAgentCoreSessionRequest(
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
          onUpdate: (_) {},
        ),
        throwsA(
          isA<GatewayAcpException>().having(
            (error) => error.code,
            'code',
            'GO_AGENT_CORE_ENDPOINT_MISSING',
          ),
        ),
      );
    });
  });
}

class _AcpFakeServer {
  _AcpFakeServer._(this._server);

  final HttpServer _server;
  final List<String> rpcMethods = <String>[];
  String? lastHttpRequestPath;
  String? lastSessionMode;

  Uri get baseHttpUri => Uri.parse('http://127.0.0.1:${_server.port}');

  static Future<_AcpFakeServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = _AcpFakeServer._(server);
    unawaited(fake._listen());
    return fake;
  }

  Future<void> close() async {
    await _server.close(force: true);
  }

  Future<void> _listen() async {
    await for (final request in _server) {
      if (request.uri.path == '/acp/rpc' && request.method == 'POST') {
        lastHttpRequestPath = request.uri.path;
        await _handleHttpRpc(request);
        continue;
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    }
  }

  Future<void> _handleHttpRpc(HttpRequest request) async {
    final body = await utf8.decodeStream(request);
    final envelope = (jsonDecode(body) as Map).cast<String, dynamic>();
    final id = envelope['id'];
    final method = envelope['method']?.toString() ?? '';
    final params =
        (envelope['params'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    rpcMethods.add(method);

    request.response.headers.set(
      HttpHeaders.contentTypeHeader,
      'text/event-stream; charset=utf-8',
    );
    if (method == 'session.start' || method == 'session.message') {
      lastSessionMode = params['mode']?.toString();
      request.response.write(
        'data: ${jsonEncode(<String, dynamic>{'jsonrpc': '2.0', 'id': id, 'result': <String, dynamic>{'success': true, 'message': 'gateway-ok', 'summary': 'gateway-ok', 'turnId': 'turn-1'}})}\n\n',
      );
      await request.response.close();
      return;
    }
    request.response.write(
      'data: ${jsonEncode(<String, dynamic>{'jsonrpc': '2.0', 'id': id, 'result': <String, dynamic>{'singleAgent': true, 'multiAgent': true, 'providers': <String>['codex'], 'capabilities': <String, dynamic>{'single_agent': true, 'multi_agent': true, 'providers': <String>['codex']}}})}\n\n',
    );
    await request.response.close();
  }
}
