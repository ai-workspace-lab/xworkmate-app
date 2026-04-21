import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/runtime/mode_switcher.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';

void main() {
  group('Bridge runtime cleanup', () {
    test(
      'keeps the managed bridge endpoint fixed even when account sync carries a bridge URL',
      () async {
        final storeRoot = await Directory.systemTemp.createTemp(
          'xworkmate-bridge-runtime-cleanup-',
        );
        addTearDown(() async {
          if (await storeRoot.exists()) {
            try {
              await storeRoot.delete(recursive: true);
            } on FileSystemException {
              // Best-effort cleanup. Flutter tests can still hold temporary files
              // briefly when teardown starts.
            }
          }
        });

        final store = SecureConfigStore(
          secretRootPathResolver: () async => '${storeRoot.path}/secrets',
          appDataRootPathResolver: () async => '${storeRoot.path}/app-data',
          supportRootPathResolver: () async => '${storeRoot.path}/support',
          enableSecureStorage: false,
        );
        await store.initialize();
        await store.saveAccountSyncState(
          AccountSyncState.defaults().copyWith(
            syncedDefaults: AccountRemoteProfile.defaults().copyWith(
              bridgeServerUrl: 'https://xworkmate-bridge-alt.svc.plus',
            ),
            syncState: 'ready',
            tokenConfigured: const AccountTokenConfigured(
              bridge: true,
              vault: false,
              apisix: false,
            ),
          ),
        );
        await store.saveAccountManagedSecret(
          target: kAccountManagedSecretTargetBridgeAuthToken,
          value: 'bridge-token',
        );

        final controller = AppController(
          store: store,
          environmentOverride: const <String, String>{
            'BRIDGE_SERVER_URL': 'https://stale.example.invalid',
          },
        );
        addTearDown(controller.dispose);
        await controller.settingsControllerInternal.initialize();

        expect(
          controller.resolveBridgeAcpEndpointInternal()?.toString(),
          kManagedBridgeServerUrl,
        );
        expect(
          controller
              .resolveExternalAcpEndpointForTargetInternal(
                AssistantExecutionTarget.gateway,
              )
              ?.toString(),
          kManagedBridgeServerUrl,
        );
        expect(await store.loadAccountSyncState(), isNotNull);
        expect(
          (await store.loadAccountSyncState())!.syncedDefaults.bridgeServerUrl,
          'https://xworkmate-bridge-alt.svc.plus',
        );
      },
    );

    test(
      'keeps the managed bridge endpoint fixed when signed out',
      () {
        final controller = AppController(
          environmentOverride: const <String, String>{
            'BRIDGE_SERVER_URL': 'https://stale.example.invalid',
          },
        );
        addTearDown(controller.dispose);

        expect(
          controller.resolveBridgeAcpEndpointInternal()?.toString(),
          kManagedBridgeServerUrl,
        );
      },
    );

    test(
      'resolves raw bridge token only for the current managed bridge endpoint',
      () async {
        final storeRoot = await Directory.systemTemp.createTemp(
          'xworkmate-bridge-auth-resolver-',
        );
        addTearDown(() async {
          if (await storeRoot.exists()) {
            try {
              await storeRoot.delete(recursive: true);
            } on FileSystemException {
              // Temp cleanup is best effort here. The controller may still be
              // releasing files when teardown starts.
            }
          }
        });

        final store = SecureConfigStore(
          secretRootPathResolver: () async => '${storeRoot.path}/secrets',
          appDataRootPathResolver: () async => '${storeRoot.path}/app-data',
          supportRootPathResolver: () async => '${storeRoot.path}/support',
          enableSecureStorage: false,
        );
        await store.initialize();
        await store.saveAccountManagedSecret(
          target: kAccountManagedSecretTargetBridgeAuthToken,
          value: 'bridge-token',
        );
        await store.saveAccountSyncState(
          AccountSyncState.defaults().copyWith(
            syncedDefaults: AccountRemoteProfile.defaults().copyWith(
              bridgeServerUrl: kManagedBridgeServerUrl,
            ),
            syncState: 'ready',
            tokenConfigured: const AccountTokenConfigured(
              bridge: true,
              vault: false,
              apisix: false,
            ),
          ),
        );

        final controller = AppController(store: store);
        addTearDown(controller.dispose);
        await controller.settingsControllerInternal.initialize();

        final bridgeHeader = await controller.resolveGatewayAcpAuthorizationHeaderInternal(
          Uri.parse('$kManagedBridgeServerUrl/acp/rpc'),
        );
        final unrelatedHeader = await controller
            .resolveGatewayAcpAuthorizationHeaderInternal(
              Uri.parse('https://unrelated.example.com/acp/rpc'),
            );

        expect(bridgeHeader, 'bridge-token');
        expect(unrelatedHeader, isNull);
      },
    );

    test(
      'runtime coordinator only exposes remote and offline gateway modes',
      () {
        final controller = AppController();
        addTearDown(controller.dispose);

        expect(
          controller.runtimeCoordinatorInternal.getAvailableModes(),
          const <GatewayMode>[GatewayMode.remote, GatewayMode.offline],
        );
      },
    );
  });
}
