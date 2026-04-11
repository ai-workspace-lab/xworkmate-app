import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/runtime_controllers.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsController account logout', () {
    test(
      'clears synced account state, managed secrets, and cloud summary',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'xworkmate-settings-account-test-',
        );
        final store = SecureConfigStore(
          enableSecureStorage: false,
          appDataRootPathResolver: () async => '${root.path}/settings.sqlite3',
          secretRootPathResolver: () async => root.path,
          supportRootPathResolver: () async => root.path,
        );
        final controller = SettingsController(store);
        addTearDown(() async {
          controller.dispose();
          store.dispose();
          if (await root.exists()) {
            await root.delete(recursive: true);
          }
        });

        await store.initialize();
        await controller.initialize();

        await store.saveAccountSessionToken('session-token');
        await store.saveAccountSessionSummary(
          const AccountSessionSummary(
            userId: 'u-1',
            email: 'review@svc.plus',
            name: 'Review',
            role: 'member',
            mfaEnabled: false,
          ),
        );
        await store.saveAccountSessionIdentifier('review@svc.plus');
        await store.saveAccountManagedSecret(
          target: kAccountManagedSecretTargetAIGatewayAccessToken,
          value: 'managed-secret',
        );
        await store.saveAccountManagedSecret(
          target: kAccountManagedSecretTargetOpenclawGatewayToken,
          value: 'bridge-token',
        );
        await store.saveAccountSyncState(
          AccountSyncState.defaults().copyWith(
            syncState: 'ready',
            syncMessage: 'Bridge access synced',
            lastSyncAtMs: 123456789,
            lastSyncSource: 'https://xworkmate-bridge.svc.plus',
            profileScope: 'bridge',
            tokenConfigured: const AccountTokenConfigured(
              openclaw: true,
              vault: false,
              apisix: false,
            ),
          ),
        );
        await controller.saveSnapshot(
          controller.snapshot.copyWith(
            accountBaseUrl: 'https://accounts.svc.plus',
            accountUsername: 'review@svc.plus',
            accountLocalMode: false,
            acpBridgeServerModeConfig: controller
                .snapshot
                .acpBridgeServerModeConfig
                .copyWith(
                  cloudSynced: controller
                      .snapshot
                      .acpBridgeServerModeConfig
                      .cloudSynced
                      .copyWith(
                        accountBaseUrl: 'https://accounts.svc.plus',
                        accountIdentifier: 'review@svc.plus',
                        lastSyncAt: 123456789,
                        remoteServerSummary:
                            const AcpBridgeServerRemoteServerSummary(
                              endpoint: 'https://xworkmate-bridge.svc.plus',
                              hasAdvancedOverrides: false,
                            ),
                      ),
                ),
          ),
        );

        await controller.logoutAccount();

        expect(await store.loadAccountSessionToken(), isNull);
        expect(await store.loadAccountSessionSummary(), isNull);
        expect(await store.loadAccountSessionIdentifier(), isNull);
        expect(
          await store.loadAccountManagedSecret(
            target: kAccountManagedSecretTargetAIGatewayAccessToken,
          ),
          isNull,
        );
        expect(
          await store.loadAccountManagedSecret(
            target: kAccountManagedSecretTargetOpenclawGatewayToken,
          ),
          isNull,
        );
        expect(await store.loadAccountSyncState(), isNull);

        expect(controller.accountSignedIn, isFalse);
        expect(controller.accountStatus, 'Signed out');
        expect(controller.accountSyncState, isNull);
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
        expect(
          controller.snapshot.acpBridgeServerModeConfig.cloudSynced.lastSyncAt,
          0,
        );
        expect(
          controller
              .snapshot
              .acpBridgeServerModeConfig
              .cloudSynced
              .remoteServerSummary
              .endpoint,
          isEmpty,
        );
      },
    );
  });
}
