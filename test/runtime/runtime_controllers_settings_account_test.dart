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

    test(
      'disconnectManagedAccountBase switches the snapshot to local mode',
      () async {
        final storeRoot = await Directory.systemTemp.createTemp(
          'xworkmate-account-disconnect-',
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
            accountLocalMode: false,
            accountBaseUrl: 'https://accounts.svc.plus',
            accountUsername: 'review@svc.plus',
            acpBridgeServerModeConfig: AcpBridgeServerModeConfig.defaults()
                .copyWith(
                  cloudSynced: AcpBridgeServerModeConfig.defaults().cloudSynced
                      .copyWith(
                        accountIdentifier: 'review@svc.plus',
                        remoteServerSummary:
                            AcpBridgeServerModeConfig.defaults()
                                .cloudSynced
                                .remoteServerSummary
                                .copyWith(endpoint: 'https://bridge.svc.plus'),
                      ),
                ),
          ),
        );
        await store.saveAccountSyncState(
          AccountSyncState.defaults().copyWith(
            syncState: 'ready',
            syncMessage: 'Bridge access synced',
            profileScope: 'bridge',
            lastSyncAtMs: DateTime(2026, 4, 12, 10).millisecondsSinceEpoch,
          ),
        );

        final controller = SettingsController(store);
        addTearDown(controller.dispose);
        await controller.initialize();

        await controller.disconnectManagedAccountBase();

        expect(controller.snapshot.accountLocalMode, isTrue);
        expect(
          controller
              .snapshot
              .acpBridgeServerModeConfig
              .cloudSynced
              .accountBaseUrl,
          isEmpty,
        );
        expect(
          controller
              .snapshot
              .acpBridgeServerModeConfig
              .cloudSynced
              .accountIdentifier,
          isEmpty,
        );
        expect(controller.accountSyncState, isNotNull);
        expect(controller.accountSyncState!.syncState, 'disconnected');
        expect(
          controller.accountSyncState!.syncMessage,
          'Using local connection settings',
        );
        expect(controller.accountSyncState!.profileScope, 'bridge');
      },
    );
  });
}
