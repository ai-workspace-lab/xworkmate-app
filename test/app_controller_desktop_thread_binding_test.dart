import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller_desktop_thread_binding.dart';
import 'package:xworkmate/app/app_controller_desktop_thread_sessions.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

void main() {
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
}
