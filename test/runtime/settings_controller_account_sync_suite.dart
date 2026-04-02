@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xworkmate/runtime/account_runtime_client.dart';
import 'package:xworkmate/runtime/runtime_controllers.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';

import '../test_support_account_server.dart';

void main() {
  test(
    'SettingsController logs in and syncs remote defaults without writing secrets into settings snapshot',
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
        ),
      );

      await controller.loginAccount(
        baseUrl: server.accountBaseUrl,
        identifier: server.loginEmail,
        password: server.loginPassword,
      );

      expect(controller.accountSignedIn, isTrue);
      expect(controller.accountMfaRequired, isFalse);
      expect(controller.accountSession?.email, server.loginEmail);
      expect(controller.accountSyncState?.syncState, 'ready');
      expect(controller.accountSyncState?.profileScope, 'user');
      expect(controller.accountSyncState?.tokenConfigured.apisix, isTrue);
      expect(await store.loadAccountSessionToken(), server.sessionToken);
      expect(await store.loadAccountSessionExpiresAtMs(), greaterThan(0));
      expect(await store.loadAccountSessionUserId(), 'user-1');
      expect(await store.loadAccountSessionIdentifier(), server.loginEmail);
      expect(await store.loadAccountSyncState(), isNotNull);
      expect(
        await store.loadAccountManagedSecret(
          target: kAccountManagedSecretTargetOpenclawGatewayToken,
        ),
        isNull,
      );
      expect(
        await store.loadAccountManagedSecret(
          target: kAccountManagedSecretTargetAIGatewayAccessToken,
        ),
        isNull,
      );

      final remoteProfile =
          controller.snapshot.gatewayProfiles[kGatewayRemoteProfileIndex];
      expect(remoteProfile.mode, RuntimeConnectionMode.remote);
      expect(remoteProfile.useSetupCode, isFalse);
      expect(remoteProfile.host, 'openclaw.account.example');
      expect(remoteProfile.port, 443);
      expect(remoteProfile.tls, isTrue);
      expect(controller.snapshot.vault.address, server.vaultBaseUrl);
      expect(controller.snapshot.vault.namespace, 'team-a');
      expect(controller.snapshot.aiGateway.baseUrl, server.aiGatewayBaseUrl);
      expect(
        controller.snapshot.aiGateway.apiKeyRef,
        kAccountManagedSecretTargetAIGatewayAccessToken,
      );
      expect(
        controller.snapshot.ollamaCloud.apiKeyRef,
        kAccountManagedSecretTargetOllamaCloudApiKey,
      );
      expect(controller.snapshot.accountLocalMode, isFalse);
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
        ),
      );

      await controller.loginAccount(
        baseUrl: server.accountBaseUrl,
        identifier: server.loginEmail,
        password: server.loginPassword,
      );

      expect(controller.accountSignedIn, isFalse);
      expect(controller.accountMfaRequired, isTrue);
      expect(controller.accountSyncState, isNull);

      await controller.verifyAccountMfa(
        baseUrl: server.accountBaseUrl,
        code: server.loginCode,
      );

      expect(controller.accountSignedIn, isTrue);
      expect(controller.accountMfaRequired, isFalse);
      expect(controller.accountSession?.mfaEnabled, isTrue);
      expect(controller.accountSyncState?.syncState, 'ready');
    },
  );

  test(
    'SettingsController preserves local overrides across a second remote sync',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-settings-account-overrides-',
      );
      addTearDown(() async => _deleteDirectoryBestEffort(tempDirectory));
      final store = _createIsolatedStore(tempDirectory.path);
      addTearDown(store.dispose);

      final client = _MutableAccountRuntimeClient();
      final controller = SettingsController(
        store,
        accountClientFactory: (_) => client,
      );
      await controller.initialize();
      await controller.saveSnapshot(
        SettingsSnapshot.defaults().copyWith(
          accountBaseUrl: _MutableAccountRuntimeClient.accountBaseUrl,
          accountUsername: _MutableAccountRuntimeClient.loginEmail,
        ),
      );

      await controller.loginAccount(
        baseUrl: _MutableAccountRuntimeClient.accountBaseUrl,
        identifier: _MutableAccountRuntimeClient.loginEmail,
        password: _MutableAccountRuntimeClient.loginPassword,
      );

      expect(
        controller.snapshot.aiGateway.baseUrl,
        'https://apisix.account.example/v1',
      );

      await controller.saveSnapshot(
        controller.snapshot.copyWith(
          aiGateway: controller.snapshot.aiGateway.copyWith(
            baseUrl: 'https://local-ai.example.com/v1',
          ),
        ),
      );

      expect(
        (await store.loadAccountSyncState())
            ?.overrideFlags[kAccountOverrideAiGatewayBaseUrl],
        isTrue,
      );

      client.profileResponse = AccountProfileResponse(
        profile: client.profileResponse.profile.copyWith(
          apisixUrl: 'https://apisix.second.example/v1',
          vaultNamespace: 'team-b',
        ),
        profileScope: client.profileResponse.profileScope,
        tokenConfigured: client.profileResponse.tokenConfigured,
      );

      final result = await controller.syncAccountSettings(
        baseUrl: _MutableAccountRuntimeClient.accountBaseUrl,
      );

      expect(result.state, 'ready');
      expect(
        controller.snapshot.aiGateway.baseUrl,
        'https://local-ai.example.com/v1',
      );
      expect(controller.snapshot.vault.namespace, 'team-b');
      expect(
        controller.accountSyncState?.syncedDefaults.apisixUrl,
        'https://apisix.second.example/v1',
      );
    },
  );

  test(
    'SettingsController logout clears session but keeps synced defaults and override flags',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-settings-account-logout-',
      );
      addTearDown(() async => _deleteDirectoryBestEffort(tempDirectory));
      final store = _createIsolatedStore(tempDirectory.path);
      addTearDown(store.dispose);

      final client = _MutableAccountRuntimeClient();
      final controller = SettingsController(
        store,
        accountClientFactory: (_) => client,
      );
      await controller.initialize();
      await controller.saveSnapshot(
        SettingsSnapshot.defaults().copyWith(
          accountBaseUrl: _MutableAccountRuntimeClient.accountBaseUrl,
          accountUsername: _MutableAccountRuntimeClient.loginEmail,
        ),
      );

      await controller.loginAccount(
        baseUrl: _MutableAccountRuntimeClient.accountBaseUrl,
        identifier: _MutableAccountRuntimeClient.loginEmail,
        password: _MutableAccountRuntimeClient.loginPassword,
      );
      await controller.saveSnapshot(
        controller.snapshot.copyWith(
          aiGateway: controller.snapshot.aiGateway.copyWith(
            baseUrl: 'https://local-ai.example.com/v1',
          ),
        ),
      );

      await controller.logoutAccount();

      expect(controller.accountSignedIn, isFalse);
      expect(await store.loadAccountSessionToken(), isNull);
      expect(await store.loadAccountSessionUserId(), isNull);
      expect(await store.loadAccountSessionIdentifier(), isNull);
      expect(await store.loadAccountSessionSummary(), isNull);
      expect(await store.loadAccountSyncState(), isNotNull);
      expect(controller.snapshot.aiGateway.baseUrl, 'https://local-ai.example.com/v1');
      expect(controller.snapshot.accountLocalMode, isTrue);
      expect(
        (await store.loadAccountSyncState())
            ?.overrideFlags[kAccountOverrideAiGatewayBaseUrl],
        isTrue,
      );
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

