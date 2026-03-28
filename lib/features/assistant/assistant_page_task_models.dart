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
import 'assistant_page_composer_skill_models.dart';
import 'assistant_page_composer_skill_picker.dart';
import 'assistant_page_composer_clipboard.dart';
import 'assistant_page_components_core.dart';

enum BubbleToneInternal { user, assistant, agent }

enum TimelineItemKindInternal { user, assistant, agent, toolCall }

class TimelineItemInternal {
  const TimelineItemInternal._({
    required this.kind,
    this.label,
    this.text,
    this.title,
    this.pending = false,
    this.error = false,
  });

  const TimelineItemInternal.message({
    required TimelineItemKindInternal kind,
    required String label,
    required String text,
    required bool pending,
    required bool error,
  }) : this._(
         kind: kind,
         label: label,
         text: text,
         pending: pending,
         error: error,
       );

  const TimelineItemInternal.toolCall({
    required String toolName,
    required String summary,
    required bool pending,
    required bool error,
  }) : this._(
         kind: TimelineItemKindInternal.toolCall,
         title: toolName,
         text: summary,
         pending: pending,
         error: error,
       );

  final TimelineItemKindInternal kind;
  final String? label;
  final String? text;
  final String? title;
  final bool pending;
  final bool error;
}

class AssistantTaskSeedInternal {
  const AssistantTaskSeedInternal({
    required this.sessionKey,
    required this.title,
    required this.preview,
    required this.status,
    required this.updatedAtMs,
    required this.owner,
    required this.surface,
    required this.executionTarget,
    required this.draft,
  });

  final String sessionKey;
  final String title;
  final String preview;
  final String status;
  final double updatedAtMs;
  final String owner;
  final String surface;
  final AssistantExecutionTarget executionTarget;
  final bool draft;

  AssistantTaskEntryInternal toEntry({required bool isCurrent}) {
    return AssistantTaskEntryInternal(
      sessionKey: sessionKey,
      title: title,
      preview: preview,
      status: status,
      updatedAtMs: updatedAtMs,
      owner: owner,
      surface: surface,
      executionTarget: executionTarget,
      isCurrent: isCurrent,
      draft: draft,
    );
  }
}

class AssistantTaskEntryInternal {
  const AssistantTaskEntryInternal({
    required this.sessionKey,
    required this.title,
    required this.preview,
    required this.status,
    required this.updatedAtMs,
    required this.owner,
    required this.surface,
    required this.executionTarget,
    required this.isCurrent,
    this.draft = false,
  });

  final String sessionKey;
  final String title;
  final String preview;
  final String status;
  final double? updatedAtMs;
  final String owner;
  final String surface;
  final AssistantExecutionTarget executionTarget;
  final bool isCurrent;
  final bool draft;

  AssistantTaskEntryInternal copyWith({
    String? sessionKey,
    String? title,
    String? preview,
    String? status,
    double? updatedAtMs,
    String? owner,
    String? surface,
    AssistantExecutionTarget? executionTarget,
    bool? isCurrent,
    bool? draft,
  }) {
    return AssistantTaskEntryInternal(
      sessionKey: sessionKey ?? this.sessionKey,
      title: title ?? this.title,
      preview: preview ?? this.preview,
      status: status ?? this.status,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      owner: owner ?? this.owner,
      surface: surface ?? this.surface,
      executionTarget: executionTarget ?? this.executionTarget,
      isCurrent: isCurrent ?? this.isCurrent,
      draft: draft ?? this.draft,
    );
  }

  String get updatedAtLabel => sessionUpdatedAtLabelInternal(updatedAtMs);
}

class AssistantTaskGroupInternal {
  const AssistantTaskGroupInternal({
    required this.executionTarget,
    required this.items,
  });

  final AssistantExecutionTarget executionTarget;
  final List<AssistantTaskEntryInternal> items;
}

