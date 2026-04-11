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
      'always overwrites sync-owned fields and stores metadata only',
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
              apiKeyRef: 'local_ai_ref',
            ),
            ollamaCloud: controller.snapshot.ollamaCloud.copyWith(
              apiKeyRef: 'local_ollama_ref',
            ),
          ),
        );

        final first = await controller.syncAccountSettings(
          baseUrl: 'https://accounts.svc.plus',
        );
        expect(first.state, 'ready');
        expect(
          controller.snapshot.gatewayProfiles[kGatewayRemoteProfileIndex].host,
          'remote.gateway.svc.plus',
        );
        expect(
          controller
              .snapshot
              .gatewayProfiles[kGatewayRemoteProfileIndex]
              .tokenRef,
          kAccountManagedSecretTargetOpenclawGatewayToken,
        );
        expect(controller.snapshot.vault.address, 'https://vault.svc.plus');
        expect(controller.snapshot.vault.namespace, 'prod');
        expect(
          controller.snapshot.aiGateway.baseUrl,
          'https://apisix.svc.plus',
        );
        expect(
          controller.snapshot.aiGateway.apiKeyRef,
          kAccountManagedSecretTargetAIGatewayAccessToken,
        );
        expect(
          controller.snapshot.ollamaCloud.apiKeyRef,
          kAccountManagedSecretTargetOllamaCloudApiKey,
        );
        expect(controller.snapshot.accountLocalMode, isFalse);

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
        expect(controller.snapshot.vault.address, 'https://vault.svc.plus');
        expect(
          controller.snapshot.aiGateway.baseUrl,
          'https://apisix.svc.plus',
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

  @override
  Future<AccountProfileResponse> loadProfile({required String token}) async {
    expect(token, 'session-token');
    return AccountProfileResponse(
      profile: AccountRemoteProfile.defaults().copyWith(
        openclawUrl: 'wss://remote.gateway.svc.plus',
        vaultUrl: 'https://vault.svc.plus',
        vaultNamespace: 'prod',
        apisixUrl: 'https://apisix.svc.plus',
        secretLocators: const <AccountSecretLocator>[
          AccountSecretLocator(
            id: 'gateway',
            provider: 'vault',
            secretPath: 'kv/xworkmate',
            secretKey: 'gateway_token',
            target: kAccountManagedSecretTargetOpenclawGatewayToken,
            required: true,
          ),
          AccountSecretLocator(
            id: 'ai',
            provider: 'vault',
            secretPath: 'kv/xworkmate',
            secretKey: 'ai_gateway_token',
            target: kAccountManagedSecretTargetAIGatewayAccessToken,
            required: true,
          ),
          AccountSecretLocator(
            id: 'ollama',
            provider: 'vault',
            secretPath: 'kv/xworkmate',
            secretKey: 'ollama_key',
            target: kAccountManagedSecretTargetOllamaCloudApiKey,
            required: true,
          ),
        ],
      ),
      profileScope: 'workspace',
      tokenConfigured: const AccountTokenConfigured(
        openclaw: true,
        vault: true,
        apisix: true,
      ),
    );
  }
}
