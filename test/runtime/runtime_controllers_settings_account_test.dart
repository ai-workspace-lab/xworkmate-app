import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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

        final controller = SettingsController(store);
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

      final controller = SettingsController(store);
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
    });

    test(
      'recovers bridge sync state from cloud-synced snapshot when support state is missing',
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

        expect(controller.accountSyncState, isNotNull);
        expect(
          controller.accountSyncState!.syncedDefaults.bridgeServerUrl,
          'https://bridge.svc.plus',
        );
        expect(controller.accountSyncState!.syncState, 'ready');
        expect(controller.accountSyncState!.profileScope, 'bridge');

        final persisted = await store.loadAccountSyncState();
        expect(persisted, isNotNull);
        expect(
          persisted!.syncedDefaults.bridgeServerUrl,
          'https://bridge.svc.plus',
        );
      },
    );
  });
}
