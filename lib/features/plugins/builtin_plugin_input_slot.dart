import 'package:flutter/foundation.dart';

import '../../i18n/app_language.dart';

/// What kind of value a plugin input slot accepts (plan §8.5, batch 3).
enum BuiltinPluginSlotType {
  /// An image the user supplies as a *reference*, not as the subject. The
  /// slot's [BuiltinPluginInputSlot.roleZh] says which attribute of the
  /// reference to carry over (pose, palette, print pattern, ...).
  referenceImage,

  /// Free text — copy, selling points, brand voice.
  text,

  /// One value out of [BuiltinPluginInputSlot.choices].
  choice,

  /// An external source to ingest and analyse before generating anything.
  url,
}

extension BuiltinPluginSlotTypeCopy on BuiltinPluginSlotType {
  String get label => switch (this) {
    BuiltinPluginSlotType.referenceImage => appText('参考图', 'Reference image'),
    BuiltinPluginSlotType.text => appText('文本', 'Text'),
    BuiltinPluginSlotType.choice => appText('选项', 'Choice'),
    BuiltinPluginSlotType.url => appText('链接', 'Link'),
  };
}

/// One typed input a plugin declares up front.
///
/// This is the extension point that makes "dynamic multi-reference prompting"
/// a plugin capability instead of prose. A free-text prompt can *ask* for a
/// model shot and a print swatch; only a slot can state that image #2 is a
/// print reference and that **only its pattern** should be carried over, while
/// image #1 contributes pose and framing. [renderPromptLineZh] turns that
/// declaration into the constraint line the gateway agent actually reads.
///
/// Slots are declaration-only: the app collects values and renders them into
/// the composer template. No generation happens client-side.
@immutable
class BuiltinPluginInputSlot {
  const BuiltinPluginInputSlot({
    required this.id,
    required this.labelZh,
    required this.labelEn,
    required this.type,
    required this.roleZh,
    required this.roleEn,
    this.required = false,
    this.maxCount = 1,
    this.choices = const <String>[],
  }) : assert(maxCount >= 1, 'a slot must accept at least one value');

  /// Stable slot id, unique within one plugin (e.g. `model`, `print`).
  final String id;

  final String labelZh;
  final String labelEn;

  final BuiltinPluginSlotType type;

  /// What this input contributes to the generation — the whole point of the
  /// slot. For a reference image this is the attribute to carry over and,
  /// just as importantly, what to ignore.
  final String roleZh;
  final String roleEn;

  /// Whether the plugin can run at all without this slot filled.
  final bool required;

  /// How many values the slot accepts. A print slot may take several swatches;
  /// a product shot takes one.
  final int maxCount;

  /// Allowed values for [BuiltinPluginSlotType.choice] slots.
  final List<String> choices;

  String get label => appText(labelZh, labelEn);

  String get role => appText(roleZh, roleEn);

  bool get acceptsMultiple => maxCount > 1;

  /// One constraint line for the composer template.
  String renderPromptLineZh() {
    final buffer = StringBuffer('- $labelZh（${_slotTypeLabelZh(type)}');
    if (acceptsMultiple) {
      buffer.write('，最多 $maxCount 张');
    }
    buffer.write(required ? '，必填）' : '，可选）');
    buffer.write('：$roleZh');
    if (type == BuiltinPluginSlotType.choice && choices.isNotEmpty) {
      buffer.write('。可选值：${choices.join(' / ')}');
    }
    return buffer.toString();
  }

  String renderPromptLineEn() {
    final buffer = StringBuffer('- $labelEn (${_slotTypeLabelEn(type)}');
    if (acceptsMultiple) {
      buffer.write(', up to $maxCount');
    }
    buffer.write(required ? ', required)' : ', optional)');
    buffer.write(': $roleEn');
    if (type == BuiltinPluginSlotType.choice && choices.isNotEmpty) {
      buffer.write('. Allowed values: ${choices.join(' / ')}');
    }
    return buffer.toString();
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'labelZh': labelZh,
    'labelEn': labelEn,
    'type': type.name,
    'roleZh': roleZh,
    'roleEn': roleEn,
    'required': required,
    'maxCount': maxCount,
    if (choices.isNotEmpty) 'choices': choices,
  };

  factory BuiltinPluginInputSlot.fromJson(Map<String, dynamic> json) {
    final rawType = (json['type'] as String?)?.trim() ?? '';
    final rawMaxCount = (json['maxCount'] as num?)?.toInt() ?? 1;
    return BuiltinPluginInputSlot(
      id: (json['id'] as String?)?.trim() ?? '',
      labelZh: json['labelZh'] as String? ?? '',
      labelEn: json['labelEn'] as String? ?? '',
      type:
          BuiltinPluginSlotType.values
              .where((value) => value.name == rawType)
              .firstOrNull ??
          BuiltinPluginSlotType.text,
      roleZh: json['roleZh'] as String? ?? '',
      roleEn: json['roleEn'] as String? ?? '',
      required: json['required'] as bool? ?? false,
      maxCount: rawMaxCount < 1 ? 1 : rawMaxCount,
      choices: json['choices'] is List
          ? (json['choices'] as List)
                .map((item) => item.toString())
                .toList(growable: false)
          : const <String>[],
    );
  }
}

String _slotTypeLabelZh(BuiltinPluginSlotType type) => switch (type) {
  BuiltinPluginSlotType.referenceImage => '参考图',
  BuiltinPluginSlotType.text => '文本',
  BuiltinPluginSlotType.choice => '选项',
  BuiltinPluginSlotType.url => '链接',
};

String _slotTypeLabelEn(BuiltinPluginSlotType type) => switch (type) {
  BuiltinPluginSlotType.referenceImage => 'reference image',
  BuiltinPluginSlotType.text => 'text',
  BuiltinPluginSlotType.choice => 'choice',
  BuiltinPluginSlotType.url => 'link',
};
