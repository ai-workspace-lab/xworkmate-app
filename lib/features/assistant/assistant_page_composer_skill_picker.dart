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
import '../../app/app_controller.dart';
import '../../app/app_metadata.dart';
import '../../app/ui_feature_manifest.dart';
import '../../i18n/app_language.dart';
import '../../models/app_models.dart';
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
import 'assistant_page_composer_clipboard.dart';
import 'assistant_page_components_core.dart';

class ComposerSelectedSkillChipInternal extends StatelessWidget {
  const ComposerSelectedSkillChipInternal({
    super.key,
    required this.option,
    required this.onDeleted,
  });

  final ComposerSkillOptionInternal option;
  final VoidCallback onDeleted;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: skillOptionTooltipInternal(option),
      child: InputChip(
        avatar: Icon(option.icon, size: 16, color: context.palette.accent),
        label: Text(option.label),
        onDeleted: onDeleted,
        side: BorderSide.none,
        backgroundColor: context.palette.surfaceSecondary,
        deleteIconColor: context.palette.textMuted,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.chip),
        ),
      ),
    );
  }
}

class SkillPickerPopoverInternal extends StatelessWidget {
  const SkillPickerPopoverInternal({
    super.key,
    required this.maxHeight,
    required this.searchController,
    required this.searchFocusNode,
    required this.selectedSkillKeys,
    required this.filteredSkills,
    required this.isLoading,
    required this.errorText,
    required this.hasQuery,
    required this.onQueryChanged,
    required this.onToggleSkill,
    this.onRetry,
  });

  final double maxHeight;
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final List<String> selectedSkillKeys;
  final List<ComposerSkillOptionInternal> filteredSkills;
  final bool isLoading;
  final String? errorText;
  final bool hasQuery;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String> onToggleSkill;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    final groupedSkills = skillPickerSectionsInternal(filteredSkills);
    final hasError = !isLoading && (errorText?.trim().isNotEmpty ?? false);
    return Material(
      key: const Key('assistant-skill-picker-popover'),
      color: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: 360,
          maxWidth: 480,
          maxHeight: maxHeight,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: palette.surfacePrimary,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: palette.strokeSoft),
            boxShadow: [palette.chromeShadowAmbient],
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                child: TextField(
                  key: const Key('assistant-skill-picker-search'),
                  controller: searchController,
                  focusNode: searchFocusNode,
                  autofocus: true,
                  onChanged: onQueryChanged,
                  decoration: InputDecoration(
                    hintText: appText('搜索技能', 'Search skills'),
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: searchController.text.trim().isEmpty
                        ? null
                        : IconButton(
                            tooltip: appText('清除', 'Clear'),
                            onPressed: () {
                              searchController.clear();
                              onQueryChanged('');
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                  ),
                ),
              ),
              Container(height: 1, color: palette.strokeSoft),
              Expanded(
                child: filteredSkills.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isLoading) ...[
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: palette.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 12),
                              ],
                              Text(
                                isLoading
                                    ? appText('正在加载技能…', 'Loading skills…')
                                    : hasError
                                    ? appText(
                                        '技能列表加载失败，请稍后重试。',
                                        'Could not load skills. Please try again.',
                                      )
                                    : hasQuery
                                    ? appText('没有匹配的技能。', 'No matching skills.')
                                    : appText(
                                        '当前没有已加载技能。',
                                        'No skills are loaded yet.',
                                      ),
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: palette.textSecondary,
                                ),
                              ),
                              if (hasError) ...[
                                const SizedBox(height: 8),
                                Text(
                                  errorText!.trim(),
                                  textAlign: TextAlign.center,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: palette.textMuted,
                                  ),
                                ),
                              ],
                              if (!hasError && !isLoading && !hasQuery) ...[
                                const SizedBox(height: 8),
                                Text(
                                  appText(
                                    '技能来源于 Gateway 工作区。请确认 OpenClaw'
                                    ' Gateway 已连接且安装了技能包。',
                                    'Skills come from the Gateway workspace.'
                                    ' Make sure OpenClaw Gateway is connected'
                                    ' and skills are installed.',
                                  ),
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: palette.textMuted,
                                  ),
                                ),
                              ],
                              if ((hasError || (!isLoading && !hasQuery)) &&
                                  onRetry != null) ...[
                                const SizedBox(height: 12),
                                TextButton.icon(
                                  onPressed: onRetry,
                                  icon: const Icon(Icons.refresh_rounded, size: 16),
                                  label: Text(appText('重试', 'Retry')),
                                ),
                              ],
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                        itemCount: groupedSkills.length,
                        itemBuilder: (context, index) {
                          final row = groupedSkills[index];
                          if (row.headerLabel != null) {
                            return SkillPickerGroupHeaderInternal(
                              key: ValueKey<String>(
                                'assistant-skill-group-${row.headerLabel}',
                              ),
                              label: row.headerLabel!,
                            );
                          }
                          final skill = row.skill!;
                          return Padding(
                            padding: EdgeInsets.only(
                              bottom: index == groupedSkills.length - 1 ? 0 : 8,
                            ),
                            child: SkillPickerTileInternal(
                              key: ValueKey<String>(
                                'assistant-skill-option-${skill.key}',
                              ),
                              option: skill,
                              selected: selectedSkillKeys.contains(skill.key),
                              onTap: () => onToggleSkill(skill.key),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

List<SkillPickerRowInternal> skillPickerSectionsInternal(
  List<ComposerSkillOptionInternal> skills,
) {
  final groupsByLabel = <String, List<ComposerSkillOptionInternal>>{};
  final groupSortOrders = <String, int>{};
  for (final skill in skills) {
    groupsByLabel.putIfAbsent(skill.groupLabel, () => []).add(skill);
    groupSortOrders[skill.groupLabel] = skill.groupSortOrder;
  }
  final labels = groupsByLabel.keys.toList(growable: false)
    ..sort((a, b) {
      final orderCompare = (groupSortOrders[a] ?? 999).compareTo(
        groupSortOrders[b] ?? 999,
      );
      if (orderCompare != 0) {
        return orderCompare;
      }
      return a.compareTo(b);
    });

  final rows = <SkillPickerRowInternal>[];
  for (final label in labels) {
    rows.add(SkillPickerRowInternal.header(label));
    for (final skill in groupsByLabel[label]!) {
      rows.add(SkillPickerRowInternal.skill(skill));
    }
  }
  return rows;
}

class SkillPickerRowInternal {
  const SkillPickerRowInternal.header(this.headerLabel) : skill = null;
  const SkillPickerRowInternal.skill(this.skill) : headerLabel = null;

  final String? headerLabel;
  final ComposerSkillOptionInternal? skill;
}

class SkillPickerGroupHeaderInternal extends StatelessWidget {
  const SkillPickerGroupHeaderInternal({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelMedium?.copyWith(
          color: palette.textSecondary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class SkillPickerTileInternal extends StatelessWidget {
  const SkillPickerTileInternal({
    super.key,
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final ComposerSkillOptionInternal option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;

    return Tooltip(
      message: skillOptionTooltipInternal(option),
      waitDuration: const Duration(milliseconds: 250),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: selected
                  ? palette.surfaceSecondary
                  : palette.surfacePrimary,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: palette.strokeSoft),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    option.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

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
