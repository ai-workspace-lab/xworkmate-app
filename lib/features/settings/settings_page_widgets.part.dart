part of 'settings_page.dart';

class _EditableField extends StatefulWidget {
  const _EditableField({
    required this.label,
    required this.value,
    required this.onSubmitted,
  });

  final String label;
  final String value;
  final ValueChanged<String> onSubmitted;

  @override
  State<_EditableField> createState() => _EditableFieldState();
}

class _EditableFieldState extends State<_EditableField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant _EditableField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value == _controller.text) {
      return;
    }
    _controller.value = _controller.value.copyWith(
      text: widget.value,
      selection: TextSelection.collapsed(offset: widget.value.length),
      composing: TextRange.empty,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        key: ValueKey('${widget.label}:${widget.value}'),
        controller: _controller,
        decoration: InputDecoration(labelText: widget.label),
        onChanged: widget.onSubmitted,
        onFieldSubmitted: widget.onSubmitted,
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
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

class _MountTargetCard extends StatelessWidget {
  const _MountTargetCard({required this.target});

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

class _InlineSwitchField extends StatelessWidget {
  const _InlineSwitchField({
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

class _AiGatewayFeedbackTheme {
  const _AiGatewayFeedbackTheme({
    required this.background,
    required this.border,
    required this.foreground,
  });

  final Color background;
  final Color border;
  final Color foreground;
}

class _SecretFieldUiState {
  const _SecretFieldUiState({
    this.showPlaintext = false,
    this.hasDraft = false,
    this.loading = false,
  });

  final bool showPlaintext;
  final bool hasDraft;
  final bool loading;

  _SecretFieldUiState copyWith({
    bool? showPlaintext,
    bool? hasDraft,
    bool? loading,
  }) {
    return _SecretFieldUiState(
      showPlaintext: showPlaintext ?? this.showPlaintext,
      hasDraft: hasDraft ?? this.hasDraft,
      loading: loading ?? this.loading,
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

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
class _AgentRoleCard extends StatelessWidget {
  const _AgentRoleCard({
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
              final toggle = _InlineSwitchField(
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
class _WorkflowStep extends StatelessWidget {
  const _WorkflowStep({
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

enum _GatewayIntegrationSubTab { gateway, llm, acp, skills }

enum _LlmEndpointSlot { aiGateway, ollamaLocal, ollamaCloud }

const List<_LlmEndpointSlot> _llmEndpointSlots = <_LlmEndpointSlot>[
  _LlmEndpointSlot.aiGateway,
  _LlmEndpointSlot.ollamaLocal,
  _LlmEndpointSlot.ollamaCloud,
];

enum _StatusChipTone { idle, ready }

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.tone});

  final String label;
  final _StatusChipTone tone;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final (background, foreground) = switch (tone) {
      _StatusChipTone.ready => (
        colorScheme.primaryContainer,
        colorScheme.onPrimaryContainer,
      ),
      _StatusChipTone.idle => (
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
