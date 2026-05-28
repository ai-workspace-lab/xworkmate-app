import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/runtime/device_identity_store.dart';
import 'package:xworkmate/runtime/gateway_runtime.dart';
import 'package:xworkmate/runtime/gateway_runtime_session_client.dart';
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

    test('keeps the managed bridge endpoint fixed when signed out', () {
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
        await store.saveAccountSessionToken('session-token');
        await store.saveAccountSessionSummary(
          const AccountSessionSummary(
            userId: 'user-1',
            email: 'review@svc.plus',
            name: 'Review User',
            role: 'reviewer',
            mfaEnabled: true,
          ),
        );
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
            ),
          ),
        );

        final controller = AppController(
          environmentOverride: const <String, String>{},
          store: store,
        );
        addTearDown(controller.dispose);
        await controller.settingsControllerInternal.initialize();

        final bridgeHeader = await controller
            .resolveGatewayAcpAuthorizationHeaderInternal(
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
        final controller = AppController(
          environmentOverride: const <String, String>{},
        );
        addTearDown(controller.dispose);

        expect(
          controller.runtimeCoordinatorInternal.getAvailableModes(),
          const <GatewayMode>[GatewayMode.remote, GatewayMode.offline],
        );
      },
    );

    test(
      'session client bootstrap uses the managed bridge instead of local ACP',
      () async {
        final storeRoot = await Directory.systemTemp.createTemp(
          'xworkmate-bridge-session-bootstrap-',
        );
        addTearDown(() async {
          if (await storeRoot.exists()) {
            try {
              await storeRoot.delete(recursive: true);
            } on FileSystemException {
              // Temp cleanup is best effort while Flutter test teardown releases IO.
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
        final sessionClient = _CapturingGatewayRuntimeSessionClient();
        final runtime = GatewayRuntime(
          store: store,
          identityStore: DeviceIdentityStore(store),
          sessionClient: sessionClient,
          runtimeId: 'runtime-session-bootstrap-test',
        );
        addTearDown(runtime.dispose);
        await runtime.initialize();

        await runtime.ensureBridgeSessionConnected(selectedAgentId: 'codex');

        final request = sessionClient.lastConnectRequest;
        expect(request, isNotNull);
        expect(request!.mode, RuntimeConnectionMode.remote);
        expect(request.host, Uri.parse(kManagedBridgeServerUrl).host);
        expect(request.port, 443);
        expect(request.tls, isTrue);
        expect(request.host, isNot(anyOf('127.0.0.1', 'localhost')));
      },
    );
  });
}

class _CapturingGatewayRuntimeSessionClient
    implements GatewayRuntimeSessionClient {
  final StreamController<GatewayRuntimeSessionUpdate> _updates =
      StreamController<GatewayRuntimeSessionUpdate>.broadcast();

  GatewayRuntimeSessionConnectRequest? lastConnectRequest;

  @override
  Stream<GatewayRuntimeSessionUpdate> get updates => _updates.stream;

  @override
  Future<GatewayRuntimeSessionConnectResult> connect(
    GatewayRuntimeSessionConnectRequest request,
  ) async {
    lastConnectRequest = request;
    return GatewayRuntimeSessionConnectResult(
      snapshot: GatewayConnectionSnapshot.initial(mode: request.mode).copyWith(
        status: RuntimeConnectionStatus.connected,
        statusText: 'Connected',
        remoteAddress: '${request.host}:${request.port}',
        deviceId: request.identity.deviceId,
      ),
      auth: const <String, dynamic>{'role': 'operator'},
      returnedDeviceToken: '',
      raw: const <String, dynamic>{},
    );
  }

  @override
  Future<void> disconnect({required String runtimeId}) async {}

  @override
  Future<dynamic> request({
    required String runtimeId,
    required String method,
    Map<String, dynamic>? params,
    Duration timeout = const Duration(seconds: 15),
  }) {
    throw UnimplementedError('request is not used by this cleanup test');
  }

  @override
  Future<void> dispose() => _updates.close();
}
