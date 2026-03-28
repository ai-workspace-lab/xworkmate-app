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
import 'assistant_page_tooltip_labels.dart';
import 'assistant_page_message_widgets.dart';
import 'assistant_page_task_models.dart';
import 'assistant_page_composer_skill_picker.dart';
import 'assistant_page_composer_clipboard.dart';
import 'assistant_page_components_core.dart';

const List<ComposerSkillOptionInternal> fallbackSkillOptionsInternal =
    <ComposerSkillOptionInternal>[
      ComposerSkillOptionInternal(
        key: '1password',
        label: '1password',
        description: '安全读取和注入本地凭据。',
        sourceLabel: 'Local',
        icon: Icons.auto_awesome_rounded,
      ),
      ComposerSkillOptionInternal(
        key: 'xlsx',
        label: 'xlsx',
        description: '读取、整理和生成表格文件。',
        sourceLabel: 'Local',
        icon: Icons.auto_awesome_rounded,
      ),
      ComposerSkillOptionInternal(
        key: 'web-processing',
        label: '网页处理',
        description: '打开网页、提取内容并完成网页操作。',
        sourceLabel: 'Web',
        icon: Icons.language_rounded,
      ),
      ComposerSkillOptionInternal(
        key: 'apple-reminders',
        label: 'apple-reminders',
        description: '管理提醒事项和任务提醒。',
        sourceLabel: 'Local',
        icon: Icons.auto_awesome_rounded,
      ),
      ComposerSkillOptionInternal(
        key: 'blogwatcher',
        label: 'blogwatcher',
        description: '跟踪博客更新并生成摘要。',
        sourceLabel: 'Local',
        icon: Icons.auto_awesome_rounded,
      ),
    ];

ComposerSkillOptionInternal skillOptionFromGatewayInternal(
  GatewaySkillSummary skill,
) {
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

  return ComposerSkillOptionInternal(
    key: key,
    label: label,
    description: description,
    sourceLabel: sourceLabel,
    icon: isWebSkill ? Icons.language_rounded : Icons.auto_awesome_rounded,
  );
}

ComposerSkillOptionInternal skillOptionFromThreadSkillInternal(
  AssistantThreadSkillEntry skill,
) {
  return ComposerSkillOptionInternal(
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

class ComposerSkillOptionInternal {
  const ComposerSkillOptionInternal({
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
