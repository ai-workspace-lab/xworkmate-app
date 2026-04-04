import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/acp_endpoint_paths.dart';
import 'package:xworkmate/web/web_acp_client.dart';

void main() {
  group('AcpEndpointPaths', () {
    test('builds default ACP paths for bare endpoints', () {
      final paths = AcpEndpointPaths.fromBaseEndpoint(
        Uri.parse('https://acp-server.svc.plus'),
      );

      expect(paths.basePath, isEmpty);
      expect(paths.webSocketPath, '/acp');
      expect(paths.httpRpcPath, '/acp/rpc');
    });

    test('preserves prefixed base paths', () {
      final paths = AcpEndpointPaths.fromBaseEndpoint(
        Uri.parse('https://acp-server.svc.plus/codex'),
      );

      expect(paths.basePath, '/codex');
      expect(paths.webSocketPath, '/codex/acp');
      expect(paths.httpRpcPath, '/codex/acp/rpc');
    });

    test('normalizes existing ACP suffixes before rebuilding', () {
      expect(
        AcpEndpointPaths.fromBaseEndpoint(
          Uri.parse('https://acp-server.svc.plus/codex/acp'),
        ).httpRpcPath,
        '/codex/acp/rpc',
      );
      expect(
        AcpEndpointPaths.fromBaseEndpoint(
          Uri.parse('https://acp-server.svc.plus/opencode/acp/rpc'),
        ).webSocketPath,
        '/opencode/acp',
      );
      expect(
        AcpEndpointPaths.fromBaseEndpoint(
          Uri.parse('https://acp-server.svc.plus/opencode/acp/rpc/'),
        ).basePath,
        '/opencode',
      );
    });

    test(
      'resolves websocket and HTTP RPC endpoints with preserved prefixes',
      () {
        expect(
          resolveAcpWebSocketEndpoint(
            Uri.parse('https://acp-server.svc.plus/opencode'),
          ),
          Uri.parse('wss://acp-server.svc.plus/opencode/acp'),
        );
        expect(
          resolveAcpHttpRpcEndpoint(
            Uri.parse('http://acp-server.svc.plus/codex'),
          ),
          Uri.parse('http://acp-server.svc.plus/codex/acp/rpc'),
        );
      },
    );

    test('web ACP client uses shared prefixed websocket resolution', () {
      expect(
        WebAcpClient.resolveWebSocketEndpointInternal(
          Uri.parse('https://acp-server.svc.plus/codex'),
        ),
        Uri.parse('wss://acp-server.svc.plus/codex/acp'),
      );
    });

    test('HTTP RPC resolution rejects websocket-only schemes', () {
      expect(
        resolveAcpHttpRpcEndpoint(
          Uri.parse('wss://acp-server.svc.plus/opencode'),
        ),
        isNull,
      );
    });
  });
}
