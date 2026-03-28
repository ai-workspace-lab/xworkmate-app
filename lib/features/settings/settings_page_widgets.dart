// ignore_for_file: unused_import, unnecessary_import

import 'dart:async';
import 'package:flutter/material.dart';
import '../../app/app_controller.dart';
import '../../app/app_metadata.dart';
import '../../app/app_store_policy.dart';
import '../../app/ui_feature_manifest.dart';
import '../../app/workspace_navigation.dart';
import '../../i18n/app_language.dart';
import '../../models/app_models.dart';
import '../../runtime/gateway_runtime.dart';
import '../../runtime/runtime_controllers.dart';
import '../../runtime/runtime_models.dart';
import 'codex_integration_card.dart';
import 'skill_directory_authorization_card.dart';
import '../../widgets/section_tabs.dart';
import '../../widgets/surface_card.dart';
import '../../widgets/top_bar.dart';
import 'settings_page_core.dart';
import 'settings_page_sections.dart';
import 'settings_page_gateway.dart';
import 'settings_page_gateway_connection.dart';
import 'settings_page_gateway_llm.dart';
import 'settings_page_presentation.dart';
import 'settings_page_multi_agent.dart';
import 'settings_page_support.dart';
import 'settings_page_device.dart';

class EditableFieldInternal extends StatefulWidget {
  const EditableFieldInternal({
    super.key,
    required this.label,
    required this.value,
    required this.onSubmitted,
  });

  final String label;
  final String value;
  final ValueChanged<String> onSubmitted;

  @override
  State<EditableFieldInternal> createState() => EditableFieldStateInternal();
}

class EditableFieldStateInternal extends State<EditableFieldInternal> {
  late final TextEditingController controllerInternal;

  @override
  void initState() {
    super.initState();
    controllerInternal = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant EditableFieldInternal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value == controllerInternal.text) {
      return;
    }
    controllerInternal.value = controllerInternal.value.copyWith(
      text: widget.value,
      selection: TextSelection.collapsed(offset: widget.value.length),
      composing: TextRange.empty,
    );
  }

  @override
  void dispose() {
    controllerInternal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        key: ValueKey('${widget.label}:${widget.value}'),
        controller: controllerInternal,
        decoration: InputDecoration(labelText: widget.label),
        onChanged: widget.onSubmitted,
        onFieldSubmitted: widget.onSubmitted,
      ),
    );
  }
}

class SwitchRowInternal extends StatelessWidget {
  const SwitchRowInternal({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      value: value,
      onChanged: onChanged,
    );
  }
}

class MountTargetCardInternal extends StatelessWidget {
  const MountTargetCardInternal({super.key, required this.target});

  final ManagedMountTargetState target;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = target.available
        ? theme.colorScheme.primary
        : theme.colorScheme.outline;
    final summary = <String>[
      '${appText('发现', 'Discovery')}: ${target.discoveryState}',
      '${appText('同步', 'Sync')}: ${target.syncState}',
      if (target.supportsSkills)
        '${appText('技能', 'Skills')}: ${target.discoveredSkillCount}',
      if (target.supportsMcp)
        '${appText('MCP', 'MCP')}: ${target.discoveredMcpCount}',
      if (target.supportsMcp)
        '${appText('托管', 'Managed')}: ${target.managedMcpCount}',
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(target.label, style: theme.textTheme.titleMedium),
                ),
                Text(
                  target.available
                      ? appText('可用', 'Available')
                      : appText('未安装', 'Missing'),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(summary.join(' · '), style: theme.textTheme.bodySmall),
            if (target.detail.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(target.detail, style: theme.textTheme.bodyMedium),
            ],
          ],
        ),
      ),
    );
  }
}

class InlineSwitchFieldInternal extends StatelessWidget {
  const InlineSwitchFieldInternal({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                style: theme.textTheme.labelLarge,
                softWrap: true,
              ),
            ),
            const SizedBox(width: 12),
            Switch.adaptive(
              value: value,
              onChanged: onChanged,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
      ),
    );
  }
}

class AiGatewayFeedbackThemeInternal {
  const AiGatewayFeedbackThemeInternal({
    required this.background,
    required this.border,
    required this.foreground,
  });

  final Color background;
  final Color border;
  final Color foreground;
}

