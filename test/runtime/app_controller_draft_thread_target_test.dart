import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller_desktop_thread_binding.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

void main() {
  group('pickDraftThreadExecutionTargetInternal', () {
    test('prefers the first visible manual target for new drafts', () {
      final target = pickDraftThreadExecutionTargetInternal(
        currentTarget: AssistantExecutionTarget.auto,
        visibleTargets: const <AssistantExecutionTarget>[
          AssistantExecutionTarget.singleAgent,
          AssistantExecutionTarget.local,
          AssistantExecutionTarget.remote,
        ],
        localWorkspaceAvailable: true,
      );

      expect(target, AssistantExecutionTarget.singleAgent);
    });

    test('skips local targets when the local workspace is unavailable', () {
      final target = pickDraftThreadExecutionTargetInternal(
        currentTarget: AssistantExecutionTarget.auto,
        visibleTargets: const <AssistantExecutionTarget>[
          AssistantExecutionTarget.singleAgent,
          AssistantExecutionTarget.local,
          AssistantExecutionTarget.remote,
        ],
        localWorkspaceAvailable: false,
      );

      expect(target, AssistantExecutionTarget.remote);
    });

    test('keeps the current visible manual target when it is usable', () {
      final target = pickDraftThreadExecutionTargetInternal(
        currentTarget: AssistantExecutionTarget.remote,
        visibleTargets: const <AssistantExecutionTarget>[
          AssistantExecutionTarget.singleAgent,
          AssistantExecutionTarget.local,
          AssistantExecutionTarget.remote,
        ],
        localWorkspaceAvailable: false,
      );

      expect(target, AssistantExecutionTarget.remote);
    });
  });
}
