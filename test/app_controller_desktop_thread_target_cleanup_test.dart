import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller_desktop_thread_sessions.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

void main() {
  group('resolveAssistantExecutionTargetFromRecordsInternal', () {
    const owner = ThreadOwnerScope(
      realm: ThreadRealm.local,
      subjectType: ThreadSubjectType.user,
      subjectId: 'u1',
      displayName: 'User',
    );

    TaskThread buildThread({
      required String threadId,
      required ThreadExecutionMode mode,
      String providerId = 'auto',
    }) {
      return TaskThread(
        threadId: threadId,
        ownerScope: owner,
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

    test('defaults to single-agent when no thread record exists', () {
      final resolved = _ThreadSessionTargetResolverHarness().resolveTarget(
        primary: null,
      );

      expect(resolved, AssistantExecutionTarget.singleAgent);
    });

    test('prefers the current thread record over the main thread fallback', () {
      final primary = buildThread(
        threadId: 'draft:1',
        mode: ThreadExecutionMode.gatewayRemote,
      );
      final fallback = buildThread(
        threadId: 'main',
        mode: ThreadExecutionMode.gatewayLocal,
      );

      final resolved = _ThreadSessionTargetResolverHarness().resolveTarget(
        primary: primary,
        fallback: fallback,
      );

      expect(resolved, AssistantExecutionTarget.remote);
    });

    test(
      'uses main thread record instead of settings when current is missing',
      () {
        final fallback = buildThread(
          threadId: 'main',
          mode: ThreadExecutionMode.localAgent,
          providerId: SingleAgentProvider.opencode.providerId,
        );

        final resolved = _ThreadSessionTargetResolverHarness().resolveTarget(
          primary: null,
          fallback: fallback,
        );

        expect(resolved, AssistantExecutionTarget.singleAgent);
      },
    );
  });
}

class _ThreadSessionTargetResolverHarness {
  AssistantExecutionTarget resolveTarget({
    required TaskThread? primary,
    TaskThread? fallback,
  }) {
    return resolveAssistantExecutionTargetFromRecordsForTest(
      primary,
      fallbackRecord: fallback,
    );
  }
}
