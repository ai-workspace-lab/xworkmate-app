// ignore_for_file: unused_import, unnecessary_import

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xworkmate/models/app_models.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';
import 'secure_config_store_suite_core.dart';
import 'secure_config_store_suite_settings.dart';
import 'secure_config_store_suite_compatibility.dart';
import 'secure_config_store_suite_lifecycle.dart';
import 'secure_config_store_suite_fixtures.dart';

void registerSecureConfigStoreSuiteSecretsTestsInternal() {
  group('Secret storage', () {
    test(
      'SecureConfigStore keeps gateway secrets isolated per profile slot',
      () async {
        final tempDirectory = await createTempDirectoryInternal(
          'xworkmate-config-store-profiles-',
        );
        final store = createStoreFromTempDirectoryInternal(tempDirectory);

        await store.saveGatewayToken(
          'local-token',
          profileIndex: kGatewayLocalProfileIndex,
        );
        await store.saveGatewayToken(
          'remote-token',
          profileIndex: kGatewayRemoteProfileIndex,
        );
        await store.saveGatewayPassword(
          'custom-password',
          profileIndex: kGatewayCustomProfileStartIndex,
        );

        final secureRefs = await store.loadSecureRefs();

        expect(
          await store.loadGatewayToken(profileIndex: kGatewayLocalProfileIndex),
          'local-token',
        );
        expect(
          await store.loadGatewayToken(
            profileIndex: kGatewayRemoteProfileIndex,
          ),
          'remote-token',
        );
        expect(
          await store.loadGatewayPassword(
            profileIndex: kGatewayCustomProfileStartIndex,
          ),
          'custom-password',
        );
        expect(
          secureRefs['gateway_token_$kGatewayLocalProfileIndex'],
          'local-token',
        );
        expect(
          secureRefs['gateway_token_$kGatewayRemoteProfileIndex'],
          'remote-token',
        );
        expect(
          secureRefs['gateway_password_$kGatewayCustomProfileStartIndex'],
          'custom-password',
        );
        expect(await store.loadGatewayToken(), 'remote-token');
      },
    );

    test(
      'SecureConfigStore writes secrets into the fixed secret path',
      () async {
        final tempDirectory = await createTempDirectoryInternal(
          'xworkmate-config-store-secret-path-',
        );
        final store = SecureConfigStore(
          fallbackDirectoryPathResolver: () async =>
              '${tempDirectory.path}/secrets',
        );

        await store.saveGatewayToken('token-secret');
        await store.saveGatewayPassword('password-secret');
        await store.saveAiGatewayApiKey('ai-gateway-secret');

        expect(await store.loadGatewayToken(), 'token-secret');
        expect(await store.loadGatewayPassword(), 'password-secret');
        expect(await store.loadAiGatewayApiKey(), 'ai-gateway-secret');
        final secretDirectory = Directory('${tempDirectory.path}/secrets');
        final secretFiles = await secretDirectory
            .list()
            .where((entity) => entity is File)
            .toList();
        expect(secretFiles, hasLength(3));
        expect(
          secretFiles.every((entity) => entity.path.endsWith('.secret')),
          isTrue,
        );
        expect(store.persistentWriteFailures.secrets, isNull);
        if (!Platform.isWindows) {
          expect((await secretDirectory.stat()).modeString(), 'rwx------');
          for (final entity in secretFiles) {
            expect((await entity.stat()).modeString(), 'rw-------');
          }
        }
      },
    );

    test(
      'SecureConfigStore keeps Vault root token out of the settings snapshot payload',
      () async {
        final tempDirectory = await createTempDirectoryInternal(
          'xworkmate-config-store-vault-secret-',
        );
        final store = createStoreFromTempDirectoryInternal(tempDirectory);
        final snapshot = SettingsSnapshot.defaults().copyWith(
          vault: SettingsSnapshot.defaults().vault.copyWith(
            address: 'https://vault.example.com',
            namespace: 'platform/team-a',
          ),
        );

        await store.saveSettingsSnapshot(snapshot);
        await store.saveVaultToken('vault-root-secret');

        expect(await store.loadVaultToken(), 'vault-root-secret');
        expect(
          (await store.loadSecureRefs())['vault_token'],
          'vault-root-secret',
        );
        expect(
          (await store.loadSettingsSnapshot()).toJsonString(),
          isNot(contains('vault-root-secret')),
        );
      },
    );

    test(
      'SecureConfigStore exposes an explicit secrets write failure when durable secret storage is unavailable',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final tempDirectory = await createTempDirectoryInternal(
          'xworkmate-config-store-secrets-memory-fallback-',
        );
        final store = SecureConfigStore(
          databasePathResolver: () async => tempDirectory.path,
          fallbackDirectoryPathResolver: () async =>
              '/dev/null/xworkmate/secrets',
        );

        await store.saveGatewayToken('token-secret');

        expect(await store.loadGatewayToken(), 'token-secret');
        expect(store.persistentWriteFailures.secrets, isNotNull);
        expect(
          store.persistentWriteFailures.secrets?.scope,
          PersistentStoreScope.secrets,
        );
        expect(store.persistentWriteFailures.secrets?.operation, 'writeSecret');
        expect(
          store.persistentWriteFailures.secrets?.message,
          contains('Persistent secret'),
        );

        final reloadedStore = SecureConfigStore(
          databasePathResolver: () async => tempDirectory.path,
          fallbackDirectoryPathResolver: () async =>
              '/dev/null/xworkmate/secrets',
        );
        expect(await reloadedStore.loadGatewayToken(), isNull);
      },
    );

    test(
      'SecureConfigStore clears gateway token without touching snapshot',
      () async {
        final tempDirectory = await createTempDirectoryInternal(
          'xworkmate-config-store-clear-token-',
        );
        final store = createStoreFromTempDirectoryInternal(tempDirectory);

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

    test(
      'SecureConfigStore falls back to file-backed device identity and token across instances',
      () async {
        final tempDirectory = await createTempDirectoryInternal(
          'xworkmate-secure-store-',
        );

        final identity = const LocalDeviceIdentity(
          deviceId: 'device-123',
          publicKeyBase64Url: 'public-key',
          privateKeyBase64Url: 'private-key',
          createdAtMs: 1700000000000,
        );
        final firstStore = SecureConfigStore(
          fallbackDirectoryPathResolver: () async => tempDirectory.path,
        );
        await firstStore.saveDeviceIdentity(identity);
        await firstStore.saveDeviceToken(
          deviceId: identity.deviceId,
          role: 'operator',
          token: 'device-token',
        );

        final secondStore = SecureConfigStore(
          fallbackDirectoryPathResolver: () async => tempDirectory.path,
        );
        final reloadedIdentity = await secondStore.loadDeviceIdentity();
        final reloadedToken = await secondStore.loadDeviceToken(
          deviceId: identity.deviceId,
          role: 'operator',
        );

        expect(reloadedIdentity?.deviceId, identity.deviceId);
        expect(
          reloadedIdentity?.publicKeyBase64Url,
          identity.publicKeyBase64Url,
        );
        expect(
          reloadedIdentity?.privateKeyBase64Url,
          identity.privateKeyBase64Url,
        );
        expect(reloadedToken, 'device-token');
      },
    );
  });
}
