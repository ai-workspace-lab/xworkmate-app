// ignore_for_file: unused_import, unnecessary_import

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:path_provider/path_provider.dart';
import 'package:super_clipboard/super_clipboard.dart';
import '../../app/app_controller.dart';
import '../../app/app_metadata.dart';
import '../../app/ui_feature_manifest.dart';
import '../../i18n/app_language.dart';
import '../../models/app_models.dart';
import '../../runtime/multi_agent_orchestrator.dart';
import '../../runtime/runtime_models.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../widgets/assistant_focus_panel.dart';
import '../../widgets/assistant_artifact_sidebar.dart';
import '../../widgets/desktop_workspace_scaffold.dart';
import '../../widgets/pane_resize_handle.dart';
import '../../widgets/surface_card.dart';
import 'assistant_page_main.dart';
import 'assistant_page_components.dart';
import 'assistant_page_composer_bar.dart';
import 'assistant_page_composer_state_helpers.dart';
import 'assistant_page_composer_support.dart';
import 'assistant_page_message_widgets.dart';
import 'assistant_page_task_models.dart';
import 'assistant_page_composer_skill_models.dart';
import 'assistant_page_composer_skill_picker.dart';
import 'assistant_page_composer_clipboard.dart';
import 'assistant_page_components_core.dart';

String executionTargetTooltipInternal(AssistantExecutionTarget target) =>
    appText(
      '任务对话模式: ${target.compactLabel}',
      'Task dialog mode: ${target.compactLabel}',
    );

String providerTooltipInternal(SingleAgentProvider provider) => appText(
  '智能体 Provider: ${provider.label}',
  'Agent provider: ${provider.label}',
);

String modelTooltipInternal(String modelLabel) =>
    appText('模型: $modelLabel', 'Model: $modelLabel');

String skillsTooltipInternal(int selectedCount) => selectedCount <= 0
    ? appText('技能', 'Skills')
    : appText('技能: 已选 $selectedCount 个', 'Skills: $selectedCount selected');

String permissionTooltipInternal(AssistantPermissionLevel level) =>
    appText('权限: ${level.label}', 'Permissions: ${level.label}');

String thinkingTooltipInternal(String level) => appText(
  '推理强度: ${assistantThinkingLabelInternal(level)}',
  'Reasoning: ${assistantThinkingLabelInternal(level)}',
);

String skillOptionTooltipInternal(ComposerSkillOptionInternal option) {
  final sourceLabel = option.sourceLabel.trim();
  return sourceLabel.isEmpty ? option.label : sourceLabel;
}
