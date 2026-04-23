import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/acp_endpoint_paths.dart';

void main() {
  group('ACP endpoint path resolution', () {
    test('resolves managed bridge origin to ACP HTTP RPC path', () {
      final endpoint = resolveAcpHttpRpcEndpoint(
        Uri.parse('https://xworkmate-bridge.svc.plus'),
      );

      expect(endpoint.toString(), 'https://xworkmate-bridge.svc.plus/acp/rpc');
    });

    test('does not preserve provider mapping paths as app RPC bases', () {
      final codexEndpoint = resolveAcpHttpRpcEndpoint(
        Uri.parse('https://xworkmate-bridge.svc.plus/acp-server/codex'),
      );
      final gatewayEndpoint = resolveAcpHttpRpcEndpoint(
        Uri.parse('https://xworkmate-bridge.svc.plus/gateway/openclaw'),
      );

      expect(
        codexEndpoint.toString(),
        'https://xworkmate-bridge.svc.plus/acp/rpc',
      );
      expect(
        gatewayEndpoint.toString(),
        'https://xworkmate-bridge.svc.plus/acp/rpc',
      );
    });

    test(
      'normalizes provider mapping paths even when ACP suffix is present',
      () {
        final endpoint = resolveAcpHttpRpcEndpoint(
          Uri.parse(
            'https://xworkmate-bridge.svc.plus/acp-server/codex/acp/rpc',
          ),
        );

        expect(
          endpoint.toString(),
          'https://xworkmate-bridge.svc.plus/acp/rpc',
        );
      },
    );
  });
}
