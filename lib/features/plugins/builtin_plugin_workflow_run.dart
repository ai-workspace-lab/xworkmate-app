import 'package:flutter/foundation.dart';

import 'builtin_plugin_workflow.dart';

/// Status of a single step within a workflow run.
enum BuiltinPluginStepStatus {
  pending,
  running,
  succeeded,

  /// Failed but continued via the step's fallback semantics.
  degraded,

  /// Failed and skipped without output (failurePolicy.skip).
  skipped,

  /// Failed terminally (failurePolicy.abort) — the run stops here.
  failed,
}

/// Overall status of a workflow run.
enum BuiltinPluginWorkflowRunStatus { running, succeeded, failed }

/// What the run decided after a step failure was reported.
enum BuiltinPluginStepFailureAction { retry, degraded, skipped, aborted }

/// Mutable execution state for one [BuiltinPluginWorkflow] run (plan §8.1,
/// batch 2).
///
/// The executor drives steps in order: [beginCurrentStep] →
/// [completeCurrentStep] / [failCurrentStep]. Failures consume the step's
/// retry budget first; once exhausted the step's
/// [BuiltinPluginWorkflowStep.failurePolicy] decides between degrade / skip
/// (both continue) and abort (run fails). The whole run state serializes to
/// JSON so an interrupted run can resume from the step it stopped at, and
/// [progress] feeds step-level progress visualization.
class BuiltinPluginWorkflowRun {
  BuiltinPluginWorkflowRun(this.workflow)
      : _statuses = List<BuiltinPluginStepStatus>.filled(
          workflow.steps.length,
          BuiltinPluginStepStatus.pending,
          growable: false,
        ),
        _retryCounts = List<int>.filled(workflow.steps.length, 0,
            growable: false),
        _currentIndex = 0;

  BuiltinPluginWorkflowRun._restored(
    this.workflow,
    this._statuses,
    this._retryCounts,
    this._currentIndex,
  );

  /// Serialization schema version for persisted run state.
  static const int schemaVersion = 1;

  final BuiltinPluginWorkflow workflow;
  final List<BuiltinPluginStepStatus> _statuses;
  final List<int> _retryCounts;
  int _currentIndex;

  /// Immutable view of all step statuses, in workflow order.
  List<BuiltinPluginStepStatus> get stepStatuses =>
      List<BuiltinPluginStepStatus>.unmodifiable(_statuses);

  /// Retry attempts consumed so far for each step.
  List<int> get retryCounts => List<int>.unmodifiable(_retryCounts);

  /// Index of the step the run is at, == step count once complete.
  int get currentIndex => _currentIndex;

  /// The step awaiting/being executed, or null when the run is terminal.
  BuiltinPluginWorkflowStep? get currentStep =>
      isTerminal ? null : workflow.steps[_currentIndex];

  BuiltinPluginWorkflowRunStatus get status {
    if (_statuses.contains(BuiltinPluginStepStatus.failed)) {
      return BuiltinPluginWorkflowRunStatus.failed;
    }
    if (_currentIndex >= workflow.steps.length) {
      return BuiltinPluginWorkflowRunStatus.succeeded;
    }
    return BuiltinPluginWorkflowRunStatus.running;
  }

  bool get isTerminal => status != BuiltinPluginWorkflowRunStatus.running;

  /// Whether any step degraded or was skipped along the way.
  bool get hasDegradedSteps =>
      _statuses.contains(BuiltinPluginStepStatus.degraded) ||
      _statuses.contains(BuiltinPluginStepStatus.skipped);

  /// Fraction of steps resolved (succeeded / degraded / skipped / failed),
  /// 0..1, for progress visualization.
  double get progress {
    if (workflow.steps.isEmpty) {
      return 1;
    }
    final resolved = _statuses
        .where((status) => status != BuiltinPluginStepStatus.pending &&
            status != BuiltinPluginStepStatus.running)
        .length;
    return resolved / workflow.steps.length;
  }

  /// Marks the current step running. No-op when already running; throws when
  /// the run is terminal.
  void beginCurrentStep() {
    final step = currentStep;
    if (step == null) {
      throw StateError('Workflow run is already terminal.');
    }
    _statuses[_currentIndex] = BuiltinPluginStepStatus.running;
  }

