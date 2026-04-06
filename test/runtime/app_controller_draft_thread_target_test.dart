import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller_desktop_thread_binding.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

void main() {
  group('pickDraftThreadExecutionTargetInternal', () {
    test('prefers the current visible target for new drafts', () {
      final target = pickDraftThreadExecutionTargetInternal(
        currentTarget: AssistantExecutionTarget.singleAgent,
        visibleTargets: const <AssistantExecutionTarget>[
          AssistantExecutionTarget.singleAgent,
          AssistantExecutionTarget.local,
          AssistantExecutionTarget.remote,
        ],
      );

      expect(target, AssistantExecutionTarget.singleAgent);
    });

    test('keeps singleAgent even when the local workspace is unavailable', () {
      final target = pickDraftThreadExecutionTargetInternal(
        currentTarget: AssistantExecutionTarget.singleAgent,
        visibleTargets: const <AssistantExecutionTarget>[
          AssistantExecutionTarget.singleAgent,
          AssistantExecutionTarget.local,
          AssistantExecutionTarget.remote,
        ],
      );

      expect(target, AssistantExecutionTarget.singleAgent);
    });

    test('keeps the current visible manual target when it is usable', () {
      final target = pickDraftThreadExecutionTargetInternal(
        currentTarget: AssistantExecutionTarget.remote,
        visibleTargets: const <AssistantExecutionTarget>[
          AssistantExecutionTarget.singleAgent,
          AssistantExecutionTarget.local,
          AssistantExecutionTarget.remote,
        ],
      );

      expect(target, AssistantExecutionTarget.remote);
    });
  });
}
