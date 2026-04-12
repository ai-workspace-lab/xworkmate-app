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
import 'assistant_page_tooltip_labels.dart';
import 'assistant_page_message_widgets.dart';
import 'assistant_page_task_models.dart';
import 'assistant_page_composer_skill_models.dart';
import 'assistant_page_composer_skill_picker.dart';
import 'assistant_page_composer_clipboard.dart';
import 'assistant_page_components_core.dart';

class ComposerIconButtonInternal extends StatefulWidget {
  const ComposerIconButtonInternal({super.key, required this.icon});

  final IconData icon;

  @override
  State<ComposerIconButtonInternal> createState() =>
      ComposerIconButtonStateInternal();
}

class ComposerResizeHandleInternal extends StatefulWidget {
  const ComposerResizeHandleInternal({super.key, required this.onDelta});

  final ValueChanged<double> onDelta;

  @override
  State<ComposerResizeHandleInternal> createState() =>
      ComposerResizeHandleStateInternal();
}

class ComposerResizeHandleStateInternal
    extends State<ComposerResizeHandleInternal> {
  bool hoveredInternal = false;
  bool draggingInternal = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final highlight = hoveredInternal || draggingInternal;

    return MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      onEnter: (_) => setState(() => hoveredInternal = true),
      onExit: (_) => setState(() => hoveredInternal = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragStart: (_) => setState(() => draggingInternal = true),
        onVerticalDragEnd: (_) => setState(() => draggingInternal = false),
        onVerticalDragCancel: () => setState(() => draggingInternal = false),
        onVerticalDragUpdate: (details) => widget.onDelta(details.delta.dy),
        child: SizedBox(
          height: 12,
          width: double.infinity,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: 42,
              height: 2,
              decoration: BoxDecoration(
                color: highlight
                    ? palette.accent.withValues(alpha: 0.72)
                    : palette.strokeSoft,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ComposerIconButtonStateInternal
    extends State<ComposerIconButtonInternal> {
  bool hoveredInternal = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return MouseRegion(
      onEnter: (_) => setState(() => hoveredInternal = true),
      onExit: (_) => setState(() => hoveredInternal = false),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: hoveredInternal
              ? palette.surfaceSecondary
              : palette.surfacePrimary,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: palette.strokeSoft),
        ),
        child: Icon(widget.icon, size: 18, color: palette.textMuted),
      ),
    );
  }
}

class ComposerToolbarChipInternal extends StatefulWidget {
  const ComposerToolbarChipInternal({
    super.key,
    this.icon,
    this.leading,
    required this.tooltip,
    required this.showChevron,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppSpacing.xs,
      vertical: 6,
    ),
  });

  final IconData? icon;
  final Widget? leading;
  final String tooltip;
  final bool showChevron;
  final EdgeInsetsGeometry padding;

  @override
  State<ComposerToolbarChipInternal> createState() =>
      ComposerToolbarChipStateInternal();
}

class ComposerToolbarChipStateInternal
    extends State<ComposerToolbarChipInternal> {
  bool hoveredInternal = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    final chip = MouseRegion(
      onEnter: (_) => setState(() => hoveredInternal = true),
      onExit: (_) => setState(() => hoveredInternal = false),
      child: Container(
        padding: widget.padding,
        decoration: BoxDecoration(
          color: hoveredInternal
              ? palette.surfaceSecondary
              : palette.surfacePrimary,
          borderRadius: BorderRadius.circular(AppRadius.chip),
          border: Border.all(color: palette.strokeSoft),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            widget.leading ??
                Icon(widget.icon, size: 16, color: palette.textMuted),
            if (widget.showChevron) ...[
              const SizedBox(width: 1),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 14,
                color: palette.textMuted,
              ),
            ],
          ],
        ),
      ),
    );
    final tooltip = widget.tooltip.trim();
    if (tooltip.isEmpty) {
      return chip;
    }
    return Tooltip(message: tooltip, child: chip);
  }
}

extension AssistantExecutionTargetIconInternal on AssistantExecutionTarget {
  IconData get icon => switch (this) {
    AssistantExecutionTarget.agent => Icons.cloud_outlined,
    AssistantExecutionTarget.gateway => Icons.cloud_outlined,
  };
}

extension AssistantPermissionLevelIconInternal on AssistantPermissionLevel {
  IconData get icon => switch (this) {
    AssistantPermissionLevel.defaultAccess => Icons.verified_user_outlined,
    AssistantPermissionLevel.fullAccess => Icons.error_outline_rounded,
  };
}

class SingleAgentProviderBadgeInternal extends StatelessWidget {
  const SingleAgentProviderBadgeInternal({super.key, required this.provider});

  final SingleAgentProvider provider;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final candidate = provider.badge.trim().isEmpty
        ? provider.label
        : provider.badge;
    final display = candidate.trim().isEmpty
        ? '?'
        : candidate.length <= 2
        ? candidate
        : candidate.substring(0, 2);
    return Container(
      width: 18,
      height: 18,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: palette.surfaceSecondary,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.strokeSoft),
      ),
      child: Text(
        display,
        maxLines: 1,
        overflow: TextOverflow.clip,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: palette.textMuted,
          fontWeight: FontWeight.w700,
          fontSize: 9,
          height: 1,
        ),
      ),
    );
  }
}
