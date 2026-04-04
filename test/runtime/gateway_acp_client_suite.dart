@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/gateway_acp_client.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

void main() {
  group('GatewayAcpClient', () {
    test('loads ACP capabilities over websocket when available', () async {
      final server = await _AcpFakeServer.start();
      addTearDown(server.close);

      final client = GatewayAcpClient(
        endpointResolver: () => server.baseHttpUri,
      );

      final capabilities = await client.loadCapabilities(forceRefresh: true);

      expect(capabilities.singleAgent, isTrue);
      expect(capabilities.multiAgent, isTrue);
      expect(capabilities.providers, contains(SingleAgentProvider.codex));
      expect(server.rpcMethods, contains('acp.capabilities'));
    });

    test('preserves prefixed websocket ACP endpoints', () async {
      final server = await _AcpFakeServer.start(pathPrefix: '/codex');
      addTearDown(server.close);

      final client = GatewayAcpClient(
        endpointResolver: () => server.baseHttpUri,
      );

      final capabilities = await client.loadCapabilities(forceRefresh: true);

      expect(capabilities.singleAgent, isTrue);
      expect(server.rpcMethods, contains('acp.capabilities'));
    });

    test('falls back to HTTP+SSE when websocket is unavailable', () async {
      final server = await _AcpFakeServer.start(disableWebSocket: true);
      addTearDown(server.close);

      final client = GatewayAcpClient(
        endpointResolver: () => server.baseHttpUri,
      );

      final capabilities = await client.loadCapabilities(forceRefresh: true);

      expect(capabilities.singleAgent, isTrue);
      expect(capabilities.multiAgent, isTrue);
      expect(capabilities.providers, contains(SingleAgentProvider.claude));
      expect(server.rpcMethods, contains('acp.capabilities'));
    });

    test('preserves prefixed HTTP fallback ACP endpoints', () async {
      final server = await _AcpFakeServer.start(
        disableWebSocket: true,
        pathPrefix: '/opencode',
      );
      addTearDown(server.close);

      final client = GatewayAcpClient(
        endpointResolver: () => server.baseHttpUri,
      );

      final capabilities = await client.loadCapabilities(forceRefresh: true);

      expect(capabilities.multiAgent, isTrue);
      expect(server.rpcMethods, contains('acp.capabilities'));
    });

    test(
      'surfaces HTTP content-type errors without raw JSON parse failures',
      () async {
        final server = await _AcpFakeServer.start(
          disableWebSocket: true,
          respondWithHtmlError: true,
        );
        addTearDown(server.close);

        final client = GatewayAcpClient(
          endpointResolver: () => server.baseHttpUri,
        );

        await expectLater(
          () => client.loadCapabilities(forceRefresh: true),
          throwsA(
            isA<GatewayAcpException>().having(
              (error) => error.toString(),
              'message',
              contains('unexpected content type: text/html'),
            ),
          ),
        );
      },
    );

    test(
      'forwards ACP authorization resolver headers over websocket',
      () async {
        final server = await _AcpFakeServer.start();
        addTearDown(server.close);

        final client = GatewayAcpClient(
          endpointResolver: () => server.baseHttpUri,
          authorizationResolver: (_) async => 'Bearer ws-secret',
        );

        await client.loadCapabilities(forceRefresh: true);

        expect(server.lastWebSocketAuthorization, 'Bearer ws-secret');
      },
    );

    test(
      'prefers explicit ACP authorization overrides on HTTP fallback',
      () async {
        final server = await _AcpFakeServer.start(disableWebSocket: true);
        addTearDown(server.close);

        final client = GatewayAcpClient(
          endpointResolver: () => server.baseHttpUri,
          authorizationResolver: (_) async => 'Bearer resolver-secret',
        );

        await client.loadCapabilities(
          forceRefresh: true,
          authorizationOverride: 'Bearer override-secret',
        );

        expect(server.lastHttpAuthorization, 'Bearer override-secret');
      },
    );

    test('preserves hosted ACP base path for websocket requests', () async {
      final server = await _AcpFakeServer.start(pathPrefix: '/opencode');
      addTearDown(server.close);

      final client = GatewayAcpClient(
        endpointResolver: () => server.baseHttpUri,
      );

      final capabilities = await client.loadCapabilities(forceRefresh: true);

      expect(capabilities.singleAgent, isTrue);
      expect(server.lastWebSocketRequestPath, '/opencode/acp');
    });

    test('preserves hosted ACP base path for HTTP fallback requests', () async {
      final server = await _AcpFakeServer.start(
        disableWebSocket: true,
        pathPrefix: '/opencode',
      );
      addTearDown(server.close);

      final client = GatewayAcpClient(
        endpointResolver: () => server.baseHttpUri,
      );

      final capabilities = await client.loadCapabilities(forceRefresh: true);

      expect(capabilities.singleAgent, isTrue);
      expect(server.lastHttpRequestPath, '/opencode/acp/rpc');
    });

    test(
      'streams multi-agent events and supports cancel/close session',
      () async {
        final server = await _AcpFakeServer.start();
        addTearDown(server.close);

        final client = GatewayAcpClient(
          endpointResolver: () => server.baseHttpUri,
        );

        final events = await client
            .runMultiAgent(
              GatewayAcpMultiAgentRequest(
                sessionId: 'session-ma',
                threadId: 'thread-ma',
                prompt: 'run multi-agent',
                workingDirectory: '/tmp',
                attachments: const <CollaborationAttachment>[],
                selectedSkills: const <String>['design'],
                aiGatewayBaseUrl: 'https://example.invalid',
                aiGatewayApiKey: 'test-key',
                resumeSession: false,
              ),
            )
            .toList();

        expect(events, isNotEmpty);
        expect(events.first.type, 'step');
        expect(events.last.type, 'result');
        expect(events.last.error, isFalse);

        await client.cancelSession(
          sessionId: 'session-ma',
          threadId: 'thread-ma',
        );
        await client.closeSession(
          sessionId: 'session-ma',
          threadId: 'thread-ma',
        );

        expect(server.rpcMethods, contains('session.cancel'));
        expect(server.rpcMethods, contains('session.close'));
      },
    );
  });
}

