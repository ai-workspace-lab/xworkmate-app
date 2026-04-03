// ignore_for_file: unused_import, unnecessary_import

import 'dart:async';
import 'package:flutter/material.dart';
import '../app/app_controller_web.dart';
import '../app/app_metadata.dart';
import '../app/ui_feature_manifest.dart';
import '../i18n/app_language.dart';
import '../models/app_models.dart';
import '../runtime/runtime_models.dart';
import '../theme/app_palette.dart';
import '../widgets/desktop_workspace_scaffold.dart';
import '../widgets/section_tabs.dart';
import '../widgets/surface_card.dart';
import '../widgets/top_bar.dart';
import 'web_settings_page_core.dart';
import 'web_settings_page_sections.dart';
import 'web_settings_page_gateway.dart';

void setIfDifferentInternal(TextEditingController controller, String value) {
  if (controller.text == value) {
    return;
  }
  controller.value = controller.value.copyWith(
    text: value,
    selection: TextSelection.collapsed(offset: value.length),
    composing: TextRange.empty,
  );
}

String themeLabelInternal(ThemeMode mode) {
  return switch (mode) {
    ThemeMode.light => appText('浅色', 'Light'),
    ThemeMode.dark => appText('深色', 'Dark'),
    ThemeMode.system => appText('跟随系统', 'System'),
  };
}

String targetLabelInternal(AssistantExecutionTarget target) {
  return switch (target) {
    AssistantExecutionTarget.auto => 'Auto',
    AssistantExecutionTarget.singleAgent => appText(
      'Single Agent',
      'Single Agent',
    ),
    AssistantExecutionTarget.local => appText('Local Gateway', 'Local Gateway'),
    AssistantExecutionTarget.remote => appText(
      'Remote Gateway',
      'Remote Gateway',
    ),
  };
}

enum StatusChipToneInternal { idle, ready }

class StatusChipInternal extends StatelessWidget {
  const StatusChipInternal({
    super.key,
    required this.label,
    required this.tone,
  });

  final String label;
  final StatusChipToneInternal tone;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final background = switch (tone) {
      StatusChipToneInternal.idle => palette.surfaceSecondary,
      StatusChipToneInternal.ready => palette.accent.withValues(alpha: 0.14),
    };
    final foreground = switch (tone) {
      StatusChipToneInternal.idle => palette.textSecondary,
      StatusChipToneInternal.ready => palette.accent,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
