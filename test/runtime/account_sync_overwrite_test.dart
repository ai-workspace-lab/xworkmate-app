import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/account_runtime_client.dart';
import 'package:xworkmate/runtime/runtime_controllers.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('syncAccountSettings overwrite policy', () {
    test(
      'rewrites only bridge-owned auth metadata and removes old synced secret refs',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'xworkmate-account-sync-overwrite-',
        );
        final store = SecureConfigStore(
          enableSecureStorage: false,
          appDataRootPathResolver: () async => root.path,
          secretRootPathResolver: () async => root.path,
          supportRootPathResolver: () async => root.path,
        );
        final controller = SettingsController(
          store,
          accountClientFactory: (_) => _FakeAccountRuntimeClient(),
        );
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

        await controller.saveSnapshot(
          controller.snapshot.copyWith(
            accountBaseUrl: 'https://accounts.svc.plus',
            accountUsername: 'review@svc.plus',
            accountLocalMode: true,
            gatewayProfiles:
                controller.snapshot.gatewayProfiles.toList(growable: false)
                  ..[kGatewayRemoteProfileIndex] = controller
                      .snapshot
                      .gatewayProfiles[kGatewayRemoteProfileIndex]
                      .copyWith(
                        host: 'local.example.com',
                        port: 7443,
                        tokenRef: 'local_ref',
                      ),
            vault: controller.snapshot.vault.copyWith(
              address: 'https://local-vault.example.com',
              namespace: 'local',
            ),
            aiGateway: controller.snapshot.aiGateway.copyWith(
              baseUrl: 'https://local-apisix.example.com',
              apiKeyRef: kAccountManagedSecretTargetAIGatewayAccessToken,
            ),
            ollamaCloud: controller.snapshot.ollamaCloud.copyWith(
              apiKeyRef: kAccountManagedSecretTargetOllamaCloudApiKey,
            ),
          ),
        );
        await store.saveAccountManagedSecret(
          target: kAccountManagedSecretTargetAIGatewayAccessToken,
          value: 'stale-ai-token',
        );
        await store.saveAccountManagedSecret(
          target: kAccountManagedSecretTargetOllamaCloudApiKey,
          value: 'stale-ollama-token',
        );
        await store.saveAccountManagedSecret(
          target: kAccountManagedSecretTargetBridgeAuthToken,
          value: 'bridge-token',
        );

        final first = await controller.syncAccountSettings(
          baseUrl: 'https://accounts.svc.plus',
        );
        expect(first.state, 'ready');
        expect(
          controller.snapshot.gatewayProfiles[kGatewayRemoteProfileIndex].host,
          'local.example.com',
        );
        expect(
          controller
              .snapshot
              .gatewayProfiles[kGatewayRemoteProfileIndex]
              .tokenRef,
          'local_ref',
        );
        expect(
          controller.snapshot.vault.address,
          'https://local-vault.example.com',
        );
        expect(controller.snapshot.vault.namespace, 'local');
        expect(
          controller.snapshot.aiGateway.baseUrl,
          'https://local-apisix.example.com',
        );
        expect(
          controller.snapshot.aiGateway.apiKeyRef,
          AiGatewayProfile.defaults().apiKeyRef,
        );
        expect(
          controller.snapshot.ollamaCloud.apiKeyRef,
          OllamaCloudConfig.defaults().apiKeyRef,
        );
        expect(controller.snapshot.accountLocalMode, isFalse);
        expect(controller.accountSyncState?.profileScope, 'bridge');
        expect(controller.accountSyncState?.tokenConfigured.bridge, isTrue);
        expect(controller.accountSyncState?.tokenConfigured.apisix, isFalse);
        expect(
          await store.loadAccountManagedSecret(
            target: kAccountManagedSecretTargetBridgeAuthToken,
          ),
          'bridge-token',
        );
        expect(
          await store.loadAccountManagedSecret(
            target: kAccountManagedSecretTargetAIGatewayAccessToken,
          ),
          isNull,
        );
        expect(
          await store.loadAccountManagedSecret(
            target: kAccountManagedSecretTargetOllamaCloudApiKey,
          ),
          isNull,
        );
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

        await controller.saveSnapshot(
          controller.snapshot.copyWith(
            vault: controller.snapshot.vault.copyWith(
              address: 'https://edited.example.com',
            ),
            aiGateway: controller.snapshot.aiGateway.copyWith(
              baseUrl: 'https://edited-apisix.example.com',
            ),
          ),
        );

        final second = await controller.syncAccountSettings(
          baseUrl: 'https://accounts.svc.plus',
        );
        expect(second.state, 'ready');
        expect(controller.snapshot.vault.address, 'https://edited.example.com');
        expect(
          controller.snapshot.aiGateway.baseUrl,
          'https://edited-apisix.example.com',
        );
        expect(
          controller
              .snapshot
              .acpBridgeServerModeConfig
              .cloudSynced
              .remoteServerSummary
              .endpoint,
          'https://xworkmate-bridge.svc.plus',
        );

        final rawSyncState = await store.loadSupportJson(
          'account/sync_state.json',
        );
        expect(rawSyncState, isNotNull);
        expect(rawSyncState!.containsKey('overrideFlags'), isFalse);
        expect(rawSyncState['syncState'], 'ready');
        expect(rawSyncState['lastSyncError'], isEmpty);
      },
    );
  });
}

class _FakeAccountRuntimeClient extends AccountRuntimeClient {
  _FakeAccountRuntimeClient() : super(baseUrl: 'https://accounts.svc.plus');
}
