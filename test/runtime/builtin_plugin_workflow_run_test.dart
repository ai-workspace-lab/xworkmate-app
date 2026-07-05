import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/features/plugins/builtin_plugin_catalog.dart';
import 'package:xworkmate/features/plugins/builtin_plugin_runtime.dart';
import 'package:xworkmate/features/plugins/builtin_plugin_workflow.dart';
import 'package:xworkmate/features/plugins/builtin_plugin_workflow_run.dart';

BuiltinPluginWorkflow _workflow({
  required List<BuiltinPluginWorkflowStep> steps,
}) => BuiltinPluginWorkflow(
  goalZh: '目标',
  goalEn: 'goal',
  inputPromptZh: '输入：',
  inputPromptEn: 'input:',
  steps: steps,
);

BuiltinPluginWorkflowStep _step(
  String id, {
  int maxRetries = 1,
  BuiltinPluginStepFailurePolicy? failurePolicy,
  String fallbackZh = '',
}) => BuiltinPluginWorkflowStep(
  id: id,
  titleZh: id,
  titleEn: id,
  instructionZh: '执行 $id',
  instructionEn: 'run $id',
  maxRetries: maxRetries,
  failurePolicy: failurePolicy,
  fallbackZh: fallbackZh,
  fallbackEn: fallbackZh.isEmpty ? '' : 'fallback for $id',
);

