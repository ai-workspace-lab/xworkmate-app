import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller_desktop_core.dart';
import 'package:xworkmate/app/app_controller_desktop_external_acp_routing.dart';
import 'package:xworkmate/app/app_controller_desktop_runtime_helpers.dart';
import 'package:xworkmate/app/app_controller_desktop_skill_permissions.dart';
import 'package:xworkmate/app/app_controller_desktop_thread_binding.dart';
import 'package:xworkmate/app/app_controller_desktop_thread_sessions.dart';
import 'package:xworkmate/app/app_controller_desktop_workspace_execution.dart';
import 'package:xworkmate/runtime/codex_config_bridge.dart';
import 'package:xworkmate/runtime/codex_runtime.dart';
import 'package:xworkmate/runtime/device_identity_store.dart';
import 'package:xworkmate/runtime/gateway_runtime.dart';
import 'package:xworkmate/runtime/go_task_service_client.dart';
import 'package:xworkmate/runtime/runtime_coordinator.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('resolveDesktopThreadBindingSnapshotInternal', () {
    const localOwner = ThreadOwnerScope(
      realm: ThreadRealm.local,
      subjectType: ThreadSubjectType.user,
      subjectId: 'u1',
      displayName: 'User',
    );

    TaskThread buildThread({
      required String threadId,
      required ThreadExecutionMode mode,
      required String providerId,
      String latestResolvedProviderId = '',
    }) {
      return TaskThread(
        threadId: threadId,
        ownerScope: localOwner,
        workspaceBinding: const WorkspaceBinding(
          workspaceId: 'ws-1',
          workspaceKind: WorkspaceKind.localFs,
          workspacePath: '/tmp/ws',
          displayPath: '/tmp/ws',
          writable: true,
        ),
        executionBinding: ExecutionBinding(
          executionMode: mode,
          executorId: providerId,
          providerId: providerId,
          endpointId: '',
        ),
        latestResolvedProviderId: latestResolvedProviderId,
      );
    }

    test('prefers the latest record after async binding resumes', () {
      final latestRecord = buildThread(
        threadId: 'thread-1',
        mode: ThreadExecutionMode.localAgent,
        providerId: SingleAgentProvider.opencode.providerId,
      );

      final snapshot = resolveDesktopThreadBindingSnapshotInternal(
        defaultExecutionTarget: AssistantExecutionTarget.gateway,
        latestRecord: latestRecord,
      );

      expect(snapshot.executionTarget, AssistantExecutionTarget.singleAgent);
      expect(
        snapshot.selectedSingleAgentProvider,
        SingleAgentProvider.opencode,
      );
      expect(snapshot.record, same(latestRecord));
    });

    test(
      'keeps an explicit execution override while preserving latest provider',
      () {
        final latestRecord = buildThread(
          threadId: 'thread-2',
          mode: ThreadExecutionMode.localAgent,
          providerId: SingleAgentProvider.opencode.providerId,
        );

        final snapshot = resolveDesktopThreadBindingSnapshotInternal(
          defaultExecutionTarget: AssistantExecutionTarget.gateway,
          executionTargetOverride: AssistantExecutionTarget.gateway,
          latestRecord: latestRecord,
        );

        expect(snapshot.executionTarget, AssistantExecutionTarget.gateway);
        expect(
          snapshot.selectedSingleAgentProvider,
          SingleAgentProvider.opencode,
        );
      },
    );

    test(
      'keeps the stored provider selection separate from resolved provider',
      () {
        final latestRecord = buildThread(
          threadId: 'thread-2b',
          mode: ThreadExecutionMode.localAgent,
          providerId: SingleAgentProvider.opencode.providerId,
          latestResolvedProviderId: SingleAgentProvider.codex.providerId,
        );

        final snapshot = resolveDesktopThreadBindingSnapshotInternal(
          defaultExecutionTarget: AssistantExecutionTarget.gateway,
          latestRecord: latestRecord,
        );

        expect(snapshot.executionTarget, AssistantExecutionTarget.singleAgent);
        expect(
          snapshot.selectedSingleAgentProvider,
          SingleAgentProvider.opencode,
        );
        expect(
          latestRecord.latestResolvedProviderId,
          SingleAgentProvider.codex.providerId,
        );
      },
    );

    test('does not recover provider from stale fallback-only records', () {
      final staleRecord = buildThread(
        threadId: 'thread-3',
        mode: ThreadExecutionMode.gateway,
        providerId: SingleAgentProvider.codex.providerId,
      );

      final snapshot = resolveDesktopThreadBindingSnapshotInternal(
        defaultExecutionTarget: AssistantExecutionTarget.gateway,
        latestRecord: null,
      );

      expect(snapshot.executionTarget, AssistantExecutionTarget.gateway);
      expect(snapshot.selectedSingleAgentProvider.isUnspecified, isTrue);
      expect(snapshot.record, isNull);
      expect(staleRecord.executionBinding.providerId, isNotEmpty);
    });
  });

  group('resolveGatewayExecutionTargetFromVisibleTargets', () {
    test('prefers remote bridge target over silent local fallback', () {
      final target = resolveGatewayExecutionTargetFromVisibleTargets(
        const <AssistantExecutionTarget>[
          AssistantExecutionTarget.singleAgent,
          AssistantExecutionTarget.gateway,
        ],
        currentTarget: AssistantExecutionTarget.singleAgent,
      );

      expect(target, AssistantExecutionTarget.gateway);
    });

    test(
      'falls back to remote when legacy local gateway selection is active',
      () {
        final target = resolveGatewayExecutionTargetFromVisibleTargets(
          const <AssistantExecutionTarget>[AssistantExecutionTarget.gateway],
          currentTarget: AssistantExecutionTarget.gateway,
        );

        expect(target, AssistantExecutionTarget.gateway);
      },
    );
  });

  group('resolveGatewayThreadConnectionStateInternal', () {
    test('uses the current bridge connection address as the only address source', () {
      final state = resolveGatewayThreadConnectionStateInternal(
        target: AssistantExecutionTarget.gateway,
        connection:
            GatewayConnectionSnapshot.initial(
              mode: RuntimeConnectionMode.remote,
            ).copyWith(
              status: RuntimeConnectionStatus.connected,
              remoteAddress: 'bridge.example.internal:443',
            ),
      );

      expect(state.status, RuntimeConnectionStatus.connected);
      expect(state.detailLabel, 'bridge.example.internal:443');
      expect(state.ready, isTrue);
    });

    test('uses current bridge snapshot even when the connection was established locally before', () {
      final state = resolveGatewayThreadConnectionStateInternal(
        target: AssistantExecutionTarget.gateway,
        connection:
            GatewayConnectionSnapshot.initial(
              mode: RuntimeConnectionMode.local,
            ).copyWith(
              status: RuntimeConnectionStatus.connected,
              remoteAddress: 'legacy-loopback:18789',
            ),
      );

      expect(state.status, RuntimeConnectionStatus.connected);
      expect(state.detailLabel, 'legacy-loopback:18789');
      expect(state.ready, isTrue);
    });
  });

  group('assistantConnectionStateForSession', () {
    test(
      'uses bridge connection address instead of thread target profile address',
      () {
        final gateway = _FakeGatewayRuntime(
          GatewayConnectionSnapshot.initial(
            mode: RuntimeConnectionMode.remote,
          ).copyWith(
            status: RuntimeConnectionStatus.connected,
            remoteAddress: 'legacy-loopback:18789',
          ),
        );
        final controller = AppController(
          runtimeCoordinator: RuntimeCoordinator(
            gateway: gateway,
            codex: CodexRuntime(),
            configBridge: CodexConfigBridge(),
          ),
        );
        addTearDown(() async {
          controller.dispose();
          await gateway.disposeTestResources();
        });
        const sessionKey = 'draft:remote-status';
        controller.initializeAssistantThreadContext(
          sessionKey,
          executionTarget: AssistantExecutionTarget.gateway,
        );
        controller.upsertTaskThreadInternal(
          sessionKey,
          executionTarget: AssistantExecutionTarget.gateway,
          executionTargetSource: ThreadSelectionSource.explicit,
        );

        final state = controller.assistantConnectionStateForSession(sessionKey);

        expect(state.status, RuntimeConnectionStatus.connected);
        expect(state.detailLabel, 'legacy-loopback:18789');
        expect(state.ready, isTrue);
      },
    );

    test(
      'treats an advertised bridge catalog provider as ready before the first resolved turn',
      () {
        final controller = AppController();
        addTearDown(controller.dispose);

        const sessionKey = 'draft:single-agent-ready-from-catalog';
        controller.initializeAssistantThreadContext(
          sessionKey,
          executionTarget: AssistantExecutionTarget.singleAgent,
          singleAgentProvider: SingleAgentProvider.codex,
        );
        controller.bridgeProviderCatalogInternal = const <SingleAgentProvider>[
          SingleAgentProvider.codex,
        ];
        controller.upsertTaskThreadInternal(
          sessionKey,
          executionTarget: AssistantExecutionTarget.singleAgent,
          executionTargetSource: ThreadSelectionSource.explicit,
          singleAgentProvider: SingleAgentProvider.codex,
          singleAgentProviderSource: ThreadSelectionSource.explicit,
        );

        expect(
          controller.singleAgentResolvedProviderForSession(sessionKey),
          isNull,
        );
        expect(
          controller.singleAgentCatalogProviderForSession(sessionKey),
          SingleAgentProvider.codex,
        );

        final state = controller.assistantConnectionStateForSession(sessionKey);
        expect(state.status, RuntimeConnectionStatus.connected);
        expect(state.ready, isTrue);
        expect(state.detailLabel, contains('Codex'));
      },
    );
  });

  group('buildExternalAcpRoutingForSessionInternal', () {
    test('never emits explicit provider id for gateway threads', () {
      final controller = AppController();
      addTearDown(controller.dispose);

      const sessionKey = 'draft:routing';
      controller.initializeAssistantThreadContext(
        sessionKey,
        executionTarget: AssistantExecutionTarget.gateway,
        singleAgentProvider: SingleAgentProvider.opencode,
      );
      controller.upsertTaskThreadInternal(
        sessionKey,
        executionTarget: AssistantExecutionTarget.gateway,
        executionTargetSource: ThreadSelectionSource.explicit,
        singleAgentProvider: SingleAgentProvider.opencode,
        singleAgentProviderSource: ThreadSelectionSource.explicit,
      );

      final routing = controller.buildExternalAcpRoutingForSessionInternal(
        sessionKey,
      );

      expect(routing.mode, ExternalCodeAgentAcpRoutingMode.explicit);
      expect(routing.explicitExecutionTarget, 'gateway');
      expect(routing.explicitProviderId, isEmpty);
    });
  });

  group('persistGoTaskArtifactsForSessionInternal', () {
    test(
      'writes bridge-returned artifacts into the local thread workspace',
      () async {
        final root = Directory.systemTemp.createTempSync(
          'xworkmate-thread-artifacts-test-',
        );
        final controller = AppController();
        addTearDown(() async {
          controller.dispose();
          if (root.existsSync()) {
            await root.delete(recursive: true);
          }
        });

        const sessionKey = 'draft:remote-artifacts';
        controller.upsertTaskThreadInternal(
          sessionKey,
          executionTarget: AssistantExecutionTarget.gateway,
          executionTargetSource: ThreadSelectionSource.explicit,
          workspaceBinding: WorkspaceBinding(
            workspaceId: 'workspace-1',
            workspaceKind: WorkspaceKind.localFs,
            workspacePath: root.path,
            displayPath: root.path,
            writable: true,
          ),
        );

        await controller.persistGoTaskArtifactsForSessionInternal(
          sessionKey,
          GoTaskServiceResult(
            success: true,
            message: 'ok',
            turnId: 'turn-1',
            raw: <String, dynamic>{
              'artifacts': <Map<String, dynamic>>[
                <String, dynamic>{
                  'relativePath': '../notes/result.md',
                  'encoding': 'utf-8',
                  'content': 'artifact-body',
                },
                <String, dynamic>{
                  'relativePath': 'bin/data.txt',
                  'encoding': 'base64',
                  'content': 'YmluYXJ5LWRhdGE=',
                },
              ],
            },
            errorMessage: '',
            resolvedModel: '',
            route: GoTaskServiceRoute.externalAcpSingle,
          ),
        );

        expect(
          File('${root.path}/notes/result.md').readAsStringSync(),
          'artifact-body',
        );
        expect(
          File('${root.path}/bin/data.txt').readAsStringSync(),
          'binary-data',
        );

        final record = controller.requireTaskThreadForSessionInternal(
          sessionKey,
        );
        expect(record.lastArtifactSyncStatus, 'synced');
        expect(record.lastArtifactSyncAtMs, isNotNull);
      },
    );
  });

  group('resolveGatewayAcpAuthorizationHeaderInternal', () {
    test('prefers BRIDGE_SERVER_URL from environment over local settings', () {
      final controller = AppController(
        environmentOverride: const <String, String>{
          'BRIDGE_SERVER_URL': 'https://bridge.env.example/acp',
        },
      );
      addTearDown(controller.dispose);

      controller.settingsController.snapshotInternal = controller.settings
          .copyWith(
            acpBridgeServerModeConfig: controller
                .settings
                .acpBridgeServerModeConfig
                .copyWith(
                  cloudSynced: controller
                      .settings
                      .acpBridgeServerModeConfig
                      .cloudSynced
                      .copyWith(
                        remoteServerSummary:
                            const AcpBridgeServerRemoteServerSummary(
                              endpoint: 'https://bridge.customer.example/acp',
                              hasAdvancedOverrides: false,
                            ),
                      ),
                ),
          );

      expect(
        controller.resolveBridgeAcpEndpointInternal(),
        Uri.parse('https://bridge.env.example/acp'),
      );
      expect(
        controller.resolveExternalAcpEndpointForTargetInternal(
          AssistantExecutionTarget.singleAgent,
        ),
        Uri.parse('https://bridge.env.example/acp'),
      );
      expect(
        controller.resolveExternalAcpEndpointForTargetInternal(
          AssistantExecutionTarget.gateway,
        ),
        Uri.parse('https://bridge.env.example/acp'),
      );
    });

    test('does not recover bridge endpoint from local settings snapshot alone', () {
      final controller = AppController();
      addTearDown(controller.dispose);

      controller.settingsController.snapshotInternal = controller.settings
          .copyWith(
            acpBridgeServerModeConfig: controller
                .settings
                .acpBridgeServerModeConfig
                .copyWith(
                  cloudSynced: controller
                      .settings
                      .acpBridgeServerModeConfig
                      .cloudSynced
                      .copyWith(
                        remoteServerSummary:
                            const AcpBridgeServerRemoteServerSummary(
                              endpoint: 'https://bridge.customer.example/acp',
                              hasAdvancedOverrides: false,
                            ),
                      ),
                ),
          );

      expect(controller.resolveBridgeAcpEndpointInternal(), isNull);
    });

    test(
      'prefers environment bridge bearer tokens over persisted bridge secrets',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'xworkmate-bridge-auth-header-',
        );
        final store = SecureConfigStore(
          enableSecureStorage: false,
          appDataRootPathResolver: () async => '${root.path}/settings.sqlite3',
          secretRootPathResolver: () async => root.path,
          supportRootPathResolver: () async => root.path,
        );
        final controller = AppController(
          store: store,
          environmentOverride: const <String, String>{
            'BRIDGE_SERVER_URL': 'https://xworkmate-bridge.svc.plus/acp',
            'BRIDGE_AUTH_TOKEN': 'env-bridge-token',
            'INTERNAL_SERVICE_TOKEN': 'env-internal-token',
          },
        );
        addTearDown(() async {
          controller.dispose();
          if (await root.exists()) {
            try {
              await root.delete(recursive: true);
            } on FileSystemException {
              // Temp cleanup is best-effort on macOS when sqlite/watch handles lag.
            }
          }
        });

        await store.initialize();
        await store.saveAccountManagedSecret(
          target: kAccountManagedSecretTargetBridgeAuthToken,
          value: 'persisted-bridge-token',
        );

        final bridgeAuthorization = await controller
            .resolveGatewayAcpAuthorizationHeaderInternal(
              Uri.parse('https://xworkmate-bridge.svc.plus/acp'),
            );
        final nonBridgeAuthorization = await controller
            .resolveGatewayAcpAuthorizationHeaderInternal(
              Uri.parse('https://remote.example.com/acp'),
            );

        expect(bridgeAuthorization, 'Bearer env-bridge-token');
        expect(nonBridgeAuthorization, isNull);
      },
    );
  });

  group('thread working directory', () {
    test(
      'uses the unique thread workspace as the only workingDirectory source',
      () async {
        final controller = AppController();
        addTearDown(controller.dispose);

        const sessionKey = 'draft:thread-working-directory';
        controller.initializeAssistantThreadContext(
          sessionKey,
          executionTarget: AssistantExecutionTarget.singleAgent,
        );
        final record = controller.requireTaskThreadForSessionInternal(
          sessionKey,
        );

        expect(
          controller.assistantWorkingDirectoryForSessionInternal(sessionKey),
          record.workspaceBinding.workspacePath,
        );
      },
    );
  });
}

