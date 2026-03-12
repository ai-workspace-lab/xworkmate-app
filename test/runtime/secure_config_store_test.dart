import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

void main() {
  test(
    'SecureConfigStore persists settings and secure refs in test runners',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = SecureConfigStore();

      final snapshot = SettingsSnapshot.defaults().copyWith(
        accountUsername: 'tester',
        accountWorkspace: 'QA',
        gateway: GatewayConnectionProfile.defaults().copyWith(
          host: 'gateway.example.com',
          port: 9443,
        ),
      );

      await store.saveSettingsSnapshot(snapshot);
      await store.saveGatewayToken('token-secret');
      await store.saveGatewayPassword('password-secret');
      await store.saveVaultToken('vault-secret');

      final loadedSnapshot = await store.loadSettingsSnapshot();
      final secureRefs = await store.loadSecureRefs();

      expect(loadedSnapshot.accountUsername, 'tester');
      expect(loadedSnapshot.accountWorkspace, 'QA');
      expect(loadedSnapshot.gateway.host, 'gateway.example.com');
      expect(loadedSnapshot.gateway.port, 9443);
      expect(secureRefs['gateway_token'], 'token-secret');
      expect(secureRefs['gateway_password'], 'password-secret');
      expect(secureRefs['vault_token'], 'vault-secret');
      expect(SecureConfigStore.maskValue('token-secret'), 'tok••••ret');
      expect(SecureConfigStore.maskValue(''), 'Not set');
    },
  );

  test(
    'SecureConfigStore clears gateway token without touching snapshot',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = SecureConfigStore();

      await store.saveGatewayToken('token-secret');
      expect(await store.loadGatewayToken(), 'token-secret');

      await store.clearGatewayToken();

      expect(await store.loadGatewayToken(), isNull);
      expect(
        (await store.loadSecureRefs()).containsKey('gateway_token'),
        isFalse,
      );
    },
  );
}
