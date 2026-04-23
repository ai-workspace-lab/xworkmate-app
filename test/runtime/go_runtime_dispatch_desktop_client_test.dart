import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/gateway_acp_client.dart';
import 'package:xworkmate/runtime/go_runtime_dispatch_desktop_client.dart';
import 'package:xworkmate/runtime/runtime_external_code_agents.dart';

void main() {
  test('desktop dispatch resolver uses xworkmate.routing.resolve', () async {
    final capture = await _startAcpHttpServer();
    addTearDown(capture.close);

    final client = GatewayAcpClient(
      endpointResolver: () => capture.baseEndpoint,
    );
    final resolver = GoRuntimeDispatchDesktopClient(
      client: client,
      endpointResolver: () => capture.baseEndpoint,
    );
    addTearDown(resolver.dispose);

    await resolver.resolveGatewayDispatch(
      providers: const <ExternalCodeAgentProvider>[],
      preferredProviderId: 'codex',
      requiredCapabilities: const <String>['skill-a'],
      nodeState: const <String, dynamic>{},
      nodeInfo: const <String, dynamic>{},
    );

    expect(capture.method, 'xworkmate.routing.resolve');
    expect(capture.body, contains('"routingMode":"auto"'));
    expect(capture.body, contains('"preferredGatewayTarget":"codex"'));
  });
}

Future<_CapturedAcpHttpServer> _startAcpHttpServer() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final capture = _CapturedAcpHttpServer._(
    server,
    Uri.parse('http://127.0.0.1:${server.port}'),
  );
  server.listen((request) async {
    final body = await utf8.decoder.bind(request).join();
    capture.body = body;
    final decoded = jsonDecode(body);
    capture.method = decoded['method']?.toString() ?? '';
    final id = decoded['id']?.toString() ?? 'request-id';
    request.response.headers.contentType = ContentType.json;
    request.response.write(
      jsonEncode(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'result': <String, dynamic>{'providerId': 'codex'},
      }),
    );
    await request.response.close();
  });
  return capture;
}

class _CapturedAcpHttpServer {
  _CapturedAcpHttpServer._(this._server, this.baseEndpoint);

  final HttpServer _server;
  final Uri baseEndpoint;
  String method = '';
  String body = '';

  Future<void> close() => _server.close(force: true);
}
