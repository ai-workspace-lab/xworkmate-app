import 'package:flutter/foundation.dart';

import '../../i18n/app_language.dart';

/// What the executor does with a step once its retries are exhausted.
enum BuiltinPluginStepFailurePolicy {
  /// Mark the step degraded (its [BuiltinPluginWorkflowStep.fallbackZh]
  /// semantics apply) and continue with the next step.
  degrade,

  /// Skip the step's output and continue with the next step.
  skip,

  /// Abort the whole workflow run.
  abort,
}

/// Lightweight workflow state machine for built-in plugins (plan §8.1).
///
/// Batch 1 delivered the linear step list + JSON serialization. Batch 2 adds
/// explicit transition semantics — per-step retry budget ([BuiltinPluginWorkflowStep.maxRetries])
/// and an exhaustion policy ([BuiltinPluginWorkflowStep.failurePolicy]) — plus
/// a runtime tracker (`BuiltinPluginWorkflowRun`) that advances step by step
/// with single-step retry, resume, and progress reporting. Non-linear
/// transitions (branches / joins / guards) remain a later batch. The model is
/// JSON-serializable so plugin definitions can come from external manifests
/// (plan §8.2) or foreign-language runtimes bridged over FFI (plan §8.4).
@immutable
class BuiltinPluginWorkflowStep {
  const BuiltinPluginWorkflowStep({
    required this.id,
    required this.titleZh,
    required this.titleEn,
    required this.instructionZh,
    required this.instructionEn,
    this.outputFormats = const <String>[],
    this.requiredSkills = const <String>[],
    this.maxRetries = 1,
    BuiltinPluginStepFailurePolicy? failurePolicy,
    this.fallbackZh = '',
    this.fallbackEn = '',
  }) : explicitFailurePolicy = failurePolicy;

  /// Stable step id, unique within one workflow (e.g. `outline`, `export`).
  final String id;

  /// Short label surfaced in the settings plugins panel pipeline list.
  final String titleZh;
  final String titleEn;

  /// Full instruction rendered into the composer template for this step.
  final String instructionZh;
  final String instructionEn;

  /// File formats this step produces, e.g. `['pdf', 'docx']`.
  final List<String> outputFormats;

  /// Skill packages this step invokes on the gateway side.
  final List<String> requiredSkills;

  /// How many retry attempts the executor may make after the first failure
  /// before applying [failurePolicy]. `0` disables retries.
  final int maxRetries;

  /// Explicit exhaustion policy, or null to derive one from [hasFallback]
  /// (fallback present → degrade, otherwise abort). See [failurePolicy].
  final BuiltinPluginStepFailurePolicy? explicitFailurePolicy;

  /// Degradation semantics applied when the step degrades.
  final String fallbackZh;
  final String fallbackEn;

  String get title => appText(titleZh, titleEn);

  String get instruction => appText(instructionZh, instructionEn);

  bool get hasFallback =>
      fallbackZh.trim().isNotEmpty || fallbackEn.trim().isNotEmpty;

  /// Whether the executor may retry this step on failure.
  bool get retryable => maxRetries > 0;

  /// Effective exhaustion policy: the explicit one when set, otherwise
  /// degrade when a fallback exists and abort when none does.
  BuiltinPluginStepFailurePolicy get failurePolicy =>
      explicitFailurePolicy ??
      (hasFallback
          ? BuiltinPluginStepFailurePolicy.degrade
          : BuiltinPluginStepFailurePolicy.abort);

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'titleZh': titleZh,
        'titleEn': titleEn,
        'instructionZh': instructionZh,
        'instructionEn': instructionEn,
        if (outputFormats.isNotEmpty) 'outputFormats': outputFormats,
        if (requiredSkills.isNotEmpty) 'requiredSkills': requiredSkills,
        'maxRetries': maxRetries,
        if (explicitFailurePolicy != null)
          'failurePolicy': explicitFailurePolicy!.name,
        if (fallbackZh.isNotEmpty) 'fallbackZh': fallbackZh,
        if (fallbackEn.isNotEmpty) 'fallbackEn': fallbackEn,
      };

  factory BuiltinPluginWorkflowStep.fromJson(Map<String, dynamic> json) {
    List<String> stringList(Object? value) => value is List
        ? value.map((item) => item.toString()).toList(growable: false)
        : const <String>[];
    final rawPolicy = (json['failurePolicy'] as String?)?.trim() ?? '';
    final policy = BuiltinPluginStepFailurePolicy.values
        .where((value) => value.name == rawPolicy)
        .firstOrNull;
    // Schema v1 manifests carried a boolean `retryable` instead of a retry
    // budget; map it onto the v2 field so old manifests keep loading.
    final legacyRetryable = json['retryable'] as bool?;
    final maxRetries =
        (json['maxRetries'] as num?)?.toInt() ??
        (legacyRetryable == null ? 1 : (legacyRetryable ? 1 : 0));
    return BuiltinPluginWorkflowStep(
      id: (json['id'] as String?)?.trim() ?? '',
      titleZh: json['titleZh'] as String? ?? '',
      titleEn: json['titleEn'] as String? ?? '',
      instructionZh: json['instructionZh'] as String? ?? '',
      instructionEn: json['instructionEn'] as String? ?? '',
      outputFormats: stringList(json['outputFormats']),
      requiredSkills: stringList(json['requiredSkills']),
      maxRetries: maxRetries < 0 ? 0 : maxRetries,
      failurePolicy: policy,
      fallbackZh: json['fallbackZh'] as String? ?? '',
      fallbackEn: json['fallbackEn'] as String? ?? '',
    );
  }
}

