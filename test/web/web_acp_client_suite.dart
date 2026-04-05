@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/web/web_acp_client.dart';

void main() {
  group('WebAcpClient', () {
    test('uses websocket when ws endpoint is provided', () async {
      final server = await _WebAcpFakeServer.start();
      addTearDown(server.close);

      const client = WebAcpClient();
      final capabilities = await client.loadCapabilities(
        endpoint: server.baseHttpUri.replace(scheme: 'ws'),
      );

      expect(capabilities.providers, contains(SingleAgentProvider.codex));
      expect(server.lastWebSocketRequestPath, '/acp');
      expect(server.lastHttpRequestPath, isNull);
    });

    test('uses HTTP RPC when http endpoint is provided', () async {
      final server = await _WebAcpFakeServer.start();
      addTearDown(server.close);

      const client = WebAcpClient();
      final capabilities = await client.loadCapabilities(
        endpoint: server.baseHttpUri,
      );

      expect(capabilities.providers, contains(SingleAgentProvider.codex));
      expect(server.lastHttpRequestPath, '/acp/rpc');
      expect(server.lastWebSocketRequestPath, isNull);
    });

    test('preserves prefixed HTTP RPC paths for hosted bases', () async {
      final server = await _WebAcpFakeServer.start(pathPrefix: '/codex');
      addTearDown(server.close);

      const client = WebAcpClient();
      final capabilities = await client.loadCapabilities(
        endpoint: server.baseHttpUri,
      );

      expect(capabilities.providers, contains(SingleAgentProvider.codex));
      expect(server.lastHttpRequestPath, '/codex/acp/rpc');
    });
  });
}

class _WebAcpFakeServer {
  _WebAcpFakeServer._(this._server, {required this.pathPrefix});

  final HttpServer _server;
  final String pathPrefix;
  String? lastWebSocketRequestPath;
  String? lastHttpRequestPath;

  Uri get baseHttpUri =>
      Uri.parse('http://127.0.0.1:${_server.port}$pathPrefix');

  static Future<_WebAcpFakeServer> start({String pathPrefix = ''}) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = _WebAcpFakeServer._(
      server,
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
      if (WebSocketTransformer.isUpgradeRequest(request) &&
          request.uri.path == '$pathPrefix/acp') {
        lastWebSocketRequestPath = request.uri.path;
        final socket = await WebSocketTransformer.upgrade(request);
        socket.listen((raw) {
          socket.add(
            jsonEncode(<String, dynamic>{
              'jsonrpc': '2.0',
              'id': _decodeId(raw),
              'result': <String, dynamic>{
                'singleAgent': true,
                'multiAgent': true,
                'providers': const <String>['codex'],
              },
            }),
          );
        });
        continue;
      }

      if (request.uri.path == '$pathPrefix/acp/rpc' &&
          request.method == 'POST') {
        lastHttpRequestPath = request.uri.path;
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.set(
          HttpHeaders.contentTypeHeader,
          'text/event-stream',
        );
        final rawBody = await utf8.decoder.bind(request).join();
        final envelope = <String, dynamic>{
          'jsonrpc': '2.0',
          'id': _decodeId(rawBody),
          'result': <String, dynamic>{
            'singleAgent': true,
            'multiAgent': true,
            'providers': const <String>['codex'],
          },
        };
        request.response.write('data: ${jsonEncode(envelope)}\n\n');
        await request.response.close();
        continue;
      }

      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    }
  }

  static String _decodeId(Object raw) {
    final decoded = jsonDecode(raw.toString());
    if (decoded is Map && decoded['id'] != null) {
      return decoded['id'].toString();
    }
    return 'unknown';
  }

  static String _normalizePathPrefix(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed == '/') {
      return '';
    }
    return trimmed.startsWith('/') ? trimmed : '/$trimmed';
  }
}