class _AcpFakeServer {
  _AcpFakeServer._(
    this._server, {
    required this.disableWebSocket,
    required this.respondWithHtmlError,
    required this.pathPrefix,
  });

  final HttpServer _server;
  final bool disableWebSocket;
  final bool respondWithHtmlError;
  final String pathPrefix;
  final List<String> rpcMethods = <String>[];
  String? lastWebSocketAuthorization;
  String? lastHttpAuthorization;
  String? lastWebSocketRequestPath;
  String? lastHttpRequestPath;

  Uri get baseHttpUri =>
      Uri.parse('http://127.0.0.1:${_server.port}$pathPrefix');

  static Future<_AcpFakeServer> start({
    bool disableWebSocket = false,
    bool respondWithHtmlError = false,
    String pathPrefix = '',
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = _AcpFakeServer._(
      server,
      disableWebSocket: disableWebSocket,
      respondWithHtmlError: respondWithHtmlError,
      pathPrefix: _normalizePathPrefix(pathPrefix),
    );
    unawaited(fake._listen());
    return fake;
  }

  Future<void> close() async {
    await _server.close(force: true);
  }

  Future<void> _listen() async {
    await for (final request in _server) {
      if (!disableWebSocket &&
          request.uri.path == '$pathPrefix/acp' &&
          WebSocketTransformer.isUpgradeRequest(request)) {
        lastWebSocketRequestPath = request.uri.path;
        lastWebSocketAuthorization = request.headers.value(
          HttpHeaders.authorizationHeader,
        );
        final socket = await WebSocketTransformer.upgrade(request);
        unawaited(_handleWebSocket(socket));
        continue;
      }
      if (request.uri.path == '$pathPrefix/acp/rpc' &&
          request.method == 'POST') {
        lastHttpRequestPath = request.uri.path;
        await _handleHttpRpc(request);
        continue;
      }
      request.response
        ..statusCode = HttpStatus.notFound
        ..write('not found');
      await request.response.close();
    }
  }

  Future<void> _handleWebSocket(WebSocket socket) async {
    await for (final raw in socket) {
      final envelope = _decodeMap(raw);
      final id = envelope['id'];
      final method = envelope['method']?.toString() ?? '';
      final params = _asMap(envelope['params']);
      if (method.isEmpty) {
        continue;
      }
      rpcMethods.add(method);
      await _dispatch(
        method: method,
        id: id,
        params: params,
        notify: (notification) async {
          socket.add(jsonEncode(notification));
        },
        respond: (response) async {
          socket.add(jsonEncode(response));
        },
      );
    }
  }

  Future<void> _handleHttpRpc(HttpRequest request) async {
    lastHttpAuthorization = request.headers.value(
      HttpHeaders.authorizationHeader,
    );
    if (respondWithHtmlError) {
      request.response.statusCode = HttpStatus.notFound;
      request.response.headers.set(HttpHeaders.contentTypeHeader, 'text/html');
      request.response.write(
        '<!doctype html><script>var key = "opencode-theme-id"</script>',
      );
      await request.response.close();
      return;
    }
    final body = await utf8.decodeStream(request);
    final envelope = _decodeMap(body);
    final id = envelope['id'];
    final method = envelope['method']?.toString() ?? '';
    final params = _asMap(envelope['params']);
    if (method.isEmpty) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }
    rpcMethods.add(method);

    request.response.headers.set(
      HttpHeaders.contentTypeHeader,
      'text/event-stream',
    );
    request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');

    Future<void> notify(Map<String, dynamic> notification) async {
      request.response.write('data: ${jsonEncode(notification)}\n\n');
      await request.response.flush();
    }

    Future<void> respond(Map<String, dynamic> response) async {
      request.response.write('data: ${jsonEncode(response)}\n\n');
      await request.response.flush();
      await request.response.close();
    }

    await _dispatch(
      method: method,
      id: id,
      params: params,
      notify: notify,
      respond: respond,
    );
  }

