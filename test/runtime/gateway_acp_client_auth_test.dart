import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/runtime/gateway_acp_client.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';

void main() {
  group('GatewayAcpClient authorization', () {
    test('normalizes raw resolver token into bearer header for HTTP', () async {
      final capture = await _startAcpHttpServer();
      addTearDown(capture.close);

      final client = GatewayAcpClient(
        endpointResolver: () => capture.baseEndpoint,
        authorizationResolver: (_) async => 'bridge-token',
      );

      final response = await client.request(
        method: 'acp.capabilities',
        params: const <String, dynamic>{},
      );

      expect(capture.authorizationHeader, 'Bearer bridge-token');
      expect(capture.requestPath, '/acp/rpc');
      expect((response['result'] as Map)['ok'], true);
    });

    test(
      'normalizes raw authorization override into bearer header for HTTP',
      () async {
        final capture = await _startAcpHttpServer();
        addTearDown(capture.close);

        final client = GatewayAcpClient(
          endpointResolver: () => capture.baseEndpoint,
        );

        await client.request(
          method: 'acp.capabilities',
          params: const <String, dynamic>{},
          authorizationOverride: 'override-token',
        );

        expect(capture.authorizationHeader, 'Bearer override-token');
      },
    );

    test('preserves prebuilt bearer authorization header', () async {
      final capture = await _startAcpHttpServer();
      addTearDown(capture.close);

      final client = GatewayAcpClient(
        endpointResolver: () => capture.baseEndpoint,
      );

      await client.request(
        method: 'acp.capabilities',
        params: const <String, dynamic>{},
        authorizationOverride: 'Bearer ready-token',
      );

      expect(capture.authorizationHeader, 'Bearer ready-token');
    });

    test('desktop bridge auth resolver skips unrelated endpoints', () async {
      final storeRoot = await Directory.systemTemp.createTemp(
        'xworkmate-acp-auth-unrelated-',
      );
      addTearDown(() async {
        if (await storeRoot.exists()) {
          await storeRoot.delete(recursive: true);
        }
      });

      final store = SecureConfigStore(
        secretRootPathResolver: () async => '${storeRoot.path}/secrets',
        appDataRootPathResolver: () async => '${storeRoot.path}/app-data',
        supportRootPathResolver: () async => '${storeRoot.path}/support',
        enableSecureStorage: false,
      );
      await store.initialize();
      await store.saveAccountManagedSecret(
        target: kAccountManagedSecretTargetBridgeAuthToken,
        value: 'bridge-token',
      );

      final controller = AppController(store: store);
      addTearDown(controller.dispose);

      final header = await controller
          .resolveGatewayAcpAuthorizationHeaderInternal(
            Uri.parse('https://unrelated.example.com/acp/rpc'),
          );

      expect(header, isNull);
    });

    test(
      'desktop auth resolver reuses the matching gateway profile token',
      () async {
        final storeRoot = await Directory.systemTemp.createTemp(
          'xworkmate-acp-auth-matching-profile-',
        );
        addTearDown(() async {
          if (await storeRoot.exists()) {
            try {
              await storeRoot.delete(recursive: true);
            } on FileSystemException {
              // Temp cleanup is best effort here. The controller does not own
              // the lifecycle of the OS temp directory.
            }
          }
        });

        final store = SecureConfigStore(
          secretRootPathResolver: () async => '${storeRoot.path}/secrets',
          appDataRootPathResolver: () async => '${storeRoot.path}/app-data',
          supportRootPathResolver: () async => '${storeRoot.path}/support',
          enableSecureStorage: false,
        );
        await store.initialize();
        await store.saveSettingsSnapshot(
          SettingsSnapshot.defaults().copyWithGatewayProfileAt(
            kGatewayRemoteProfileIndex,
            GatewayConnectionProfile.defaults().copyWith(
              host: 'gateway.example.com',
              port: 8443,
              tls: true,
            ),
          ),
        );
        await store.saveSecretValueByRef('gateway_token_0', 'gateway-token');

        final controller = AppController(store: store);
        addTearDown(controller.dispose);
        await controller.settingsControllerInternal.resetSnapshot(
          await store.loadSettingsSnapshot(),
        );

        final header = await controller
            .resolveGatewayAcpAuthorizationHeaderInternal(
              Uri.parse('https://gateway.example.com:8443/acp/rpc'),
            );

        expect(header, 'gateway-token');
      },
    );

    test(
      'desktop bridge auth resolver sends managed bridge bearer for capabilities HTTP',
      () async {
        final capture = await _startAcpHttpServer();
        addTearDown(capture.close);

        final storeRoot = await Directory.systemTemp.createTemp(
          'xworkmate-acp-auth-managed-bridge-',
        );
        addTearDown(() async {
          if (await storeRoot.exists()) {
            try {
              await storeRoot.delete(recursive: true);
            } on FileSystemException {
              // Temp cleanup is best effort here. The client may still be
              // releasing files when teardown starts.
            }
          }
        });

        final store = SecureConfigStore(
          secretRootPathResolver: () async => '${storeRoot.path}/secrets',
          appDataRootPathResolver: () async => '${storeRoot.path}/app-data',
          supportRootPathResolver: () async => '${storeRoot.path}/support',
          enableSecureStorage: false,
        );
        await store.initialize();
        await store.saveAccountManagedSecret(
          target: kAccountManagedSecretTargetBridgeAuthToken,
          value: 'bridge-token',
        );

        final controller = AppController(
          store: store,
          environmentOverride: <String, String>{
            'BRIDGE_SERVER_URL': capture.baseEndpoint.toString(),
          },
        );
        addTearDown(controller.dispose);
        await controller.settingsControllerInternal.initialize();

        await controller.gatewayAcpClientInternal.loadCapabilities(
          forceRefresh: true,
        );

        expect(capture.authorizationHeader, 'Bearer bridge-token');
        expect(capture.requestPath, '/acp/rpc');
      },
    );

    test(
      'desktop bridge auth resolver falls back to the remote gateway token for bridge ACP',
      () async {
        final storeRoot = await Directory.systemTemp.createTemp(
          'xworkmate-acp-auth-bridge-fallback-',
        );
        addTearDown(() async {
          if (await storeRoot.exists()) {
            try {
              await storeRoot.delete(recursive: true);
            } on FileSystemException {
              // Temp cleanup is best effort here. The controller may still be
              // releasing files when teardown starts.
            }
          }
        });

        final store = SecureConfigStore(
          secretRootPathResolver: () async => '${storeRoot.path}/secrets',
          appDataRootPathResolver: () async => '${storeRoot.path}/app-data',
          supportRootPathResolver: () async => '${storeRoot.path}/support',
          enableSecureStorage: false,
        );
        await store.initialize();
        await store.saveSettingsSnapshot(
          SettingsSnapshot.defaults().copyWithGatewayProfileAt(
            kGatewayRemoteProfileIndex,
            GatewayConnectionProfile.defaults().copyWith(
              host: 'xworkmate.svc.plus',
              port: 443,
              tls: true,
            ),
          ),
        );
        await store.saveSecretValueByRef('gateway_token_0', 'gateway-token');

        final controller = AppController(store: store);
        addTearDown(controller.dispose);
        await controller.settingsControllerInternal.initialize();

        final header = await controller
            .resolveGatewayAcpAuthorizationHeaderInternal(
              Uri.parse('https://xworkmate-bridge.svc.plus/acp/rpc'),
            );

        expect(header, 'gateway-token');
      },
    );

    test(
      'desktop bridge auth resolver resolves manual bridge token when configured',
      () async {
        final storeRoot = await Directory.systemTemp.createTemp(
          'xworkmate-acp-auth-bridge-manual-',
        );
        addTearDown(() async {
          if (await storeRoot.exists()) {
            try {
              await storeRoot.delete(recursive: true);
            } on FileSystemException {
              // Temp cleanup is best effort here.
            }
          }
        });

        final store = SecureConfigStore(
          secretRootPathResolver: () async => '${storeRoot.path}/secrets',
          appDataRootPathResolver: () async => '${storeRoot.path}/app-data',
          supportRootPathResolver: () async => '${storeRoot.path}/support',
          enableSecureStorage: false,
        );
        await store.initialize();

        final settings = SettingsSnapshot.defaults().copyWith(
          acpBridgeServerModeConfig: AcpBridgeServerModeConfig.defaults().copyWith(
            mode: AcpBridgeServerMode.manual,
            selfHosted: AcpBridgeServerSelfHostedConfig.defaults().copyWith(
              serverUrl: 'https://manual-bridge.example.com',
            ),
          ),
        );
        await store.saveSettingsSnapshot(settings);
        await store.saveSecretValueByRef(
          settings.acpBridgeServerModeConfig.selfHosted.passwordRef,
          'manual-token',
        );

        final controller = AppController(store: store);
        addTearDown(controller.dispose);
        await controller.settingsControllerInternal.initialize();

        final header = await controller
            .resolveGatewayAcpAuthorizationHeaderInternal(
              Uri.parse('https://manual-bridge.example.com/acp/rpc'),
            );

        expect(header, 'manual-token');
      },
    );
  });
}

Future<_CapturedAcpHttpServer> _startAcpHttpServer() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final capture = _CapturedAcpHttpServer._(
    server,
    Uri.parse('http://127.0.0.1:${server.port}'),
  );
  server.listen((request) async {
    capture.authorizationHeader =
        request.headers.value(HttpHeaders.authorizationHeader) ?? '';
    capture.requestPath = request.uri.path;
    final body = await utf8.decoder.bind(request).join();
    final id = _decodeRequestId(body);
    request.response.headers.contentType = ContentType.json;
    request.response.write(
      jsonEncode(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'result': <String, dynamic>{'ok': true},
      }),
    );
    await request.response.close();
  });
  return capture;
}

String _decodeRequestId(String body) {
  final decoded = jsonDecode(body);
  if (decoded is Map && decoded['id'] != null) {
    return decoded['id'].toString();
  }
  return 'request-id';
}

class _CapturedAcpHttpServer {
  _CapturedAcpHttpServer._(this._server, this.baseEndpoint);

  final HttpServer _server;
  final Uri baseEndpoint;
  String authorizationHeader = '';
  String requestPath = '';

  Future<void> close() => _server.close(force: true);
}
