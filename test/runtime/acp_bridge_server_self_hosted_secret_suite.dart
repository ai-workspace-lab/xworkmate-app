@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';

void main() {
  test('self hosted ACP bridge password stays in secure storage, not settings snapshot', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final tempDirectory = await Directory.systemTemp.createTemp(
      'xworkmate-acp-bridge-self-hosted-',
    );
    addTearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });
    final store = SecureConfigStore(
      enableSecureStorage: false,
      databasePathResolver: () async => '${tempDirectory.path}/settings.sqlite3',
      fallbackDirectoryPathResolver: () async => tempDirectory.path,
      defaultSupportDirectoryPathResolver: () async => tempDirectory.path,
    );
    addTearDown(store.dispose);
    await store.initialize();

    final snapshot = SettingsSnapshot.defaults().copyWith(
      acpBridgeServerModeConfig: AcpBridgeServerModeConfig.defaults().copyWith(
        mode: AcpBridgeServerMode.selfHosted,
        selfHosted: AcpBridgeServerSelfHostedConfig.defaults().copyWith(
          serverUrl: 'https://bridge.example.com',
          username: 'review@example.com',
        ),
      ),
    );
    await store.saveSettingsSnapshot(snapshot);
    await store.saveSecretValueByRef('acp_bridge_server_password', 'top-secret');

    final loadedSnapshot = await store.loadSettingsSnapshot();

    expect(
      loadedSnapshot.acpBridgeServerModeConfig.selfHosted.passwordRef,
      'acp_bridge_server_password',
    );
    expect(loadedSnapshot.toJsonString(), isNot(contains('top-secret')));
    expect(
      await store.loadSecretValueByRef('acp_bridge_server_password'),
      'top-secret',
    );
  });
}