class _MutableAccountRuntimeClient extends AccountRuntimeClient {
  _MutableAccountRuntimeClient() : super(baseUrl: accountBaseUrl);

  static const String accountBaseUrl = 'https://accounts.widget.test';
  static const String loginEmail = 'user@example.com';
  static const String loginPassword = 'correct-password';
  static const String sessionToken = 'account-session-token';

  AccountProfileResponse profileResponse = AccountProfileResponse(
    profile: AccountRemoteProfile.defaults().copyWith(
      openclawUrl: 'https://openclaw.account.example',
      openclawOrigin: 'https://openclaw.account.example',
      vaultUrl: accountBaseUrl,
      vaultNamespace: 'team-a',
      apisixUrl: 'https://apisix.account.example/v1',
      secretLocators: const <AccountSecretLocator>[
        AccountSecretLocator(
          id: 'locator-openclaw',
          provider: 'vault',
          secretPath: 'kv/openclaw',
          secretKey: 'OPENCLAW_GATEWAY_TOKEN',
          target: kAccountManagedSecretTargetOpenclawGatewayToken,
          required: true,
        ),
        AccountSecretLocator(
          id: 'locator-ai-gateway',
          provider: 'vault',
          secretPath: 'kv/apisix',
          secretKey: 'AI_GATEWAY_ACCESS_TOKEN',
          target: kAccountManagedSecretTargetAIGatewayAccessToken,
          required: true,
        ),
        AccountSecretLocator(
          id: 'locator-ollama',
          provider: 'vault',
          secretPath: 'kv/ollama',
          secretKey: 'OLLAMA_API_KEY',
          target: kAccountManagedSecretTargetOllamaCloudApiKey,
          required: false,
        ),
      ],
    ),
    profileScope: 'user',
    tokenConfigured: const AccountTokenConfigured(
      openclaw: true,
      vault: false,
      apisix: true,
    ),
  );

  @override
  Future<Map<String, dynamic>> login({
    required String identifier,
    required String password,
  }) async {
    if (identifier != loginEmail || password != loginPassword) {
      throw const AccountRuntimeException(
        statusCode: 401,
        errorCode: 'invalid_credentials',
        message: 'invalid credentials',
      );
    }
    return <String, dynamic>{
      'message': 'login successful',
      'token': sessionToken,
      'access_token': sessionToken,
      'expiresAt': DateTime.utc(2030, 1, 1).toIso8601String(),
      'mfaRequired': false,
      'mfa_required': false,
      'user': <String, dynamic>{
        'id': 'user-1',
        'email': loginEmail,
        'name': 'Account User',
        'role': 'operator',
        'mfaEnabled': false,
      },
    };
  }

  @override
  Future<AccountSessionSummary> loadSession({required String token}) async {
    if (token != sessionToken) {
      throw const AccountRuntimeException(
        statusCode: 401,
        errorCode: 'session_not_found',
        message: 'session not found',
      );
    }
    return const AccountSessionSummary(
      userId: 'user-1',
      email: loginEmail,
      name: 'Account User',
      role: 'operator',
      mfaEnabled: false,
    );
  }

  @override
  Future<AccountProfileResponse> loadProfile({required String token}) async {
    if (token != sessionToken) {
      throw const AccountRuntimeException(
        statusCode: 401,
        errorCode: 'session_not_found',
        message: 'session not found',
      );
    }
    return profileResponse;
  }
}
