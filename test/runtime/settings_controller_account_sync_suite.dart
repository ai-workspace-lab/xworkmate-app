@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xworkmate/runtime/runtime_controllers.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';

import '../test_support_account_server.dart';

void main() {
  test(
    'SettingsController logs in and syncs account-managed secrets without writing them into settings snapshot',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final server = await FakeAccountVaultServer.start();
      addTearDown(server.close);
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-settings-account-sync-',
      );
      addTearDown(() async => _deleteDirectoryBestEffort(tempDirectory));
      final store = _createIsolatedStore(tempDirectory.path);
      addTearDown(store.dispose);

      final controller = SettingsController(store);
      await controller.initialize();
      await controller.saveSnapshot(
        SettingsSnapshot.defaults().copyWith(
          accountBaseUrl: server.accountBaseUrl,
          accountUsername: server.loginEmail,
          accountLocalMode: false,
        ),
      );
      await controller.saveVaultToken(server.expectedVaultToken);

      await controller.loginAccount(
        baseUrl: server.accountBaseUrl,
        identifier: server.loginEmail,
        password: server.loginPassword,
      );

      expect(controller.accountSignedIn, isTrue);
      expect(controller.accountMfaRequired, isFalse);
      expect(controller.accountSession?.email, server.loginEmail);
      expect(controller.accountProfile?.syncState, 'ready');
      expect(
        controller.accountProfile?.aiGatewayAvailableModels,
        contains('gpt-5.4'),
      );
      expect(await store.loadAccountSessionToken(), server.sessionToken);
      expect(
        await store.loadAccountManagedSecret(
          target: kAccountManagedSecretTargetOpenclawGatewayToken,
        ),
        server.openclawGatewayToken,
      );
      expect(
        await controller.loadEffectiveAiGatewayApiKey(),
        server.aiGatewayAccessToken,
      );
      expect(
        await controller.loadEffectiveGatewayToken(
          profileIndex: kGatewayRemoteProfileIndex,
        ),
        server.openclawGatewayToken,
      );
      expect(controller.effectiveAiGatewayBaseUrl, server.aiGatewayBaseUrl);
      expect(
        server.lastAiGatewayAuthorization,
        'Bearer ${server.aiGatewayAccessToken}',
      );
      expect(server.lastVaultToken, server.expectedVaultToken);
      expect(server.lastVaultNamespace, 'team-a');
      expect(
        (await store.loadSettingsSnapshot()).toJsonString(),
        allOf(
          isNot(contains(server.sessionToken)),
          isNot(contains(server.openclawGatewayToken)),
          isNot(contains(server.aiGatewayAccessToken)),
          isNot(contains(server.ollamaCloudApiKey)),
        ),
      );
    },
  );

  test(
    'SettingsController completes MFA verification before restoring the account session',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final server = await FakeAccountVaultServer.start(requireMfa: true);
      addTearDown(server.close);
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-settings-account-mfa-',
      );
      addTearDown(() async => _deleteDirectoryBestEffort(tempDirectory));
      final store = _createIsolatedStore(tempDirectory.path);
      addTearDown(store.dispose);

      final controller = SettingsController(store);
      await controller.initialize();
      await controller.saveSnapshot(
        SettingsSnapshot.defaults().copyWith(
          accountBaseUrl: server.accountBaseUrl,
          accountUsername: server.loginEmail,
          accountLocalMode: false,
        ),
      );
      await controller.saveVaultToken(server.expectedVaultToken);

      await controller.loginAccount(
        baseUrl: server.accountBaseUrl,
        identifier: server.loginEmail,
        password: server.loginPassword,
      );

      expect(controller.accountSignedIn, isFalse);
      expect(controller.accountMfaRequired, isTrue);

      await controller.verifyAccountMfa(
        baseUrl: server.accountBaseUrl,
        code: server.loginCode,
      );

      expect(controller.accountSignedIn, isTrue);
      expect(controller.accountMfaRequired, isFalse);
      expect(controller.accountSession?.mfaEnabled, isTrue);
      expect(controller.accountProfile?.syncState, 'ready');
    },
  );

  test(
    'SettingsController keeps account login successful when the local Vault token is missing',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final server = await FakeAccountVaultServer.start();
      addTearDown(server.close);
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-settings-account-vault-missing-',
      );
      addTearDown(() async => _deleteDirectoryBestEffort(tempDirectory));
      final store = _createIsolatedStore(tempDirectory.path);
      addTearDown(store.dispose);

      final controller = SettingsController(store);
      await controller.initialize();
      await controller.saveSnapshot(
        SettingsSnapshot.defaults().copyWith(
          accountBaseUrl: server.accountBaseUrl,
          accountUsername: server.loginEmail,
          accountLocalMode: false,
        ),
      );

      await controller.loginAccount(
        baseUrl: server.accountBaseUrl,
        identifier: server.loginEmail,
        password: server.loginPassword,
      );

      expect(controller.accountSignedIn, isTrue);
      expect(controller.accountProfile?.syncState, 'blocked');
      expect(controller.accountProfile?.syncMessage, contains('Vault token'));
      expect(
        await store.loadAccountManagedSecret(
          target: kAccountManagedSecretTargetAIGatewayAccessToken,
        ),
        isNull,
      );
    },
  );

  test(
    'SettingsController resolves local config ahead of account-managed fallbacks and disables fallbacks in local mode',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final server = await FakeAccountVaultServer.start();
      addTearDown(server.close);
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-settings-account-effective-config-',
      );
      addTearDown(() async => _deleteDirectoryBestEffort(tempDirectory));
      final store = _createIsolatedStore(tempDirectory.path);
      addTearDown(store.dispose);

      final controller = SettingsController(store);
      await controller.initialize();
      await controller.saveSnapshot(
        SettingsSnapshot.defaults().copyWith(
          accountBaseUrl: server.accountBaseUrl,
          accountUsername: server.loginEmail,
          accountLocalMode: false,
        ),
      );
      await controller.saveVaultToken(server.expectedVaultToken);
      await controller.loginAccount(
        baseUrl: server.accountBaseUrl,
        identifier: server.loginEmail,
        password: server.loginPassword,
      );

      await controller.saveAiGatewayApiKey('local-ai-key');
      await controller.saveGatewaySecrets(
        profileIndex: kGatewayRemoteProfileIndex,
        token: 'local-remote-token',
        password: '',
      );
      await controller.saveSnapshot(
        controller.snapshot.copyWith(
          aiGateway: controller.snapshot.aiGateway.copyWith(
            baseUrl: 'https://local-ai.example.com/v1',
          ),
        ),
      );

      expect(await controller.loadEffectiveAiGatewayApiKey(), 'local-ai-key');
      expect(
        await controller.loadEffectiveGatewayToken(
          profileIndex: kGatewayRemoteProfileIndex,
        ),
        'local-remote-token',
      );
      expect(
        controller.effectiveAiGatewayBaseUrl,
        'https://local-ai.example.com/v1',
      );

      await controller.saveSnapshot(
        controller.snapshot.copyWith(
          accountLocalMode: true,
          aiGateway: controller.snapshot.aiGateway.copyWith(baseUrl: ''),
        ),
      );
      await controller.clearAiGatewayApiKey();
      await controller.clearGatewaySecrets(
        profileIndex: kGatewayRemoteProfileIndex,
        token: true,
      );

      expect(await controller.loadEffectiveAiGatewayApiKey(), isEmpty);
      expect(
        await controller.loadEffectiveGatewayToken(
          profileIndex: kGatewayRemoteProfileIndex,
        ),
        isEmpty,
      );
      expect(controller.effectiveAiGatewayBaseUrl, isEmpty);
    },
  );
}

SecureConfigStore _createIsolatedStore(String rootPath) {
  return SecureConfigStore(
    enableSecureStorage: false,
    databasePathResolver: () async => '$rootPath/config-store.sqlite3',
    fallbackDirectoryPathResolver: () async => rootPath,
    defaultSupportDirectoryPathResolver: () async => rootPath,
  );
}

Future<void> _deleteDirectoryBestEffort(Directory directory) async {
  for (var attempt = 0; attempt < 3; attempt += 1) {
    try {
      if (!await directory.exists()) {
        return;
      }
      await directory.delete(recursive: true);
      return;
    } on FileSystemException {
      if (attempt == 2) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
  }
}
