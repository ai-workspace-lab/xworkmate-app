part of 'web_assistant_page.dart';

class _ConversationWorkspace extends StatelessWidget {
  const _ConversationWorkspace({
    required this.controller,
    required this.scrollController,
    required this.inputController,
    required this.currentMessages,
    required this.connectionState,
    required this.thinkingLevel,
    required this.permissionLevel,
    required this.useMultiAgent,
    required this.attachments,
    required this.composerHeight,
    required this.onComposerHeightChanged,
    required this.onThinkingChanged,
    required this.onPermissionChanged,
    required this.onToggleMultiAgent,
    required this.onAddAttachment,
    required this.onRemoveAttachment,
    required this.onOpenSessionSettings,
    required this.onSubmit,
  });

  final AppController controller;
  final ScrollController scrollController;
  final TextEditingController inputController;
  final List<GatewayChatMessage> currentMessages;
  final AssistantThreadConnectionState connectionState;
  final String thinkingLevel;
  final AssistantPermissionLevel permissionLevel;
  final bool useMultiAgent;
  final List<_WebComposerAttachment> attachments;
  final double composerHeight;
  final ValueChanged<double> onComposerHeightChanged;
  final ValueChanged<String> onThinkingChanged;
  final ValueChanged<AssistantPermissionLevel> onPermissionChanged;
  final ValueChanged<bool> onToggleMultiAgent;
  final Future<void> Function() onAddAttachment;
  final ValueChanged<int> onRemoveAttachment;
  final Future<void> Function() onOpenSessionSettings;
  final Future<void> Function() onSubmit;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final palette = context.palette;
        final currentTarget = controller.assistantExecutionTarget;
        final connected = connectionState.ready;
        final maxComposerHeight = math.max(
          _webAssistantComposerMinHeight,
          constraints.maxHeight -
              _webAssistantConversationMinHeight -
              _webAssistantResizeHandleSize,
        );
        final resolvedComposerHeight = composerHeight.clamp(
          _webAssistantComposerMinHeight,
          maxComposerHeight,
        );

