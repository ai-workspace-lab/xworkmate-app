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

ComposerSkillOptionInternal skillOptionFromGatewayInternal(
  GatewaySkillSummary skill,
) {
  final key = skill.skillKey.trim().isEmpty
      ? skill.name.trim().toLowerCase()
      : skill.skillKey.trim();
  final label = skill.name.trim().isEmpty ? key : skill.name.trim();
  final sourceLabel = skill.source.trim().isEmpty ? 'Gateway' : skill.source;
  final group = skillGroupForSourceInternal(skill.source);
  final description = skill.description.trim().isEmpty
      ? appText('可在当前任务中调用的技能。', 'Skill available in the current task.')
      : skill.description.trim();

  return ComposerSkillOptionInternal(
    key: key,
    label: label,
    description: description,
    sourceLabel: sourceLabel,
    groupLabel: group.label,
    groupSortOrder: group.sortOrder,
    icon: Icons.key_rounded,
  );
}

ComposerSkillGroupInternal skillGroupForSourceInternal(String source) {
  final normalized = source.trim().toLowerCase();
  if (normalized == 'openclaw-workspace') {
    return const ComposerSkillGroupInternal(
      label: 'Workspace Skills',
      sortOrder: 0,
    );
  }
  if (normalized.startsWith('agents-skills-') ||
      normalized == 'agent' ||
      normalized.startsWith('agent-') ||
      normalized.contains('personal')) {
    return const ComposerSkillGroupInternal(
      label: 'Agent Skills',
      sortOrder: 1,
    );
  }
  if (normalized == 'bridge' || normalized == 'gateway') {
    return const ComposerSkillGroupInternal(
      label: 'Gateway Skills',
      sortOrder: 2,
    );
  }
  if (normalized.isEmpty) {
    return const ComposerSkillGroupInternal(
      label: 'Gateway Skills',
      sortOrder: 2,
    );
  }
  return const ComposerSkillGroupInternal(label: 'Other Skills', sortOrder: 3);
}

class ComposerSkillGroupInternal {
  const ComposerSkillGroupInternal({
    required this.label,
    required this.sortOrder,
  });

  final String label;
  final int sortOrder;
}

class ComposerSkillOptionInternal {
  const ComposerSkillOptionInternal({
    required this.key,
    required this.label,
    required this.description,
    required this.sourceLabel,
    required this.groupLabel,
    required this.groupSortOrder,
    required this.icon,
  });

  final String key;
  final String label;
  final String description;
  final String sourceLabel;
  final String groupLabel;
  final int groupSortOrder;
  final IconData icon;
}
