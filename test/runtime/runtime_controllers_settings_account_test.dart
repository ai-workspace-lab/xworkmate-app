import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/runtime_controllers.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsController account logout', () {
    test('clears synced account state, managed secrets, and cloud summary', () async {
      final root = await Directory.systemTemp.createTemp(
        'xworkmate-settings-account-test-',
      );
      final store = SecureConfigStore(
        enableSecureStorage: false,
        databasePathResolver: () async => '${root.path}/settings.sqlite3',
        fallbackDirectoryPathResolver: () async => root.path,
        defaultSupportDirectoryPathResolver: () async => root.path,
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
      await store.saveAccountSyncState(
        AccountSyncState.defaults().copyWith(
          syncState: 'ready',
          syncMessage: 'Remote defaults synced',
          lastSyncAtMs: 123456789,
          lastSyncSource: 'https://accounts.svc.plus',
          syncedDefaults: AccountRemoteProfile.defaults().copyWith(
            openclawUrl: 'wss://gateway.svc.plus',
            apisixUrl: 'https://apisix.svc.plus',
          ),
        ),
      );
      await controller.saveSnapshot(
        controller.snapshot.copyWith(
          accountBaseUrl: 'https://accounts.svc.plus',
          accountUsername: 'review@svc.plus',
          accountLocalMode: false,
          acpBridgeServerModeConfig: controller.snapshot.acpBridgeServerModeConfig
              .copyWith(
                cloudSynced: controller
                    .snapshot
                    .acpBridgeServerModeConfig
                    .cloudSynced
                    .copyWith(
                      accountBaseUrl: 'https://accounts.svc.plus',
                      accountIdentifier: 'review@svc.plus',
                      lastSyncAt: 123456789,
                      remoteServerSummary: const AcpBridgeServerRemoteServerSummary(
                        endpoint: 'wss://gateway.svc.plus',
                        hasAdvancedOverrides: false,
                      ),
                    ),
              ),
        ),
        recordAccountOverrides: false,
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
      expect(await store.loadAccountSyncState(), isNull);

      expect(controller.accountSignedIn, isFalse);
      expect(controller.accountStatus, 'Signed out');
      expect(controller.accountSyncState, isNull);
      expect(controller.snapshot.accountLocalMode, isTrue);
      expect(
        controller.snapshot.acpBridgeServerModeConfig.cloudSynced.accountIdentifier,
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
    });
  });
}
