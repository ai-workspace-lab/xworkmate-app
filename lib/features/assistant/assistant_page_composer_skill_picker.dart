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
import 'assistant_page_composer_skill_models.dart';
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
    required this.hasQuery,
    required this.onQueryChanged,
    required this.onToggleSkill,
  });

  final double maxHeight;
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final List<String> selectedSkillKeys;
  final List<ComposerSkillOptionInternal> filteredSkills;
  final bool isLoading;
  final bool hasQuery;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String> onToggleSkill;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
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
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                        itemCount: filteredSkills.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final skill = filteredSkills[index];
                          return SkillPickerTileInternal(
                            key: ValueKey<String>(
                              'assistant-skill-option-${skill.key}',
                            ),
                            option: skill,
                            selected: selectedSkillKeys.contains(skill.key),
                            onTap: () => onToggleSkill(skill.key),
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