/// Ordered workflow definition for one built-in plugin.
@immutable
class BuiltinPluginWorkflow {
  const BuiltinPluginWorkflow({
    required this.goalZh,
    required this.goalEn,
    required this.steps,
    required this.inputPromptZh,
    required this.inputPromptEn,
  });

  /// Serialization schema version for external manifests (plan §8.2).
  ///
  /// v2 (batch 2): per-step `maxRetries` + `failurePolicy` replace the v1
  /// boolean `retryable`; v1 manifests still parse (legacy mapping in
  /// [BuiltinPluginWorkflowStep.fromJson]).
  static const int schemaVersion = 2;

  /// Opening line of the composer template, states the overall goal.
  final String goalZh;
  final String goalEn;

  final List<BuiltinPluginWorkflowStep> steps;

  /// Trailing line inviting the user to fill in their specifics.
  final String inputPromptZh;
  final String inputPromptEn;

  /// Union of step output formats, first-seen order preserved.
  List<String> get outputFormats => _orderedUnion(
        steps.map((step) => step.outputFormats),
      );

  /// Union of step skill dependencies, first-seen order preserved.
  List<String> get requiredSkills => _orderedUnion(
        steps.map((step) => step.requiredSkills),
      );

  /// Step titles for the settings plugins panel pipeline list.
  List<String> get pipelineTitlesZh =>
      steps.map((step) => step.titleZh).toList(growable: false);

  String renderComposerTemplateZh() {
    final buffer = StringBuffer()..writeln(goalZh);
    for (var i = 0; i < steps.length; i++) {
      final step = steps[i];
      final fallback = step.fallbackZh.trim().isNotEmpty
          ? '（失败降级：${step.fallbackZh.trim()}）'
          : '';
      final terminator = i == steps.length - 1 ? '。' : '；';
      buffer.writeln('${i + 1}. ${step.instructionZh}$fallback$terminator');
    }
    buffer.write(inputPromptZh);
    return buffer.toString();
  }

  String renderComposerTemplateEn() {
    final buffer = StringBuffer()..writeln(goalEn);
    for (var i = 0; i < steps.length; i++) {
      final step = steps[i];
      final fallback = step.fallbackEn.trim().isNotEmpty
          ? ' (on failure: ${step.fallbackEn.trim()})'
          : '';
      buffer.writeln('${i + 1}. ${step.instructionEn}$fallback.');
    }
    buffer.write(inputPromptEn);
    return buffer.toString();
  }

  String renderComposerTemplate() =>
      appText(renderComposerTemplateZh(), renderComposerTemplateEn());

  Map<String, dynamic> toJson() => <String, dynamic>{
        'schemaVersion': schemaVersion,
        'goalZh': goalZh,
        'goalEn': goalEn,
        'inputPromptZh': inputPromptZh,
        'inputPromptEn': inputPromptEn,
        'steps': steps.map((step) => step.toJson()).toList(growable: false),
      };

  factory BuiltinPluginWorkflow.fromJson(Map<String, dynamic> json) {
    final rawSteps = json['steps'];
    return BuiltinPluginWorkflow(
      goalZh: json['goalZh'] as String? ?? '',
      goalEn: json['goalEn'] as String? ?? '',
      inputPromptZh: json['inputPromptZh'] as String? ?? '',
      inputPromptEn: json['inputPromptEn'] as String? ?? '',
      steps: rawSteps is List
          ? rawSteps
              .whereType<Map<String, dynamic>>()
              .map(BuiltinPluginWorkflowStep.fromJson)
              .toList(growable: false)
          : const <BuiltinPluginWorkflowStep>[],
    );
  }

  static List<String> _orderedUnion(Iterable<List<String>> groups) {
    final seen = <String>{};
    final result = <String>[];
    for (final group in groups) {
      for (final item in group) {
        if (seen.add(item)) {
          result.add(item);
        }
      }
    }
    return List<String>.unmodifiable(result);
  }
}