  /// Marks the current step succeeded and advances to the next one.
  void completeCurrentStep() {
    if (currentStep == null) {
      throw StateError('Workflow run is already terminal.');
    }
    _statuses[_currentIndex] = BuiltinPluginStepStatus.succeeded;
    _currentIndex += 1;
  }

  /// Reports a failure of the current step and returns the action the run
  /// took: retry (budget left), degraded/skipped (continue per policy), or
  /// aborted (run failed).
  BuiltinPluginStepFailureAction failCurrentStep() {
    final step = currentStep;
    if (step == null) {
      throw StateError('Workflow run is already terminal.');
    }
    if (_retryCounts[_currentIndex] < step.maxRetries) {
      _retryCounts[_currentIndex] += 1;
      _statuses[_currentIndex] = BuiltinPluginStepStatus.pending;
      return BuiltinPluginStepFailureAction.retry;
    }
    switch (step.failurePolicy) {
      case BuiltinPluginStepFailurePolicy.degrade:
        _statuses[_currentIndex] = BuiltinPluginStepStatus.degraded;
        _currentIndex += 1;
        return BuiltinPluginStepFailureAction.degraded;
      case BuiltinPluginStepFailurePolicy.skip:
        _statuses[_currentIndex] = BuiltinPluginStepStatus.skipped;
        _currentIndex += 1;
        return BuiltinPluginStepFailureAction.skipped;
      case BuiltinPluginStepFailurePolicy.abort:
        _statuses[_currentIndex] = BuiltinPluginStepStatus.failed;
        return BuiltinPluginStepFailureAction.aborted;
    }
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'schemaVersion': schemaVersion,
        'stepIds': workflow.steps
            .map((step) => step.id)
            .toList(growable: false),
        'statuses':
            _statuses.map((status) => status.name).toList(growable: false),
        'retryCounts': _retryCounts,
        'currentIndex': _currentIndex,
      };

  /// Restores a run against [workflow]. Returns a fresh run when the
  /// persisted state does not match the workflow's steps (e.g. the plugin
  /// definition changed between app versions) — resuming against a different
  /// step list would attribute states to the wrong steps.
  factory BuiltinPluginWorkflowRun.fromJson(
    BuiltinPluginWorkflow workflow,
    Map<String, dynamic> json,
  ) {
    final stepIds = json['stepIds'];
    final rawStatuses = json['statuses'];
    final rawRetryCounts = json['retryCounts'];
    final currentIndex = (json['currentIndex'] as num?)?.toInt() ?? 0;
    final expectedIds = workflow.steps
        .map((step) => step.id)
        .toList(growable: false);
    if (stepIds is! List ||
        rawStatuses is! List ||
        rawRetryCounts is! List ||
        stepIds.length != expectedIds.length ||
        rawStatuses.length != expectedIds.length ||
        rawRetryCounts.length != expectedIds.length ||
        currentIndex < 0 ||
        currentIndex > expectedIds.length) {
      return BuiltinPluginWorkflowRun(workflow);
    }
    for (var i = 0; i < expectedIds.length; i++) {
      if (stepIds[i].toString() != expectedIds[i]) {
        return BuiltinPluginWorkflowRun(workflow);
      }
    }
    final statuses = <BuiltinPluginStepStatus>[];
    for (final raw in rawStatuses) {
      final parsed = BuiltinPluginStepStatus.values
          .where((value) => value.name == raw.toString())
          .firstOrNull;
      if (parsed == null) {
        return BuiltinPluginWorkflowRun(workflow);
      }
      // A step that was mid-flight when the run was persisted restarts from
      // pending on resume.
      statuses.add(parsed == BuiltinPluginStepStatus.running
          ? BuiltinPluginStepStatus.pending
          : parsed);
    }
    final retryCounts = rawRetryCounts
        .map((raw) => (raw as num).toInt())
        .toList(growable: false);
    return BuiltinPluginWorkflowRun._restored(
      workflow,
      List<BuiltinPluginStepStatus>.of(statuses, growable: false),
      List<int>.of(retryCounts, growable: false),
      currentIndex,
    );
  }

  @visibleForTesting
  void debugSetStepStatus(int index, BuiltinPluginStepStatus status) {
    _statuses[index] = status;
  }
}
