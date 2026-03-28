part of 'assistant_page.dart';

String _executionTargetTooltip(AssistantExecutionTarget target) =>
    appText('任务对话模式: ${target.label}', 'Task dialog mode: ${target.label}');

String _singleAgentProviderTooltip(SingleAgentProvider provider) => appText(
  '单机智能体执行器: ${provider.label}',
  'Single-agent provider: ${provider.label}',
);

String _modelTooltip(String modelLabel) =>
    appText('模型: $modelLabel', 'Model: $modelLabel');

String _skillsTooltip(int selectedCount) => selectedCount <= 0
    ? appText('技能', 'Skills')
    : appText('技能: 已选 $selectedCount 个', 'Skills: $selectedCount selected');

String _permissionTooltip(AssistantPermissionLevel level) =>
    appText('权限: ${level.label}', 'Permissions: ${level.label}');

String _thinkingTooltip(String level) => appText(
  '推理强度: ${_assistantThinkingLabel(level)}',
  'Reasoning: ${_assistantThinkingLabel(level)}',
);

String _skillOptionTooltip(_ComposerSkillOption option) {
  final sourceLabel = option.sourceLabel.trim();
  return sourceLabel.isEmpty ? option.label : sourceLabel;
}