class SecretFieldUiStateInternal {
  const SecretFieldUiStateInternal({
    this.showPlaintext = false,
    this.hasDraft = false,
    this.loading = false,
  });

  final bool showPlaintext;
  final bool hasDraft;
  final bool loading;

  SecretFieldUiStateInternal copyWith({
    bool? showPlaintext,
    bool? hasDraft,
    bool? loading,
  }) {
    return SecretFieldUiStateInternal(
      showPlaintext: showPlaintext ?? this.showPlaintext,
      hasDraft: hasDraft ?? this.hasDraft,
      loading: loading ?? this.loading,
    );
  }
}

class InfoRowInternal extends StatelessWidget {
  const InfoRowInternal({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label, style: Theme.of(context).textTheme.labelLarge),
          ),
          const SizedBox(width: 16),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}

/// Agent 角色配置卡片
class AgentRoleCardInternal extends StatelessWidget {
  const AgentRoleCardInternal({
    super.key,
    required this.title,
    required this.description,
    required this.cliTool,
    required this.model,
    required this.enabled,
    required this.cliOptions,
    required this.modelOptions,
    required this.onCliChanged,
    required this.onModelChanged,
    required this.onEnabledChanged,
  });

  final String title;
  final String description;
  final String cliTool;
  final String model;
  final bool enabled;
  final List<String> cliOptions;
  final List<String> modelOptions;
  final ValueChanged<String> onCliChanged;
  final ValueChanged<String> onModelChanged;
  final ValueChanged<bool> onEnabledChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 720;
              final info = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(description, style: theme.textTheme.bodySmall),
                ],
              );
              final toggle = InlineSwitchFieldInternal(
                label: appText('启用', 'Enabled'),
                value: enabled,
                onChanged: onEnabledChanged,
              );
              if (cliOptions.length <= 1) {
                return info;
              }
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [info, const SizedBox(height: 12), toggle],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: info),
                  const SizedBox(width: 16),
                  Flexible(
                    child: Align(alignment: Alignment.topRight, child: toggle),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 720;
              final cliField = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('CLI', style: theme.textTheme.labelMedium),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<String>(
                    initialValue: cliOptions.contains(cliTool)
                        ? cliTool
                        : cliOptions.first,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    items: cliOptions
                        .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) onCliChanged(v);
                    },
                  ),
                ],
              );
              final modelField = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    appText('模型', 'Model'),
                    style: theme.textTheme.labelMedium,
                  ),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<String>(
                    initialValue: modelOptions.contains(model)
                        ? model
                        : modelOptions.first,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    items: modelOptions
                        .map(
                          (m) => DropdownMenuItem(
                            value: m,
                            child: Text(m, overflow: TextOverflow.ellipsis),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) onModelChanged(v);
                    },
                  ),
                ],
              );
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [cliField, const SizedBox(height: 12), modelField],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: cliField),
                  const SizedBox(width: 12),
                  Expanded(flex: 2, child: modelField),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// 工作流步骤展示
class WorkflowStepInternal extends StatelessWidget {
  const WorkflowStepInternal({
    super.key,
    required this.label,
    required this.emoji,
    required this.title,
    required this.desc,
  });

  final String label;
  final String emoji;
  final String title;
  final String desc;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.colorScheme.primaryContainer,
            ),
            child: Text(label, style: theme.textTheme.labelSmall),
          ),
          const SizedBox(width: 12),
          Text(emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.labelLarge),
                Text(desc, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum GatewayIntegrationSubTabInternal { gateway, llm, acp, skills }

enum LlmEndpointSlotInternal { aiGateway, ollamaLocal, ollamaCloud }

const List<LlmEndpointSlotInternal> llmEndpointSlotsInternal =
    <LlmEndpointSlotInternal>[
      LlmEndpointSlotInternal.aiGateway,
      LlmEndpointSlotInternal.ollamaLocal,
      LlmEndpointSlotInternal.ollamaCloud,
    ];

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
    final colorScheme = Theme.of(context).colorScheme;
    final (background, foreground) = switch (tone) {
      StatusChipToneInternal.ready => (
        colorScheme.primaryContainer,
        colorScheme.onPrimaryContainer,
      ),
      StatusChipToneInternal.idle => (
        colorScheme.surfaceContainerHighest,
        colorScheme.onSurfaceVariant,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(color: foreground),
      ),
    );
  }
}
