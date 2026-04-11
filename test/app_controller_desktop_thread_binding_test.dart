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
      );
    }

    test('prefers the latest record after async binding resumes', () {
      final latestRecord = buildThread(
        threadId: 'thread-1',
        mode: ThreadExecutionMode.localAgent,
        providerId: SingleAgentProvider.opencode.providerId,
      );

      final snapshot = resolveDesktopThreadBindingSnapshotInternal(
        defaultExecutionTarget: AssistantExecutionTarget.local,
        latestRecord: latestRecord,
      );

      expect(snapshot.executionTarget, AssistantExecutionTarget.singleAgent);
      expect(snapshot.singleAgentProvider, SingleAgentProvider.opencode);
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
          defaultExecutionTarget: AssistantExecutionTarget.local,
          executionTargetOverride: AssistantExecutionTarget.remote,
          latestRecord: latestRecord,
        );

        expect(snapshot.executionTarget, AssistantExecutionTarget.remote);
        expect(snapshot.singleAgentProvider, SingleAgentProvider.opencode);
      },
    );

    test('does not recover provider from stale fallback-only records', () {
      final staleRecord = buildThread(
        threadId: 'thread-3',
        mode: ThreadExecutionMode.gatewayRemote,
        providerId: SingleAgentProvider.codex.providerId,
      );

      final snapshot = resolveDesktopThreadBindingSnapshotInternal(
        defaultExecutionTarget: AssistantExecutionTarget.remote,
        latestRecord: null,
      );

      expect(snapshot.executionTarget, AssistantExecutionTarget.remote);
      expect(snapshot.singleAgentProvider, SingleAgentProvider.auto);
      expect(snapshot.record, isNull);
      expect(staleRecord.executionBinding.providerId, isNotEmpty);
    });
  });

  group('resolveGatewayExecutionTargetFromVisibleTargets', () {
    test('prefers remote bridge target over silent local fallback', () {
      final target = resolveGatewayExecutionTargetFromVisibleTargets(
        const <AssistantExecutionTarget>[
          AssistantExecutionTarget.singleAgent,
          AssistantExecutionTarget.local,
          AssistantExecutionTarget.remote,
        ],
        currentTarget: AssistantExecutionTarget.singleAgent,
      );

      expect(target, AssistantExecutionTarget.remote);
    });

    test('preserves explicit local gateway selection when already active', () {
      final target = resolveGatewayExecutionTargetFromVisibleTargets(
        const <AssistantExecutionTarget>[
          AssistantExecutionTarget.local,
          AssistantExecutionTarget.remote,
        ],
        currentTarget: AssistantExecutionTarget.local,
      );

      expect(target, AssistantExecutionTarget.local);
    });
  });

  group('resolveGatewayThreadConnectionStateInternal', () {
    test('uses the thread target profile as the only address source', () {
      final state = resolveGatewayThreadConnectionStateInternal(
        target: AssistantExecutionTarget.remote,
        connection:
            GatewayConnectionSnapshot.initial(
              mode: RuntimeConnectionMode.remote,
            ).copyWith(
              status: RuntimeConnectionStatus.connected,
              remoteAddress: '127.0.0.1:18789',
            ),
        targetProfile: GatewayConnectionProfile.defaultsRemote(),
      );

      expect(state.status, RuntimeConnectionStatus.connected);
      expect(state.detailLabel, 'openclaw.svc.plus:443');
      expect(state.ready, isTrue);
    });

    test('marks mismatched local snapshot as offline for remote threads', () {
      final state = resolveGatewayThreadConnectionStateInternal(
        target: AssistantExecutionTarget.remote,
        connection:
            GatewayConnectionSnapshot.initial(
              mode: RuntimeConnectionMode.local,
            ).copyWith(
              status: RuntimeConnectionStatus.connected,
              remoteAddress: '127.0.0.1:18789',
            ),
        targetProfile: GatewayConnectionProfile.defaultsRemote(),
      );

      expect(state.status, RuntimeConnectionStatus.offline);
      expect(state.detailLabel, 'openclaw.svc.plus:443');
      expect(state.ready, isFalse);
      expect(state.lastError, isNull);
    });
  });

  group('assistantConnectionStateForSession', () {
    test(
      'uses target profile address instead of connection snapshot address',
      () {
        final gateway = _FakeGatewayRuntime(
          GatewayConnectionSnapshot.initial(
            mode: RuntimeConnectionMode.remote,
          ).copyWith(
            status: RuntimeConnectionStatus.connected,
            remoteAddress: '127.0.0.1:18789',
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
          executionTarget: AssistantExecutionTarget.remote,
        );
        controller.upsertTaskThreadInternal(
          sessionKey,
          executionTarget: AssistantExecutionTarget.remote,
          executionTargetSource: ThreadSelectionSource.explicit,
        );

        final state = controller.assistantConnectionStateForSession(sessionKey);

        expect(state.status, RuntimeConnectionStatus.connected);
        expect(state.detailLabel, 'openclaw.svc.plus:443');
        expect(state.ready, isTrue);
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
        executionTarget: AssistantExecutionTarget.remote,
        singleAgentProvider: SingleAgentProvider.opencode,
      );
      controller.upsertTaskThreadInternal(
        sessionKey,
        executionTarget: AssistantExecutionTarget.remote,
        executionTargetSource: ThreadSelectionSource.explicit,
        singleAgentProvider: SingleAgentProvider.opencode,
        singleAgentProviderSource: ThreadSelectionSource.explicit,
      );

      final routing = controller.buildExternalAcpRoutingForSessionInternal(
        sessionKey,
      );

      expect(routing.mode, ExternalCodeAgentAcpRoutingMode.explicit);
      expect(routing.explicitExecutionTarget, 'remote');
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
          executionTarget: AssistantExecutionTarget.remote,
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