class _FakeGatewayRuntime extends GatewayRuntime {
  factory _FakeGatewayRuntime(GatewayConnectionSnapshot snapshot) {
    final deps = _FakeGatewayRuntimeDeps();
    return _FakeGatewayRuntime._(snapshot, deps);
  }

  _FakeGatewayRuntime._(this._snapshot, this._deps)
    : super(store: _deps.store, identityStore: _deps.identityStore);

  final GatewayConnectionSnapshot _snapshot;
  final _FakeGatewayRuntimeDeps _deps;

  @override
  GatewayConnectionSnapshot get snapshot => _snapshot;

  @override
  bool get isConnected => _snapshot.status == RuntimeConnectionStatus.connected;

  @override
  Future<void> initialize() async {}

  Future<void> disposeTestResources() async {
    if (_deps.root.existsSync()) {
      await _deps.root.delete(recursive: true);
    }
  }
}

class _FakeGatewayRuntimeDeps {
  factory _FakeGatewayRuntimeDeps() {
    final root = Directory.systemTemp.createTempSync(
      'xworkmate-gateway-runtime-test-',
    );
    final store = SecureConfigStore(
      enableSecureStorage: false,
      appDataRootPathResolver: () async => '${root.path}/settings.sqlite3',
      secretRootPathResolver: () async => root.path,
      supportRootPathResolver: () async => root.path,
    );
    return _FakeGatewayRuntimeDeps._(root, store, DeviceIdentityStore(store));
  }

  _FakeGatewayRuntimeDeps._(this.root, this.store, this.identityStore);

  final Directory root;
  final SecureConfigStore store;
  final DeviceIdentityStore identityStore;
}
