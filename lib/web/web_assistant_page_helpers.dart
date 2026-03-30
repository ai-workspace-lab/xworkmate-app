// ignore_for_file: unused_import, unnecessary_import

import 'dart:convert';
import 'dart:math' as math;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import '../app/app_controller_web.dart';
import '../app/ui_feature_manifest.dart';
import '../i18n/app_language.dart';
import '../models/app_models.dart';
import '../runtime/runtime_models.dart';
import '../theme/app_palette.dart';
import '../theme/app_theme.dart';
import '../widgets/assistant_artifact_sidebar.dart';
import '../widgets/desktop_workspace_scaffold.dart';
import '../widgets/pane_resize_handle.dart';
import '../widgets/surface_card.dart';
import 'web_assistant_page_core.dart';
import 'web_assistant_page_chrome.dart';
import 'web_assistant_page_workspace.dart';

class ChromePillInternal extends StatelessWidget {
  const ChromePillInternal({
    super.key,
    this.icon,
    required this.label,
    this.emphasized = false,
    this.compact = false,
  });

  final IconData? icon;
  final String label;
  final bool emphasized;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      constraints: const BoxConstraints(minHeight: 40),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 14,
        vertical: compact ? 7 : 8,
      ),
      decoration: BoxDecoration(
        color: emphasized ? palette.surfacePrimary : palette.surfaceSecondary,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(color: palette.strokeSoft),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 16), const SizedBox(width: 8)],
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: emphasized ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class HeaderDropdownShellInternal extends StatelessWidget {
  const HeaderDropdownShellInternal({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 40),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: context.palette.surfacePrimary,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(color: context.palette.strokeSoft),
      ),
      child: child,
    );
  }
}

class SessionSettingFieldInternal extends StatelessWidget {
  const SessionSettingFieldInternal({
    super.key,
    required this.label,
    required this.child,
  });

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

class MetaChipInternal extends StatelessWidget {
  const MetaChipInternal({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: context.palette.surfacePrimary,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: context.palette.strokeSoft),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: context.palette.textSecondary),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class CompactDropdownInternal<T> extends StatelessWidget {
  const CompactDropdownInternal({
    super.key,
    required this.value,
    required this.items,
    required this.labelBuilder,
    required this.onChanged,
  });

  final T value;
  final List<T> items;
  final String Function(T item) labelBuilder;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }
    return DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        value: items.contains(value) ? value : items.first,
        onChanged: onChanged,
        items: items
            .map(
              (item) => DropdownMenuItem<T>(
                value: item,
                child: Text(labelBuilder(item)),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class WebComposerAttachmentInternal {
  const WebComposerAttachmentInternal({
    required this.file,
    required this.name,
    required this.mimeType,
    required this.icon,
  });

  final XFile file;
  final String name;
  final String mimeType;
  final IconData icon;

  factory WebComposerAttachmentInternal.fromXFile(XFile file) {
    final extension = file.name.split('.').last.toLowerCase();
    final mimeType = file.mimeType?.trim().isNotEmpty == true
        ? file.mimeType!.trim()
        : switch (extension) {
            'png' => 'image/png',
            'jpg' || 'jpeg' => 'image/jpeg',
            'gif' => 'image/gif',
            'webp' => 'image/webp',
            'json' => 'application/json',
            'csv' => 'text/csv',
            'txt' || 'log' || 'md' || 'yaml' || 'yml' => 'text/plain',
            'pdf' => 'application/pdf',
            _ => 'application/octet-stream',
          };
    final icon = mimeType.startsWith('image/')
        ? Icons.image_outlined
        : mimeType == 'application/pdf'
        ? Icons.picture_as_pdf_outlined
        : Icons.insert_drive_file_outlined;
    return WebComposerAttachmentInternal(
      file: file,
      name: file.name,
      mimeType: mimeType,
      icon: icon,
    );
  }
}

List<WebConversationSummary> filterConversationsInternal(
  List<WebConversationSummary> items,
  String query,
) {
  if (query.trim().isEmpty) {
    return items;
  }
  final normalized = query.trim().toLowerCase();
  return items
      .where((item) {
        final haystack = '${item.title}\n${item.preview}'.toLowerCase();
        return haystack.contains(normalized);
      })
      .toList(growable: false);
}

String relativeTimeLabelInternal(double updatedAtMs) {
  final delta = DateTime.now().difference(
    DateTime.fromMillisecondsSinceEpoch(updatedAtMs.round()),
  );
  if (delta.inMinutes < 1) {
    return appText('刚刚', 'now');
  }
  if (delta.inHours < 1) {
    return '${delta.inMinutes}m';
  }
  if (delta.inDays < 1) {
    return '${delta.inHours}h';
  }
  return '${delta.inDays}d';
}

String thinkingLabelInternal(String level) {
  return switch (level) {
    'low' => appText('低', 'Low'),
    'medium' => appText('中', 'Medium'),
    'high' => appText('高', 'High'),
    _ => level,
  };
}

String targetLabelInternal(AssistantExecutionTarget target) {
  return switch (target) {
    AssistantExecutionTarget.singleAgent => appText('单机智能体', 'Single Agent'),
    AssistantExecutionTarget.local => appText(
      '本地 OpenClaw Gateway',
      'Local Gateway',
    ),
    AssistantExecutionTarget.remote => appText(
      '远程 OpenClaw Gateway',
      'Remote Gateway',
    ),
  };
}