class PillStyleInternal {
  const PillStyleInternal({
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final Color backgroundColor;
  final Color foregroundColor;
}

class MetaPillInternal extends StatelessWidget {
  const MetaPillInternal({super.key, required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        if (maxWidth.isFinite && maxWidth < 20) {
          return const SizedBox.shrink();
        }
        final showText = !maxWidth.isFinite || maxWidth >= 52;
        final horizontalPadding = showText ? 10.0 : 8.0;
        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: palette.surfaceSecondary,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: palette.strokeSoft),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: palette.textMuted),
              if (showText) ...[
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

PillStyleInternal pillStyleForStatusInternal(
  BuildContext context,
  String label,
) {
  final theme = Theme.of(context);
  final normalized = normalizedTaskStatusInternal(label);
  return switch (normalized) {
    'running' => PillStyleInternal(
      backgroundColor: context.palette.accentMuted,
      foregroundColor: theme.colorScheme.primary,
    ),
    'queued' => PillStyleInternal(
      backgroundColor: context.palette.surfaceSecondary,
      foregroundColor: context.palette.textSecondary,
    ),
    'failed' || 'error' => PillStyleInternal(
      backgroundColor: context.palette.surfacePrimary,
      foregroundColor: theme.colorScheme.error,
    ),
    _ => PillStyleInternal(
      backgroundColor: context.palette.surfacePrimary,
      foregroundColor: theme.colorScheme.tertiary,
    ),
  };
}

String normalizedTaskStatusInternal(String status) {
  final value = status.trim().toLowerCase();
  return switch (value) {
    'running' => 'running',
    'queued' => 'queued',
    'failed' => 'failed',
    'error' => 'error',
    'open' => 'open',
    _ => 'open',
  };
}

String toolCallStatusLabelInternal(String status) =>
    switch (normalizedTaskStatusInternal(status)) {
      'running' => appText('运行中', 'Running'),
      'failed' || 'error' => appText('错误', 'Error'),
      _ => appText('已完成', 'Completed'),
    };

String assistantThinkingLabelInternal(String level) => switch (level) {
  'low' => appText('低', 'Low'),
  'medium' => appText('中', 'Medium'),
  'max' => appText('超高', 'Max'),
  _ => appText('高', 'High'),
};

String sessionDisplayTitleInternal(GatewaySessionSummary session) {
  final label = session.label.trim();
  if (label.isEmpty || label == session.key) {
    return fallbackSessionTitleInternal(session.key);
  }
  if ((label == 'main' || label == 'agent:main:main') &&
      (session.derivedTitle ?? '').trim().toLowerCase() == 'main') {
    return fallbackSessionTitleInternal(session.key);
  }
  return label;
}

String fallbackSessionTitleInternal(String sessionKey) {
  final trimmed = sessionKey.trim();
  if (trimmed == 'main' || trimmed == 'agent:main:main') {
    return appText('默认任务', 'Default task');
  }
  if (trimmed.startsWith('draft:')) {
    return appText('新对话', 'New conversation');
  }
  final parts = trimmed.split(':');
  if (parts.length >= 3 && parts.first == 'agent' && parts.last == 'main') {
    return appText('默认任务', 'Default task');
  }
  return trimmed.isEmpty ? appText('未命名对话', 'Untitled conversation') : trimmed;
}

String? sessionPreviewInternal(GatewaySessionSummary session) {
  final preview = session.lastMessagePreview?.trim();
  if (preview != null && preview.isNotEmpty) {
    return preview;
  }
  final subject = session.subject?.trim();
  if (subject != null && subject.isNotEmpty) {
    return subject;
  }
  return null;
}

String sessionStatusInternal(
  GatewaySessionSummary session, {
  required bool sessionPending,
}) {
  if (session.abortedLastRun == true) {
    return 'failed';
  }
  if (sessionPending) {
    return 'running';
  }
  if ((session.lastMessagePreview ?? '').trim().isEmpty) {
    return 'queued';
  }
  return 'open';
}

String sessionUpdatedAtLabelInternal(double? updatedAtMs) {
  if (updatedAtMs == null) {
    return appText('未知', 'Unknown');
  }
  final delta = DateTime.now().difference(
    DateTime.fromMillisecondsSinceEpoch(updatedAtMs.toInt()),
  );
  if (delta.inMinutes < 1) {
    return appText('刚刚', 'Now');
  }
  if (delta.inHours < 1) {
    return '${delta.inMinutes}m';
  }
  if (delta.inDays < 1) {
    return '${delta.inHours}h';
  }
  return '${delta.inDays}d';
}

double estimatedComposerWrapSectionHeightInternal({
  required int itemCount,
  required double availableWidth,
  required double averageChipWidth,
}) {
  if (itemCount <= 0) {
    return 0;
  }
  final itemsPerRow = math.max(1, (availableWidth / averageChipWidth).floor());
  final rows = (itemCount / itemsPerRow).ceil();
  const chipHeight = 32.0;
  const runSpacing = 6.0;
  const sectionSpacing = 6.0;
  return sectionSpacing + (rows * chipHeight) + ((rows - 1) * runSpacing);
}

bool sessionKeysMatchInternal(String incoming, String current) {
  final left = incoming.trim().toLowerCase();
  final right = current.trim().toLowerCase();
  if (left == right) {
    return true;
  }
  return (left == 'agent:main:main' && right == 'main') ||
      (left == 'main' && right == 'agent:main:main');
}
