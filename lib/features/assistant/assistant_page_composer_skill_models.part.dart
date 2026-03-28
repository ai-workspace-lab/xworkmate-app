part of 'assistant_page.dart';

const List<_ComposerSkillOption> _fallbackSkillOptions = <_ComposerSkillOption>[
  _ComposerSkillOption(
    key: '1password',
    label: '1password',
    description: '安全读取和注入本地凭据。',
    sourceLabel: 'Local',
    icon: Icons.auto_awesome_rounded,
  ),
  _ComposerSkillOption(
    key: 'xlsx',
    label: 'xlsx',
    description: '读取、整理和生成表格文件。',
    sourceLabel: 'Local',
    icon: Icons.auto_awesome_rounded,
  ),
  _ComposerSkillOption(
    key: 'web-processing',
    label: '网页处理',
    description: '打开网页、提取内容并完成网页操作。',
    sourceLabel: 'Web',
    icon: Icons.language_rounded,
  ),
  _ComposerSkillOption(
    key: 'apple-reminders',
    label: 'apple-reminders',
    description: '管理提醒事项和任务提醒。',
    sourceLabel: 'Local',
    icon: Icons.auto_awesome_rounded,
  ),
  _ComposerSkillOption(
    key: 'blogwatcher',
    label: 'blogwatcher',
    description: '跟踪博客更新并生成摘要。',
    sourceLabel: 'Local',
    icon: Icons.auto_awesome_rounded,
  ),
];

_ComposerSkillOption _skillOptionFromGateway(GatewaySkillSummary skill) {
  final normalizedKey = skill.skillKey.trim().toLowerCase();
  final normalizedName = skill.name.trim().toLowerCase();
  final isWebSkill =
      normalizedKey.contains('browser') ||
      normalizedKey.contains('open-link') ||
      normalizedKey.contains('web') ||
      normalizedName.contains('browser') ||
      normalizedName.contains('网页');
  final label = isWebSkill ? '网页处理' : skill.name.trim();
  final key = isWebSkill ? 'web-processing' : normalizedKey;
  final sourceLabel = skill.source.trim().isEmpty ? 'Gateway' : skill.source;
  final description = skill.description.trim().isEmpty
      ? appText('可在当前任务中调用的技能。', 'Skill available in the current task.')
      : skill.description.trim();

  return _ComposerSkillOption(
    key: key,
    label: label,
    description: description,
    sourceLabel: sourceLabel,
    icon: isWebSkill ? Icons.language_rounded : Icons.auto_awesome_rounded,
  );
}

_ComposerSkillOption _skillOptionFromThreadSkill(
  AssistantThreadSkillEntry skill,
) {
  return _ComposerSkillOption(
    key: skill.key,
    label: skill.label.trim().isEmpty ? skill.key : skill.label.trim(),
    description: skill.description.trim().isEmpty
        ? appText('已绑定到当前线程的本地技能。', 'Local skill bound to this thread.')
        : skill.description.trim(),
    sourceLabel: skill.sourceLabel.trim().isEmpty
        ? skill.sourcePath
        : skill.sourceLabel.trim(),
    icon: Icons.auto_awesome_rounded,
  );
}

class _ComposerSkillOption {
  const _ComposerSkillOption({
    required this.key,
    required this.label,
    required this.description,
    required this.sourceLabel,
    required this.icon,
  });

  final String key;
  final String label;
  final String description;
  final String sourceLabel;
  final IconData icon;
}
