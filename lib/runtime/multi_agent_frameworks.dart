import 'runtime_models.dart';

abstract class FrameworkPreset {
  const FrameworkPreset();

  String get id;
  String get label;

  Future<String> roleInstructionBlock({
    required MultiAgentRole role,
    required String tool,
    required List<String> selectedSkills,
  });
}

class NativeFrameworkPreset extends FrameworkPreset {
  const NativeFrameworkPreset();

  @override
  String get id => MultiAgentFramework.native.name;

  @override
  String get label => MultiAgentFramework.native.label;

  @override
  Future<String> roleInstructionBlock({
    required MultiAgentRole role,
    required String tool,
    required List<String> selectedSkills,
  }) async {
    final selected = selectedSkills.isEmpty
        ? '- 无'
        : selectedSkills.map((item) => '- $item').join('\n');
    return '''
当前协作框架：$label
当前角色：${role.label}
当前工具：$tool

用户当前选中的技能：
$selected
''';
  }
}

class ArisFrameworkPreset extends FrameworkPreset {
  const ArisFrameworkPreset();

  @override
  String get id => MultiAgentFramework.aris.name;

  @override
  String get label => MultiAgentFramework.aris.label;

  @override
  Future<String> roleInstructionBlock({
    required MultiAgentRole role,
    required String tool,
    required List<String> selectedSkills,
  }) async {
    // ARIS data has been removed from assets.
    // Fallback to basic instruction.
    final selected = selectedSkills.isEmpty
        ? '- 无'
        : selectedSkills.map((item) => '- $item').join('\n');
    return '''
当前协作框架：$label
当前角色：${role.label}
当前工具：$tool

用户当前选中的技能：
$selected
''';
  }
}
