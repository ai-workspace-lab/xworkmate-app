import 'dart:io';

import 'aris_bundle.dart';
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
  ArisFrameworkPreset(this.bundleRepositoryInternal);

  final ArisBundleRepository bundleRepositoryInternal;

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
    final bundle = await bundleRepositoryInternal.ensureReady();
    final preferCodex = tool.trim().toLowerCase() == 'codex';
    final skillPaths = bundle.skillPathsForRole(role, preferCodex: preferCodex);
    final skillDocs = await bundleRepositoryInternal.loadSkillContents(
      skillPaths,
    );
    final selected = selectedSkills.isEmpty
        ? '- 无'
        : selectedSkills.map((item) => '- $item').join('\n');
    final excerpts = skillDocs.entries
        .map(
          (entry) =>
              formatSkillExcerptInternal(path: entry.key, content: entry.value),
        )
        .join('\n\n');
    return '''
当前协作框架：$label
当前角色：${role.label}
当前工具：$tool
ARIS bundle：${bundle.manifest.bundleVersion}

用户当前选中的技能：
$selected

请优先遵循以下内嵌 ARIS 技能方法：
$excerpts
''';
  }

  String formatSkillExcerptInternal({
    required String path,
    required String content,
  }) {
    final label = File(
      path,
    ).parent.uri.pathSegments.where((item) => item.isNotEmpty).last;
    final lines = content
        .split('\n')
        .map((line) => line.trimRight())
        .where((line) => line.isNotEmpty)
        .take(60)
        .join('\n');
    return '''
## $label
来源：$path
$lines
''';
  }
}