        return Column(
          children: [
            if (!connected)
              SurfaceCard(
                borderRadius: 10,
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        currentTarget == AssistantExecutionTarget.singleAgent
                            ? appText(
                                '当前线程未就绪。请检查 Single Agent 配置，或切换到可连接的 Gateway 目标。',
                                'This thread is not ready. Check Single Agent configuration, or switch to a connected gateway target.',
                              )
                            : appText(
                                '当前线程目标网关未连接。请先在 Settings 中 Test / Save / Apply。',
                                'The gateway target for this thread is offline. Use Test / Save / Apply in Settings first.',
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            if (!connected) const SizedBox(height: 8),
            Expanded(
              child: SurfaceCard(
                borderRadius: 10,
                padding: EdgeInsets.zero,
                tone: SurfaceCardTone.chrome,
                child: Column(
                  children: [
                    if (controller
                        .assistantImportedSkillsForSession(
                          controller.currentSessionKey,
                        )
                        .isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: controller
                                .assistantImportedSkillsForSession(
                                  controller.currentSessionKey,
                                )
                                .map((skill) {
                                  final selected = controller
                                      .assistantSelectedSkillKeysForSession(
                                        controller.currentSessionKey,
                                      )
                                      .contains(skill.key);
                                  return FilterChip(
                                    label: Text(skill.label),
                                    selected: selected,
                                    onSelected: (_) => controller
                                        .toggleAssistantSkillForSession(
                                          controller.currentSessionKey,
                                          skill.key,
                                        ),
                                  );
                                })
                                .toList(growable: false),
                          ),
                        ),
                      ),
                    Expanded(
                      child: currentMessages.isEmpty
                          ? _ConversationEmptyState(controller: controller)
                          : ListView.builder(
                              controller: scrollController,
                              padding: const EdgeInsets.all(16),
                              itemCount: currentMessages.length,
                              itemBuilder: (context, index) {
                                return _MessageBubble(
                                  message: currentMessages[index],
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(
              height: _webAssistantResizeHandleSize,
              child: PaneResizeHandle(
                axis: Axis.vertical,
                onDelta: (delta) {
                  onComposerHeightChanged(
                    (resolvedComposerHeight - delta)
                        .clamp(
                          _webAssistantComposerMinHeight,
                          maxComposerHeight,
                        )
                        .toDouble(),
                  );
                },
              ),
            ),
            SizedBox(
              height: resolvedComposerHeight,
              child: SurfaceCard(
                borderRadius: 10,
                tone: SurfaceCardTone.chrome,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (attachments.isNotEmpty) ...[
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (
                            var index = 0;
                            index < attachments.length;
                            index++
                          )
                            InputChip(
                              avatar: Icon(attachments[index].icon, size: 16),
                              label: Text(attachments[index].name),
                              onDeleted: () => onRemoveAttachment(index),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                    ],
                    Expanded(
                      child: TextField(
                        controller: inputController,
                        minLines: null,
                        maxLines: null,
                        expands: true,
                        decoration: InputDecoration(
                          hintText: appText(
                            '输入任务说明、补充上下文，XWorkmate 会沿用当前任务上下文持续处理。',
                            'Describe the task and add context. XWorkmate keeps working in the current task context.',
                          ),
                          alignLabelWithHint: true,
                        ),
                        textAlignVertical: TextAlignVertical.top,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        OutlinedButton.icon(
                          key: const Key('assistant-session-settings-button'),
                          onPressed: onOpenSessionSettings,
                          icon: const Icon(Icons.tune_rounded),
                          label: Text(appText('会话设置', 'Session settings')),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Checkbox(
                              value: useMultiAgent,
                              onChanged: (value) {
                                onToggleMultiAgent(value ?? false);
                              },
                            ),
                            Text(appText('Multi-Agent', 'Multi-Agent')),
                          ],
                        ),
                        Container(
                          decoration: BoxDecoration(
                            color: palette.surfacePrimary,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: palette.strokeSoft),
                          ),
                          child: IconButton(
                            key: const Key('assistant-attachment-menu-button'),
                            tooltip: appText('添加附件', 'Add attachment'),
                            onPressed: onAddAttachment,
                            icon: const Icon(Icons.attach_file_rounded),
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: connected ? onSubmit : null,
                          icon: controller.relayBusy || controller.acpBusy
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.arrow_upward_rounded),
                          label: Text(appText('发送', 'Send')),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      controller.lastAssistantError?.trim().isNotEmpty == true
                          ? controller.lastAssistantError!.trim()
                          : appText(
                              '附件仅支持手动选择，单次总量上限 10MB。',
                              'Attachments are explicit user picks only, with a 10MB total limit per send.',
                            ),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _AssistantSessionSettingsSheet extends StatefulWidget {
  const _AssistantSessionSettingsSheet({
    required this.controller,
    required this.thinkingLevel,
    required this.permissionLevel,
    required this.onThinkingChanged,
    required this.onPermissionChanged,
  });

  final AppController controller;
  final String thinkingLevel;
  final AssistantPermissionLevel permissionLevel;
  final ValueChanged<String> onThinkingChanged;
  final ValueChanged<AssistantPermissionLevel> onPermissionChanged;

  @override
  State<_AssistantSessionSettingsSheet> createState() =>
      _AssistantSessionSettingsSheetState();
}

class _AssistantSessionSettingsSheetState
    extends State<_AssistantSessionSettingsSheet> {
  late String _thinkingLevel = widget.thinkingLevel;
  late AssistantPermissionLevel _permissionLevel = widget.permissionLevel;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        final currentTarget = controller.assistantExecutionTarget;
        final modelChoices = controller.assistantModelChoices;
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              0,
              16,
              MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    appText('会话设置', 'Session settings'),
                    key: const Key('assistant-session-settings-sheet-title'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    appText(
                      '线程模式、渲染方式和执行参数统一放到底部对话框管理。',
                      'Manage thread mode, rendering, and execution parameters from this bottom sheet.',
                    ),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SessionSettingField(
                    label: appText('执行目标', 'Execution target'),
                    child: _HeaderDropdownShell(
                      child: _CompactDropdown<AssistantExecutionTarget>(
                        key: const Key('assistant-target-button'),
                        value: currentTarget,
                        items: controller
                            .featuresFor(UiFeaturePlatform.web)
                            .availableExecutionTargets,
                        labelBuilder: _targetLabel,
                        onChanged: (value) {
                          if (value != null) {
                            controller.setAssistantExecutionTarget(value);
                          }
                        },
                      ),
                    ),
                  ),
                  if (currentTarget == AssistantExecutionTarget.singleAgent)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: _SessionSettingField(
                        label: appText('Provider', 'Provider'),
                        child: _HeaderDropdownShell(
                          child: _CompactDropdown<SingleAgentProvider>(
                            key: const Key(
                              'assistant-single-agent-provider-button',
                            ),
                            value: controller.currentSingleAgentProvider,
                            items: controller.singleAgentProviderOptions,
                            labelBuilder: (item) => item.label,
                            onChanged: (value) {
                              if (value != null) {
                                controller.setSingleAgentProvider(value);
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                  if (modelChoices.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: _SessionSettingField(
                        label: appText('模型', 'Model'),
                        child: _HeaderDropdownShell(
                          child: _CompactDropdown<String>(
                            key: const Key('assistant-model-button'),
                            value: controller.resolvedAssistantModel,
                            items: modelChoices,
                            labelBuilder: (item) => item,
                            onChanged: (value) {
                              if (value != null) {
                                controller.selectAssistantModel(value);
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _SessionSettingField(
                      label: appText('消息视图', 'Message view'),
                      child: _HeaderDropdownShell(
                        child: _CompactDropdown<AssistantMessageViewMode>(
                          key: const Key('assistant-message-view-mode-button'),
                          value: controller.currentAssistantMessageViewMode,
                          items: AssistantMessageViewMode.values,
                          labelBuilder: (item) => item.label,
                          onChanged: (value) {
                            if (value != null) {
                              controller.setAssistantMessageViewMode(value);
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _SessionSettingField(
                      label: appText('思考强度', 'Thinking level'),
                      child: _HeaderDropdownShell(
                        child: _CompactDropdown<String>(
                          key: const Key('assistant-thinking-button'),
                          value: _thinkingLevel,
                          items: const <String>['low', 'medium', 'high'],
                          labelBuilder: _thinkingLabel,
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _thinkingLevel = value);
                              widget.onThinkingChanged(value);
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _SessionSettingField(
                      label: appText('权限', 'Permissions'),
                      child: _HeaderDropdownShell(
                        child: _CompactDropdown<AssistantPermissionLevel>(
                          key: const Key('assistant-permission-button'),
                          value: _permissionLevel,
                          items: AssistantPermissionLevel.values,
                          labelBuilder: (item) => item.label,
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _permissionLevel = value);
                              widget.onPermissionChanged(value);
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ConversationEmptyState extends StatelessWidget {
  const _ConversationEmptyState({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: palette.surfaceSecondary,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  Icons.chat_bubble_outline_rounded,
                  color: palette.accent,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                appText('开始这个任务线程', 'Start this task thread'),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                appText(
                  '保持当前线程模式与上下文，在底部 composer 中直接输入需求即可。',
                  'Keep the current thread mode and context, then start from the composer below.',
                ),
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: palette.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final GatewayChatMessage message;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final assistant = message.role.trim().toLowerCase() == 'assistant';
    final color = message.error
        ? palette.danger.withValues(alpha: 0.14)
        : assistant
        ? palette.surfacePrimary
        : palette.accentMuted;

    return Align(
      alignment: assistant ? Alignment.centerLeft : Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: palette.strokeSoft),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    assistant ? 'Assistant' : 'You',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(message.text),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AssistantSideTabButton extends StatefulWidget {
  const _AssistantSideTabButton({
    super.key,
    required this.icon,
    required this.selected,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final bool selected;
  final String tooltip;
  final VoidCallback onTap;

  @override
  State<_AssistantSideTabButton> createState() =>
      _AssistantSideTabButtonState();
}

class _AssistantSideTabButtonState extends State<_AssistantSideTabButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: widget.onTap,
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                gradient: widget.selected || _hovered
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          palette.chromeHighlight.withValues(
                            alpha: widget.selected ? 0.96 : 0.84,
                          ),
                          palette.chromeSurfacePressed,
                        ],
                      )
                    : null,
                color: widget.selected || _hovered ? null : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: widget.selected
                      ? palette.accent.withValues(alpha: 0.28)
                      : Colors.transparent,
                ),
              ),
              child: Icon(
                widget.icon,
                size: 18,
                color: widget.selected ? palette.accent : palette.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