void main() {
  group('BuiltinPluginWorkflowRun state machine (batch 2)', () {
    test('linear happy path advances step by step to success', () {
      final run = BuiltinPluginWorkflowRun(
        _workflow(steps: <BuiltinPluginWorkflowStep>[_step('a'), _step('b')]),
      );
      expect(run.status, BuiltinPluginWorkflowRunStatus.running);
      expect(run.currentStep?.id, 'a');
      expect(run.progress, 0);

      run.beginCurrentStep();
      run.completeCurrentStep();
      expect(run.currentStep?.id, 'b');
      expect(run.progress, 0.5);

      run.beginCurrentStep();
      run.completeCurrentStep();
      expect(run.status, BuiltinPluginWorkflowRunStatus.succeeded);
      expect(run.isTerminal, isTrue);
      expect(run.currentStep, isNull);
      expect(run.progress, 1);
    });

    test('failure consumes retry budget before applying the policy', () {
      final run = BuiltinPluginWorkflowRun(
        _workflow(
          steps: <BuiltinPluginWorkflowStep>[
            _step('flaky', maxRetries: 2, fallbackZh: '整页占位'),
          ],
        ),
      );
      run.beginCurrentStep();
      expect(run.failCurrentStep(), BuiltinPluginStepFailureAction.retry);
      run.beginCurrentStep();
      expect(run.failCurrentStep(), BuiltinPluginStepFailureAction.retry);
      run.beginCurrentStep();
      expect(run.failCurrentStep(), BuiltinPluginStepFailureAction.degraded);
      expect(run.status, BuiltinPluginWorkflowRunStatus.succeeded);
      expect(run.hasDegradedSteps, isTrue);
      expect(run.stepStatuses.single, BuiltinPluginStepStatus.degraded);
      expect(run.retryCounts.single, 2);
    });

    test('abort policy fails the run and keeps later steps pending', () {
      final run = BuiltinPluginWorkflowRun(
        _workflow(
          steps: <BuiltinPluginWorkflowStep>[
            _step('critical', maxRetries: 0),
            _step('after'),
          ],
        ),
      );
      run.beginCurrentStep();
      expect(run.failCurrentStep(), BuiltinPluginStepFailureAction.aborted);
      expect(run.status, BuiltinPluginWorkflowRunStatus.failed);
      expect(run.isTerminal, isTrue);
      expect(run.stepStatuses, <BuiltinPluginStepStatus>[
        BuiltinPluginStepStatus.failed,
        BuiltinPluginStepStatus.pending,
      ]);
    });

    test('skip policy records the step and continues', () {
      final run = BuiltinPluginWorkflowRun(
        _workflow(
          steps: <BuiltinPluginWorkflowStep>[
            _step(
              'optional',
              maxRetries: 0,
              failurePolicy: BuiltinPluginStepFailurePolicy.skip,
            ),
            _step('after'),
          ],
        ),
      );
      run.beginCurrentStep();
      expect(run.failCurrentStep(), BuiltinPluginStepFailureAction.skipped);
      expect(run.currentStep?.id, 'after');
      run.beginCurrentStep();
      run.completeCurrentStep();
      expect(run.status, BuiltinPluginWorkflowRunStatus.succeeded);
      expect(run.hasDegradedSteps, isTrue);
    });

    test('run state resumes from JSON at the interrupted step', () {
      final workflow = _workflow(
        steps: <BuiltinPluginWorkflowStep>[_step('a'), _step('b'), _step('c')],
      );
      final run = BuiltinPluginWorkflowRun(workflow);
      run.beginCurrentStep();
      run.completeCurrentStep();
      run.beginCurrentStep(); // 'b' was mid-flight when persisted.
      final restored = BuiltinPluginWorkflowRun.fromJson(
        workflow,
        run.toJson(),
      );
      expect(restored.currentStep?.id, 'b');
      // Mid-flight step restarts from pending.
      expect(restored.stepStatuses, <BuiltinPluginStepStatus>[
        BuiltinPluginStepStatus.succeeded,
        BuiltinPluginStepStatus.pending,
        BuiltinPluginStepStatus.pending,
      ]);
      expect(restored.progress, closeTo(1 / 3, 0.001));
    });

    test('resume falls back to a fresh run when the workflow changed', () {
      final workflow = _workflow(
        steps: <BuiltinPluginWorkflowStep>[_step('a'), _step('b')],
      );
      final run = BuiltinPluginWorkflowRun(workflow);
      run.beginCurrentStep();
      run.completeCurrentStep();
      final changedWorkflow = _workflow(
        steps: <BuiltinPluginWorkflowStep>[_step('a'), _step('renamed')],
      );
      final restored = BuiltinPluginWorkflowRun.fromJson(
        changedWorkflow,
        run.toJson(),
      );
      expect(restored.currentStep?.id, 'a');
      expect(restored.progress, 0);
    });

    test('presentation reconstruct step carries retry budget and degrade '
        'policy', () {
      final presentation = BuiltinPluginCatalog.byId(
        BuiltinPluginCatalog.presentationId,
      )!;
      final reconstruct = presentation.workflow.steps.firstWhere(
        (step) => step.id == 'reconstruct',
      );
      expect(reconstruct.maxRetries, 2);
      expect(
        reconstruct.failurePolicy,
        BuiltinPluginStepFailurePolicy.degrade,
      );
    });

    test('schema v1 manifests with boolean retryable still parse', () {
      final restored = BuiltinPluginWorkflowStep.fromJson(<String, dynamic>{
        'id': 'legacy',
        'titleZh': '旧步骤',
        'titleEn': 'legacy step',
        'instructionZh': '旧指令',
        'instructionEn': 'legacy instruction',
        'retryable': false,
      });
      expect(restored.maxRetries, 0);
      expect(restored.retryable, isFalse);
      expect(restored.failurePolicy, BuiltinPluginStepFailurePolicy.abort);
    });
  });

  group('BuiltinPluginRuntimeBinding (batch 2 scaffold)', () {
    test('first-batch plugins run on the compiled-in Dart runtime', () {
      for (final plugin in BuiltinPluginCatalog.firstBatch) {
        expect(
          plugin.runtime.kind,
          BuiltinPluginRuntimeKind.builtinDart,
          reason: plugin.id,
        );
      }
    });

    test('ffi binding roundtrips through JSON', () {
      const binding = BuiltinPluginRuntimeBinding(
        kind: BuiltinPluginRuntimeKind.nativeFfi,
        libraryPath: 'plugins/libxwm_chart.dylib',
        version: '0.3.1',
        sha256: 'abc123',
      );
      final restored = BuiltinPluginRuntimeBinding.fromJson(binding.toJson());
      expect(restored.kind, BuiltinPluginRuntimeKind.nativeFfi);
      expect(restored.libraryPath, 'plugins/libxwm_chart.dylib');
      expect(restored.entrySymbolPrefix, 'xwm_plugin');
      expect(restored.version, '0.3.1');
      expect(restored.sha256, 'abc123');
    });

    test('unknown runtime kinds fall back to builtin Dart', () {
      final restored = BuiltinPluginRuntimeBinding.fromJson(<String, dynamic>{
        'kind': 'quantum',
      });
      expect(restored.kind, BuiltinPluginRuntimeKind.builtinDart);
    });
  });
}
