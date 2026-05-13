import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/runtime_controllers.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secret_store.dart';

void main() {
  group('Gateway profile cleanup', () {
    test('normalizes settings to the single Bridge profile', () {
      final snapshot = SettingsSnapshot.defaults().copyWith(
        gatewayProfiles: <GatewayConnectionProfile>[
          GatewayConnectionProfile.defaults().copyWith(
            mode: RuntimeConnectionMode.remote,
            host: 'xworkmate-bridge.svc.plus',
            port: 443,
            tls: true,
          ),
          GatewayConnectionProfile.defaults().copyWith(
            mode: RuntimeConnectionMode.remote,
            host: 'stale-local-gateway.example.com',
            port: 18789,
            tls: false,
            tokenRef: 'gateway_token_1',
          ),
        ],
      );

      expect(snapshot.gatewayProfiles, hasLength(1));
      expect(snapshot.primaryGatewayProfile.host, 'xworkmate-bridge.svc.plus');
      expect(snapshot.primaryGatewayProfile.tokenRef, 'gateway_token_0');
    });

    test('does not fall back to stale local Gateway profile secrets', () async {
      final storeRoot = await Directory.systemTemp.createTemp(
        'xworkmate-gateway-profile-cleanup-',
      );
      addTearDown(() async {
        if (await storeRoot.exists()) {
          try {
            await storeRoot.delete(recursive: true);
          } on FileSystemException {
            // Temp cleanup is best effort while Flutter test teardown releases IO.
          }
        }
      });

      final store = SecretStore(
        secretRootPathResolver: () async => '${storeRoot.path}/secrets',
        appDataRootPathResolver: () async => '${storeRoot.path}/app-data',
        supportRootPathResolver: () async => '${storeRoot.path}/support',
        enableSecureStorage: false,
      );
      await store.initialize();
      await store.saveSecretValueByRef('gateway_token_1', 'stale-token');
      await store.saveSecretValueByRef('gateway_password_1', 'stale-password');

      expect(await store.loadGatewayToken(), isNull);
      expect(await store.loadGatewayPassword(), isNull);

      await store.saveSecretValueByRef('gateway_token_0', 'current-token');
      await store.saveSecretValueByRef(
        'gateway_password_0',
        'current-password',
      );

      expect(await store.loadGatewayToken(), 'current-token');
      expect(await store.loadGatewayPassword(), 'current-password');
    });

    test('runtime session key matching no longer aliases main sessions', () {
      expect(matchesSessionKey('draft:test-task', 'draft:test-task'), isTrue);
      expect(matchesSessionKey('agent:main:main', 'main'), isFalse);
      expect(matchesSessionKey('main', 'agent:main:main'), isFalse);
    });
  });
}