  Future<void> _dispatch({
    required String method,
    required Object? id,
    required Map<String, dynamic> params,
    required Future<void> Function(Map<String, dynamic> notification) notify,
    required Future<void> Function(Map<String, dynamic> response) respond,
  }) async {
    switch (method) {
      case 'acp.capabilities':
        await respond(
          _resultEnvelope(
            id: id,
            result: <String, dynamic>{
              'singleAgent': true,
              'multiAgent': true,
              'providers': <String>['codex', 'claude', 'gemini', 'opencode'],
              'capabilities': <String, dynamic>{
                'single_agent': true,
                'multi_agent': true,
                'providers': <String>['codex', 'claude', 'gemini', 'opencode'],
              },
            },
          ),
        );
        return;
      case 'session.start':
      case 'session.message':
        final sessionId = params['sessionId']?.toString() ?? 'session-default';
        final threadId = params['threadId']?.toString() ?? sessionId;
        final mode = params['mode']?.toString() ?? 'single-agent';
        if (mode == 'multi-agent') {
          await notify(
            _notificationEnvelope(
              method: 'multi_agent.event',
              params: <String, dynamic>{
                'type': 'step',
                'title': 'Architect',
                'message': 'planning',
                'pending': false,
                'error': false,
                'data': <String, dynamic>{'seq': 1},
              },
            ),
          );
          await respond(
            _resultEnvelope(
              id: id,
              result: <String, dynamic>{
                'success': true,
                'summary': 'multi-agent done',
                'finalScore': 9,
                'iterations': 1,
              },
            ),
          );
          return;
        }
        final provider = params['provider']?.toString() ?? 'unknown';
        await notify(
          _notificationEnvelope(
            method: 'session.update',
            params: <String, dynamic>{
              'sessionId': sessionId,
              'threadId': threadId,
              'turnId': 'turn-single',
              'type': 'delta',
              'delta': 'delta-single',
              'seq': 1,
              'mode': 'single-agent',
            },
          ),
        );
        await respond(
          _resultEnvelope(
            id: id,
            result: <String, dynamic>{
              'success': true,
              'output': 'single-agent result ($provider)',
              'turnId': 'turn-single',
            },
          ),
        );
        return;
      case 'session.cancel':
        await respond(
          _resultEnvelope(
            id: id,
            result: const <String, dynamic>{
              'accepted': true,
              'cancelled': true,
            },
          ),
        );
        return;
      case 'session.close':
        await respond(
          _resultEnvelope(
            id: id,
            result: const <String, dynamic>{'accepted': true, 'closed': true},
          ),
        );
        return;
      default:
        await respond(<String, dynamic>{
          'jsonrpc': '2.0',
          'id': id,
          'error': <String, dynamic>{
            'code': -32601,
            'message': 'method not found',
          },
        });
    }
  }

  Map<String, dynamic> _resultEnvelope({
    required Object? id,
    required Map<String, dynamic> result,
  }) {
    return <String, dynamic>{'jsonrpc': '2.0', 'id': id, 'result': result};
  }

  Map<String, dynamic> _notificationEnvelope({
    required String method,
    required Map<String, dynamic> params,
  }) {
    return <String, dynamic>{
      'jsonrpc': '2.0',
      'method': method,
      'params': params,
    };
  }

  Map<String, dynamic> _decodeMap(Object raw) {
    if (raw is String) {
      final decoded = jsonDecode(raw);
      return _asMap(decoded);
    }
    if (raw is List<int>) {
      final decoded = jsonDecode(utf8.decode(raw));
      return _asMap(decoded);
    }
    return _asMap(raw);
  }

  Map<String, dynamic> _asMap(Object? raw) {
    if (raw is Map<String, dynamic>) {
      return raw;
    }
    if (raw is Map) {
      return raw.cast<String, dynamic>();
    }
    return const <String, dynamic>{};
  }

  static String _normalizePathPrefix(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed == '/') {
      return '';
    }
    final prefixed = trimmed.startsWith('/') ? trimmed : '/$trimmed';
    final normalized = prefixed.replaceFirst(RegExp(r'/+$'), '');
    return normalized == '/' ? '' : normalized;
  }
}
