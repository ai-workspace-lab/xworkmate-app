import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/runtime/multi_agent_mount_resolver.dart';
import 'package:xworkmate/runtime/multi_agent_mounts.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';

void main() {
  test(
    'capability refresh does not fail when remote mount reconcile is absent',
    () async {
      final server = await _CapabilityServer.start();
      addTearDown(server.close);

      final storeRoot = await Directory.systemTemp.createTemp(
        'xworkmate-mount-resilience-',
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
      );
      await store.initialize();
      final settings = SettingsSnapshot.defaults();
      final bridgeConfig = settings.acpBridgeServerModeConfig;
      final selfHosted = bridgeConfig.selfHosted.copyWith(
        serverUrl: server.endpoint,
        username: 'admin',
      );
      await store.saveSecretValueByRef(selfHosted.passwordRef, 'bridge-token');
      await store.saveSettingsSnapshot(
        settings.copyWith(
          acpBridgeServerModeConfig: bridgeConfig.copyWith(
            selfHosted: selfHosted,
            effective: AcpBridgeServerEffectiveConfig(
              endpoint: server.endpoint,
              tokenRef: selfHosted.passwordRef,
              source: 'bridge',
              reason: 'test bridge',
            ),
          ),
        ),
      );

      final controller = AppController(
        store: store,
        environmentOverride: <String, String>{'HOME': storeRoot.path},
        multiAgentMountManager: MultiAgentMountManager(
          resolver: _MissingRemoteMountResolver(),
        ),
      );
      addTearDown(controller.dispose);

      await _waitForInitialization(controller);

      expect(controller.bootstrapError, isNull);
      expect(controller.bridgeCapabilitiesRefreshErrorInternal, isEmpty);
      expect(
        controller.gatewayProviderCatalog.map((item) => item.providerId),
        contains('openclaw'),
      );
    },
  );
}

Future<void> _waitForInitialization(AppController controller) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (controller.initializing && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  if (controller.initializing) {
    fail('controller did not initialize');
  }
}

class _MissingRemoteMountResolver implements MultiAgentMountResolver {
  @override
  Future<MultiAgentConfig?> reconcile({
    required MultiAgentConfig config,
    required String aiGatewayUrl,
    required String codexHome,
    required String opencodeHome,
    required ArisMountProbe arisProbe,
  }) {
    throw StateError('unknown method: xworkmate.mounts.reconcile');
  }

  @override
  Future<void> dispose() async {}
}

class _CapabilityServer {
  _CapabilityServer(this._server);

  final HttpServer _server;

  String get endpoint => 'http://${_server.address.host}:${_server.port}';

  static Future<_CapabilityServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final wrapper = _CapabilityServer(server);
    server.listen(wrapper._handle);
    return wrapper;
  }

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    final raw = await utf8.decoder.bind(request).join();
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final method = decoded['method']?.toString() ?? '';
    request.response.headers.contentType = ContentType.json;
    if (method != 'acp.capabilities') {
      request.response.write(
        jsonEncode(<String, Object?>{
          'jsonrpc': '2.0',
          'id': decoded['id'],
          'error': <String, Object?>{
            'code': -32601,
            'message': 'unknown method: $method',
          },
        }),
      );
      await request.response.close();
      return;
    }
    request.response.write(
      jsonEncode(<String, Object?>{
        'jsonrpc': '2.0',
        'id': decoded['id'],
        'result': <String, Object?>{
          'singleAgent': true,
          'multiAgent': true,
          'availableExecutionTargets': <String>['agent', 'gateway'],
          'providerCatalog': <Map<String, Object?>>[
            <String, Object?>{
              'providerId': 'codex',
              'label': 'Codex',
              'targets': <String>['agent'],
            },
          ],
          'gatewayProviders': <Map<String, Object?>>[
            <String, Object?>{
              'providerId': 'openclaw',
              'label': 'OpenClaw',
              'targets': <String>['gateway'],
            },
          ],
        },
      }),
    );
    await request.response.close();
  }
}
