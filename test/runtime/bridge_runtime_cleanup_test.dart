import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/runtime/mode_switcher.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';

void main() {
  group('Bridge runtime cleanup', () {
    test('resolves the current synced bridge endpoint before env leftovers', () async {
      final storeRoot = await Directory.systemTemp.createTemp(
        'xworkmate-bridge-runtime-cleanup-',
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
      await store.saveAccountSyncState(
        AccountSyncState.defaults().copyWith(
          syncedDefaults: AccountRemoteProfile.defaults().copyWith(
            bridgeServerUrl: 'https://xworkmate-bridge-alt.svc.plus',
          ),
          syncState: 'ready',
        ),
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
        'https://xworkmate-bridge-alt.svc.plus',
      );
      expect(
        controller
            .resolveExternalAcpEndpointForTargetInternal(
              AssistantExecutionTarget.gateway,
            )
            ?.toString(),
        'https://xworkmate-bridge-alt.svc.plus',
      );
    });

    test('falls back to the managed bridge endpoint without BRIDGE_SERVER_URL', () {
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
    });

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
