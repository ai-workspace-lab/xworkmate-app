import 'package:flutter/foundation.dart';

import '../../i18n/app_language.dart';

/// Lightweight workflow state machine for built-in plugins (plan §8.1,
/// batch 1).
///
/// Batch 1 is deliberately linear: steps run in list order, and a step
/// either completes, retries, or degrades via its [BuiltinPluginWorkflowStep.fallbackZh]
/// semantics. Non-linear transitions (branches / joins / explicit
/// transition guards) are a later batch. The model is JSON-serializable so
/// a future batch can load plugin definitions from an external manifest
/// instead of compiling them into the app (plan §8.2).
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
    this.retryable = true,
    this.fallbackZh = '',
    this.fallbackEn = '',
  });

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

  /// Whether the executor may retry this step on failure before degrading.
  final bool retryable;

  /// Degradation semantics when the step keeps failing; empty = abort.
  final String fallbackZh;
  final String fallbackEn;

  String get title => appText(titleZh, titleEn);

  String get instruction => appText(instructionZh, instructionEn);

  bool get hasFallback =>
      fallbackZh.trim().isNotEmpty || fallbackEn.trim().isNotEmpty;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'titleZh': titleZh,
        'titleEn': titleEn,
        'instructionZh': instructionZh,
        'instructionEn': instructionEn,
        if (outputFormats.isNotEmpty) 'outputFormats': outputFormats,
        if (requiredSkills.isNotEmpty) 'requiredSkills': requiredSkills,
        'retryable': retryable,
        if (fallbackZh.isNotEmpty) 'fallbackZh': fallbackZh,
        if (fallbackEn.isNotEmpty) 'fallbackEn': fallbackEn,
      };

  factory BuiltinPluginWorkflowStep.fromJson(Map<String, dynamic> json) {
    List<String> stringList(Object? value) => value is List
        ? value.map((item) => item.toString()).toList(growable: false)
        : const <String>[];
    return BuiltinPluginWorkflowStep(
      id: (json['id'] as String?)?.trim() ?? '',
      titleZh: json['titleZh'] as String? ?? '',
      titleEn: json['titleEn'] as String? ?? '',
      instructionZh: json['instructionZh'] as String? ?? '',
      instructionEn: json['instructionEn'] as String? ?? '',
      outputFormats: stringList(json['outputFormats']),
      requiredSkills: stringList(json['requiredSkills']),
      retryable: json['retryable'] as bool? ?? true,
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
  static const int schemaVersion = 1;

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
