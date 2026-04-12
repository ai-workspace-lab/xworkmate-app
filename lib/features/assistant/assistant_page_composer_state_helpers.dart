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
import 'assistant_page_composer_support.dart';
import 'assistant_page_tooltip_labels.dart';
import 'assistant_page_message_widgets.dart';
import 'assistant_page_task_models.dart';
import 'assistant_page_composer_skill_models.dart';
import 'assistant_page_composer_skill_picker.dart';
import 'assistant_page_composer_clipboard.dart';
import 'assistant_page_components_core.dart';

const double skillPickerPreferredMaxHeightInternal = 460;
const double skillPickerMinHeightInternal = 220;
const double skillPickerVerticalGapInternal = 8;

Widget buildSkillPickerOverlayForInternal(
  ComposerBarStateInternal state,
  BuildContext context,
) {
  final mediaQuery = MediaQuery.of(context);
  final targetBox =
      state.skillPickerTargetKeyInternal.currentContext?.findRenderObject()
          as RenderBox?;
  final targetOrigin = targetBox?.localToGlobal(Offset.zero);
  final targetSize = targetBox?.size;
  final availableBelow = targetOrigin == null || targetSize == null
      ? skillPickerPreferredMaxHeightInternal
      : mediaQuery.size.height -
            mediaQuery.padding.bottom -
            (targetOrigin.dy + targetSize.height) -
            skillPickerVerticalGapInternal;
  final availableAbove = targetOrigin == null
      ? skillPickerPreferredMaxHeightInternal
      : targetOrigin.dy -
            mediaQuery.padding.top -
            skillPickerVerticalGapInternal;
  final openUpward =
      availableBelow < skillPickerMinHeightInternal &&
      availableAbove > availableBelow;
  final constrainedHeight = math.max(
    skillPickerMinHeightInternal,
    openUpward ? availableAbove : availableBelow,
  );
  final maxHeight = math.min(
    skillPickerPreferredMaxHeightInternal,
    constrainedHeight,
  );
  return Stack(
    children: [
      Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: state.hideSkillPickerInternal,
          child: const SizedBox.expand(),
        ),
      ),
      CompositedTransformFollower(
        link: state.skillPickerLayerLinkInternal,
        showWhenUnlinked: false,
        targetAnchor: openUpward ? Alignment.topLeft : Alignment.bottomLeft,
        followerAnchor: openUpward ? Alignment.bottomLeft : Alignment.topLeft,
        offset: Offset(0, openUpward ? -skillPickerVerticalGapInternal : 8),
        child: SkillPickerPopoverInternal(
          maxHeight: maxHeight,
          searchController: state.skillPickerSearchControllerInternal,
          searchFocusNode: state.skillPickerSearchFocusNodeInternal,
          selectedSkillKeys: state.widget.selectedSkillKeys,
          filteredSkills: state.filteredSkillOptionsInternal(),
          isLoading: false,
          hasQuery: state.skillPickerQueryInternal.trim().isNotEmpty,
          onQueryChanged: state.setSkillPickerQueryInternal,
          onToggleSkill: (skillKey) => state.widget.onToggleSkill(skillKey),
        ),
      ),
    ],
  );
}
