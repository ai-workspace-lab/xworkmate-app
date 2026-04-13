import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/account_runtime_client.dart';
import 'package:xworkmate/runtime/runtime_controllers.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';

void main() {
  group('SettingsController account sync', () {
    test(
      'updates in-memory blocked state when bridge authorization is unavailable',
      () async {
        final storeRoot = await Directory.systemTemp.createTemp(
          'xworkmate-account-sync-',
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
        await store.saveSettingsSnapshot(
          SettingsSnapshot.defaults().copyWith(
            accountBaseUrl: 'https://accounts.svc.plus',
          ),
        );
        await store.saveAccountSessionToken('session-token');

        final client = _FakeAccountRuntimeClient(
          loginPayload: const <String, dynamic>{},
          profilePayload: const <String, dynamic>{},
        );
        final controller = SettingsController(
          store,
          accountClientFactory: (_) => client,
        );
        addTearDown(controller.dispose);
        await controller.initialize();

        final result = await controller.syncAccountSettings(
          baseUrl: 'https://accounts.svc.plus',
        );

        expect(result.state, 'blocked');
        expect(result.message, 'Bridge authorization is unavailable');
        expect(controller.accountSyncState, isNotNull);
        expect(controller.accountSyncState!.syncState, 'blocked');
        expect(
          controller.accountSyncState!.syncMessage,
          'Bridge authorization is unavailable',
        );
        expect(controller.accountSyncState!.profileScope, 'bridge');
        expect(
          controller.accountSyncState!.lastSyncError,
          'Bridge authorization is unavailable',
        );
        expect(controller.accountStatus, 'Bridge authorization is unavailable');
        expect(client.loadProfileCallCount, 1);
      },
    );

    test('login sync stores BRIDGE_AUTH_TOKEN from login payload', () async {
        final storeRoot = await Directory.systemTemp.createTemp(
          'xworkmate-account-sync-uppercase-token-',
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
        await store.saveSettingsSnapshot(
          SettingsSnapshot.defaults().copyWith(
            accountBaseUrl: 'https://accounts.svc.plus',
          ),
        );

        final controller = SettingsController(
          store,
          accountClientFactory: (_) => _FakeAccountRuntimeClient(
            loginPayload: <String, dynamic>{
              'token': 'session-token',
              'BRIDGE_AUTH_TOKEN': 'bridge-token-from-login',
              'BRIDGE_SERVER_URL': 'https://xworkmate-bridge-alt.svc.plus',
              'user': <String, dynamic>{
                'id': 'user-1',
                'email': 'review@svc.plus',
              },
            },
          ),
        );
        addTearDown(controller.dispose);
        await controller.initialize();

        await controller.loginAccount(
          baseUrl: 'https://accounts.svc.plus',
          identifier: 'review@svc.plus',
          password: 'password',
        );

        expect(controller.accountSyncState, isNotNull);
        expect(controller.accountSyncState!.syncState, 'ready');
        expect(
          controller.accountSyncState!.syncedDefaults.bridgeServerUrl,
          'https://xworkmate-bridge-alt.svc.plus',
        );
        expect(
          controller
              .snapshot
              .acpBridgeServerModeConfig
              .cloudSynced
              .remoteServerSummary
              .endpoint,
          'https://xworkmate-bridge-alt.svc.plus',
        );
        expect(
          await store.loadAccountManagedSecret(
            target: kAccountManagedSecretTargetBridgeAuthToken,
          ),
          'bridge-token-from-login',
        );
      },
    );

    test(
      'login sync ignores legacy INTERNAL_SERVICE_TOKEN fallback',
      () async {
        final storeRoot = await Directory.systemTemp.createTemp(
          'xworkmate-account-sync-legacy-token-',
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
        await store.saveSettingsSnapshot(
          SettingsSnapshot.defaults().copyWith(
            accountBaseUrl: 'https://accounts.svc.plus',
          ),
        );

        final controller = SettingsController(
          store,
          accountClientFactory: (_) => _FakeAccountRuntimeClient(
            loginPayload: <String, dynamic>{
              'token': 'session-token',
              'INTERNAL_SERVICE_TOKEN': 'legacy-bridge-token',
              'BRIDGE_SERVER_URL': 'https://xworkmate-bridge-alt.svc.plus',
              'user': <String, dynamic>{
                'id': 'user-1',
                'email': 'review@svc.plus',
              },
            },
          ),
        );
        addTearDown(controller.dispose);
        await controller.initialize();

        await controller.loginAccount(
          baseUrl: 'https://accounts.svc.plus',
          identifier: 'review@svc.plus',
          password: 'password',
        );

        expect(controller.accountSyncState, isNotNull);
        expect(controller.accountSyncState!.syncState, 'blocked');
        expect(
          await store.loadAccountManagedSecret(
            target: kAccountManagedSecretTargetBridgeAuthToken,
          ),
          isNull,
        );
      },
    );

    test('syncAccountSettings pins the managed bridge cloud entry', () async {
      final storeRoot = await Directory.systemTemp.createTemp(
        'xworkmate-account-managed-bridge-',
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
      await store.saveSettingsSnapshot(
        SettingsSnapshot.defaults().copyWith(
          accountBaseUrl: 'https://accounts.svc.plus',
          accountUsername: 'review@svc.plus',
        ),
      );
      await store.saveAccountSessionToken('session-token');
      await store.saveAccountManagedSecret(
        target: kAccountManagedSecretTargetBridgeAuthToken,
        value: 'bridge-token',
      );

      final client = _FakeAccountRuntimeClient(
        loginPayload: const <String, dynamic>{},
        profilePayload: const <String, dynamic>{},
      );
      final controller = SettingsController(
        store,
        accountClientFactory: (_) => client,
      );
      addTearDown(controller.dispose);
      await controller.initialize();

      final result = await controller.syncAccountSettings(
        baseUrl: 'https://accounts.svc.plus',
      );

      expect(result.state, 'ready');
      expect(controller.accountSyncState, isNotNull);
      expect(
        controller.accountSyncState!.syncedDefaults.bridgeServerUrl,
        kManagedBridgeServerUrl,
      );
      expect(
        controller
            .snapshot
            .acpBridgeServerModeConfig
            .cloudSynced
            .remoteServerSummary
            .endpoint,
        kManagedBridgeServerUrl,
      );
      expect(client.loadProfileCallCount, 1);
    });

    test(
      'syncAccountSettings refreshes managed bridge contract from protected account profile',
      () async {
        final storeRoot = await Directory.systemTemp.createTemp(
          'xworkmate-account-managed-bridge-refresh-',
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
        await store.saveSettingsSnapshot(
          SettingsSnapshot.defaults().copyWith(
            accountBaseUrl: 'https://accounts.svc.plus',
            accountUsername: 'review@svc.plus',
          ),
        );
        await store.saveAccountSessionToken('session-token');
        await store.saveAccountManagedSecret(
          target: kAccountManagedSecretTargetBridgeAuthToken,
          value: 'stale-bridge-token',
        );

        final client = _FakeAccountRuntimeClient(
          loginPayload: const <String, dynamic>{},
          profilePayload: <String, dynamic>{
            'BRIDGE_AUTH_TOKEN': 'fresh-bridge-token',
            'BRIDGE_SERVER_URL': 'https://xworkmate-bridge-new.svc.plus',
            'user': <String, dynamic>{
              'id': 'user-1',
              'email': 'review@svc.plus',
            },
          },
        );
        final controller = SettingsController(
          store,
          accountClientFactory: (_) => client,
        );
        addTearDown(controller.dispose);
        await controller.initialize();

        final result = await controller.syncAccountSettings(
          baseUrl: 'https://accounts.svc.plus',
        );

        expect(result.state, 'ready');
        expect(client.loadProfileCallCount, 1);
        expect(
          await store.loadAccountManagedSecret(
            target: kAccountManagedSecretTargetBridgeAuthToken,
          ),
          'fresh-bridge-token',
        );
        expect(
          controller.accountSyncState!.syncedDefaults.bridgeServerUrl,
          'https://xworkmate-bridge-new.svc.plus',
        );
      },
    );

    test(
      'does not recover bridge sync state from stale cloud-synced snapshot state',
      () async {
        final storeRoot = await Directory.systemTemp.createTemp(
          'xworkmate-account-recover-',
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
        await store.saveSettingsSnapshot(
          SettingsSnapshot.defaults().copyWith(
            acpBridgeServerModeConfig: AcpBridgeServerModeConfig.defaults()
                .copyWith(
                  cloudSynced: AcpBridgeServerModeConfig.defaults().cloudSynced
                      .copyWith(
                        lastSyncAt: DateTime(
                          2026,
                          4,
                          12,
                          11,
                        ).millisecondsSinceEpoch,
                        remoteServerSummary:
                            AcpBridgeServerModeConfig.defaults()
                                .cloudSynced
                                .remoteServerSummary
                                .copyWith(endpoint: 'https://bridge.svc.plus'),
                      ),
                ),
          ),
        );
        await store.saveSecretValueByRef(
          kAccountManagedSecretTargetBridgeAuthToken,
          'bridge-token',
        );

        final controller = SettingsController(store);
        addTearDown(controller.dispose);
        await controller.initialize();

        expect(controller.accountSyncState, isNull);
        final persisted = await store.loadAccountSyncState();
        expect(persisted, isNull);
      },
    );
  });
}

class _FakeAccountRuntimeClient extends AccountRuntimeClient {
  _FakeAccountRuntimeClient({
    required this.loginPayload,
    this.profilePayload = const <String, dynamic>{},
  })
    : super(baseUrl: 'https://accounts.svc.plus');

  final Map<String, dynamic> loginPayload;
  final Map<String, dynamic> profilePayload;
  int loadProfileCallCount = 0;

  @override
  Future<Map<String, dynamic>> login({
    required String identifier,
    required String password,
  }) async {
    return loginPayload;
  }

  @override
  Future<Map<String, dynamic>> loadProfile({required String token}) async {
    loadProfileCallCount += 1;
    return profilePayload;
  }
}
