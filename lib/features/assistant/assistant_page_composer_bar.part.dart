part of 'assistant_page.dart';

class _ComposerBar extends StatefulWidget {
  const _ComposerBar({
    required this.controller,
    required this.inputController,
    required this.focusNode,
    required this.thinkingLabel,
    required this.showModelControl,
    required this.modelLabel,
    required this.modelOptions,
    required this.attachments,
    required this.availableSkills,
    required this.selectedSkillKeys,
    required this.onRemoveAttachment,
    required this.onToggleSkill,
    required this.onThinkingChanged,
    required this.onModelChanged,
    required this.onOpenGateway,
    required this.onOpenAiGatewaySettings,
    required this.onReconnectGateway,
    required this.onPickAttachments,
    required this.onAddAttachment,
    required this.onPasteImageAttachment,
    required this.onContentHeightChanged,
    required this.onInputHeightChanged,
    required this.onSend,
  });

  final AppController controller;
  final TextEditingController inputController;
  final FocusNode focusNode;
  final String thinkingLabel;
  final bool showModelControl;
  final String modelLabel;
  final List<String> modelOptions;
  final List<_ComposerAttachment> attachments;
  final List<_ComposerSkillOption> availableSkills;
  final List<String> selectedSkillKeys;
  final ValueChanged<_ComposerAttachment> onRemoveAttachment;
  final ValueChanged<String> onToggleSkill;
  final ValueChanged<String> onThinkingChanged;
  final Future<void> Function(String modelId) onModelChanged;
  final VoidCallback onOpenGateway;
  final VoidCallback onOpenAiGatewaySettings;
  final Future<void> Function() onReconnectGateway;
  final VoidCallback onPickAttachments;
  final ValueChanged<_ComposerAttachment> onAddAttachment;
  final AssistantClipboardImageReader onPasteImageAttachment;
  final ValueChanged<double> onContentHeightChanged;
  final ValueChanged<double> onInputHeightChanged;
  final Future<void> Function() onSend;

  @override
  State<_ComposerBar> createState() => _ComposerBarState();
}

class _ComposerBarState extends State<_ComposerBar> {
  static const double _minInputHeight = 68;
  static const double _defaultInputHeight =
      _assistantComposerDefaultInputHeight;
  static const double _maxInputHeight = 220;
  static const Map<ShortcutActivator, Intent> _pasteShortcuts =
      <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.keyV, meta: true):
            AssistantPasteIntent(),
        SingleActivator(LogicalKeyboardKey.keyV, control: true):
            AssistantPasteIntent(),
      };

  late double _inputHeight;
  final GlobalKey _skillPickerTargetKey = GlobalKey(
    debugLabel: 'assistant-skill-picker-target',
  );
  final GlobalKey _contentKey = GlobalKey(debugLabel: 'assistant-composer-bar');
  final LayerLink _skillPickerLayerLink = LayerLink();
  final OverlayPortalController _skillPickerPortalController =
      OverlayPortalController(debugLabel: 'assistant-skill-picker');
  late final TextEditingController _skillPickerSearchController;
  late final FocusNode _skillPickerSearchFocusNode;
  bool _handlingPasteShortcut = false;
  bool _refreshingSingleAgentSkills = false;
  String _skillPickerQuery = '';

  @override
  void initState() {
    super.initState();
    _inputHeight = _defaultInputHeight;
    _skillPickerSearchController = TextEditingController();
    _skillPickerSearchFocusNode = FocusNode();
    widget.controller.addListener(_handleControllerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      widget.onInputHeightChanged(_inputHeight);
      _reportContentHeight();
    });
  }

  @override
  void didUpdateWidget(covariant _ComposerBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
    }
    _reportContentHeight();
  }

  Future<void> _refreshSingleAgentSkills() async {
    if (_refreshingSingleAgentSkills) {
      return;
    }
    setState(() {
      _refreshingSingleAgentSkills = true;
    });
    try {
      await widget.controller.refreshSingleAgentLocalSkillsForSession(
        widget.controller.currentSessionKey,
      );
    } finally {
      if (mounted) {
        setState(() {
          _refreshingSingleAgentSkills = false;
        });
      }
    }
  }

  List<_ComposerSkillOption> _activeSkillOptions() {
    if (widget.controller.isSingleAgentMode) {
      return widget.controller
          .assistantImportedSkillsForSession(
            widget.controller.currentSessionKey,
          )
          .map(_skillOptionFromThreadSkill)
          .toList(growable: false);
    }
    return widget.availableSkills;
  }

  List<_ComposerSkillOption> _filteredSkillOptions() {
    final normalizedQuery = _skillPickerQuery.trim().toLowerCase();
    if (normalizedQuery.isEmpty) {
      return _activeSkillOptions();
    }
    return _activeSkillOptions()
        .where((skill) {
          final haystack =
              '${skill.label}\n${skill.description}\n${skill.sourceLabel}'
                  .toLowerCase();
          return haystack.contains(normalizedQuery);
        })
        .toList(growable: false);
  }

  Widget _buildSkillPickerOverlay(BuildContext context) =>
      _buildSkillPickerOverlayFor(this, context);

  void _hideSkillPicker() {
    if (_skillPickerPortalController.isShowing) {
      _skillPickerPortalController.hide();
    }
    if (_skillPickerQuery.isNotEmpty ||
        _skillPickerSearchController.text.isNotEmpty) {
      setState(_resetSkillPickerSearch);
    }
  }

  void _toggleSkillPicker() {
    if (_skillPickerPortalController.isShowing) {
      _hideSkillPicker();
      return;
    }
    setState(_resetSkillPickerSearch);
    _skillPickerPortalController.show();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_skillPickerPortalController.isShowing) {
        return;
      }
      _skillPickerSearchFocusNode.requestFocus();
    });
    if (widget.controller.isSingleAgentMode) {
      unawaited(_refreshSingleAgentSkills());
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    if (_skillPickerPortalController.isShowing) {
      _skillPickerPortalController.hide();
    }
    _skillPickerSearchController.dispose();
    _skillPickerSearchFocusNode.dispose();
    super.dispose();
  }

  void _handleControllerChanged() {
    if (!mounted || !_skillPickerPortalController.isShowing) {
      return;
    }
    setState(() {});
  }

  void _reportContentHeight() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final height = _contentKey.currentContext?.size?.height;
      if (height == null || !height.isFinite || height <= 0) {
        return;
      }
      widget.onContentHeightChanged(height);
    });
  }

  void _resizeInput(double delta) {
    final nextHeight = (_inputHeight + delta).clamp(
      _minInputHeight,
      _maxInputHeight,
    );
    if (nextHeight == _inputHeight) {
      return;
    }
    setState(() {
      _inputHeight = nextHeight;
    });
    widget.onInputHeightChanged(_inputHeight);
  }

  Future<void> _handlePasteShortcut() async {
    if (_handlingPasteShortcut) {
      return;
    }
    _handlingPasteShortcut = true;
    try {
      if (widget.controller
          .featuresFor(resolveUiFeaturePlatformFromContext(context))
          .supportsFileAttachments) {
        final imageFile = await widget.onPasteImageAttachment();
        if (!mounted) {
          return;
        }
        if (imageFile != null) {
          widget.onAddAttachment(_ComposerAttachment.fromXFile(imageFile));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                appText(
                  '已从剪贴板添加图片附件',
                  'Added image from clipboard as attachment',
                ),
              ),
            ),
          );
          return;
        }
      }

      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      final text = clipboardData?.text;
      if (!mounted || text == null || text.isEmpty) {
        return;
      }
      _insertTextAtSelection(text);
    } finally {
      _handlingPasteShortcut = false;
    }
  }

  void _insertTextAtSelection(String text) {
    final currentValue = widget.inputController.value;
    final selection = currentValue.selection;
    final textLength = currentValue.text.length;
    final start = selection.isValid
        ? math.min(selection.start, selection.end).clamp(0, textLength)
        : textLength;
    final end = selection.isValid
        ? math.max(selection.start, selection.end).clamp(0, textLength)
        : textLength;
    final updatedText = currentValue.text.replaceRange(start, end, text);
    final cursorOffset = start + text.length;
    widget.inputController.value = currentValue.copyWith(
      text: updatedText,
      selection: TextSelection.collapsed(offset: cursorOffset),
      composing: TextRange.empty,
    );
  }

  void _resetSkillPickerSearch() {
    _skillPickerSearchController.clear();
    _skillPickerQuery = '';
  }

  void _setSkillPickerQuery(String value) {
    setState(() {
      _skillPickerQuery = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final controller = widget.controller;
    final uiFeatures = controller.featuresFor(
      resolveUiFeaturePlatformFromContext(context),
    );
    final connectionState = controller.currentAssistantConnectionState;
    final singleAgent = connectionState.isSingleAgent;
    final connected = connectionState.connected;
    final reconnectAvailable = controller.canQuickConnectGateway;
    final connecting = connectionState.connecting;
    final executionTarget = controller.assistantExecutionTarget;
    final permissionLevel = controller.assistantPermissionLevel;
    final selectedSkills = widget.availableSkills
        .where((skill) => widget.selectedSkillKeys.contains(skill.key))
        .toList(growable: false);
    final submitLabel = connected
        ? appText('提交', 'Submit')
        : singleAgent
        ? appText('提交', 'Submit')
        : connecting
        ? appText('连接中…', 'Connecting…')
        : reconnectAvailable
        ? appText('重连', 'Reconnect')
        : appText('连接', 'Connect');

    _reportContentHeight();

    return Padding(
      key: _contentKey,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (uiFeatures.supportsFileAttachments) ...[
                PopupMenuButton<String>(
                  key: const Key('assistant-attachment-menu-button'),
                  tooltip: appText('添加文件等', 'Add files'),
                  offset: const Offset(0, 48),
                  onSelected: (value) {
                    switch (value) {
                      case 'attach':
                        widget.onPickAttachments();
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem<String>(
                      value: 'attach',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.attach_file_rounded),
                        title: Text('添加照片和文件'),
                      ),
                    ),
                  ],
                  child: const _ComposerIconButton(icon: Icons.add_rounded),
                ),
                const SizedBox(width: 6),
              ],
              PopupMenuButton<AssistantExecutionTarget>(
                key: const Key('assistant-execution-target-button'),
                tooltip: appText('任务对话模式', 'Task Dialog Mode'),
                onSelected: (value) {
                  controller.setAssistantExecutionTarget(value);
                },
                itemBuilder: (context) => uiFeatures.availableExecutionTargets
                    .map(
                      (value) => PopupMenuItem<AssistantExecutionTarget>(
                        value: value,
                        child: Row(
                          children: [
                            Icon(value.icon, size: 18),
                            const SizedBox(width: 10),
                            Expanded(child: Text(value.label)),
                            if (value == executionTarget)
                              const Icon(Icons.check_rounded, size: 18),
                          ],
                        ),
                      ),
                    )
                    .toList(),
                child: _ComposerToolbarChip(
                  icon: executionTarget.icon,
                  tooltip: _executionTargetTooltip(executionTarget),
                  showChevron: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              if (singleAgent) ...[
                PopupMenuButton<SingleAgentProvider>(
                  key: const Key('assistant-single-agent-provider-button'),
                  tooltip: appText('单机智能体执行器', 'Single Agent Provider'),
                  onSelected: (value) {
                    unawaited(controller.setSingleAgentProvider(value));
                  },
                  itemBuilder: (context) => controller
                      .singleAgentProviderOptions
                      .map(
                        (value) => PopupMenuItem<SingleAgentProvider>(
                          value: value,
                          child: Row(
                            children: [
                              _SingleAgentProviderBadge(provider: value),
                              const SizedBox(width: 10),
                              Expanded(child: Text(value.label)),
                              if (value ==
                                  controller.currentSingleAgentProvider)
                                const Icon(Icons.check_rounded, size: 18),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                  child: _ComposerToolbarChip(
                    leading: _SingleAgentProviderBadge(
                      provider: controller.currentSingleAgentProvider,
                    ),
                    tooltip: _singleAgentProviderTooltip(
                      controller.currentSingleAgentProvider,
                    ),
                    showChevron: true,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              if (widget.showModelControl) ...[
                widget.modelOptions.isEmpty
                    ? _ComposerToolbarChip(
                        key: const Key('assistant-model-button'),
                        icon: Icons.bolt_rounded,
                        tooltip: _modelTooltip(widget.modelLabel),
                        showChevron: false,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                      )
                    : PopupMenuButton<String>(
                        key: const Key('assistant-model-button'),
                        tooltip: appText('模型', 'Model'),
                        onSelected: widget.onModelChanged,
                        itemBuilder: (context) => widget.modelOptions
                            .map(
                              (value) => PopupMenuItem<String>(
                                value: value,
                                child: Row(
                                  children: [
                                    Expanded(child: Text(value)),
                                    if (value == widget.modelLabel)
                                      const Icon(Icons.check_rounded, size: 18),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                        child: _ComposerToolbarChip(
                          icon: Icons.bolt_rounded,
                          tooltip: _modelTooltip(widget.modelLabel),
                          showChevron: true,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                        ),
                      ),
                const SizedBox(width: 4),
              ],
              if (uiFeatures.supportsMultiAgent) ...[
                Tooltip(
                  message: appText(
                    '多 Agent 协作模式（Architect 调度/文档 → Lead Engineer 主程 → Worker/Review）',
                    'Multi-Agent Collaboration Mode (Architect docs/scheduler -> Lead Engineer -> Worker/Review)',
                  ),
                  child: AnimatedBuilder(
                    animation: controller.multiAgentOrchestrator,
                    builder: (context, _) {
                      final collab = controller.multiAgentOrchestrator;
                      final enabled = collab.config.enabled;
                      return IconButton(
                        key: const Key('assistant-collaboration-toggle'),
                        icon: Icon(
                          enabled
                              ? Icons.auto_awesome
                              : Icons.auto_awesome_outlined,
                          size: 20,
                          color: enabled ? Colors.orange : null,
                        ),
                        onPressed:
                            collab.isRunning ||
                                controller.isMultiAgentRunPending
                            ? null
                            : () => unawaited(
                                controller.saveMultiAgentConfig(
                                  collab.config.copyWith(enabled: !enabled),
                                ),
                              ),
                        splashRadius: 18,
                      );
                    },
                  ),
                ),
                AnimatedBuilder(
                  animation: controller.multiAgentOrchestrator,
                  builder: (context, _) {
                    final collab = controller.multiAgentOrchestrator;
                    if (!collab.config.enabled) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: _ComposerToolbarChip(
                        icon: Icons.hub_rounded,
                        tooltip: collab.config.usesAris
                            ? appText('多智能体模式: ARIS', 'Multi-agent mode: ARIS')
                            : appText('多智能体模式: 原生', 'Multi-agent mode: Native'),
                        showChevron: false,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          if (widget.attachments.isNotEmpty) ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: widget.attachments
                  .map(
                    (attachment) => InputChip(
                      avatar: Icon(attachment.icon, size: 16),
                      label: Text(attachment.name),
                      onDeleted: () => widget.onRemoveAttachment(attachment),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 6),
          ],
          SizedBox(
            key: const Key('assistant-composer-input-area'),
            height: _inputHeight,
            child: Shortcuts(
              shortcuts: _pasteShortcuts,
              child: Actions(
                actions: <Type, Action<Intent>>{
                  AssistantPasteIntent: CallbackAction<AssistantPasteIntent>(
                    onInvoke: (_) {
                      unawaited(_handlePasteShortcut());
                      return null;
                    },
                  ),
                },
                child: TextField(
                  controller: widget.inputController,
                  focusNode: widget.focusNode,
                  autofocus: true,
                  expands: true,
                  minLines: null,
                  maxLines: null,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: InputDecoration(
                    isCollapsed: true,
                    filled: true,
                    fillColor: palette.surfacePrimary,
                    contentPadding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: palette.strokeSoft),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: palette.accent.withValues(alpha: 0.24),
                      ),
                    ),
                    hintText: appText(
                      '输入需求、补充上下文，XWorkmate 会沿用当前任务上下文持续处理。',
                      'Describe the task or add context. XWorkmate keeps the current task context.',
                    ),
                  ),
                  onSubmitted: (_) => widget.onSend(),
                ),
              ),
            ),
          ),
          _ComposerResizeHandle(
            key: const Key('assistant-composer-resize-handle'),
            onDelta: _resizeInput,
          ),
          if (selectedSkills.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: selectedSkills
                  .map(
                    (skill) => _ComposerSelectedSkillChip(
                      key: ValueKey<String>(
                        'assistant-selected-skill-${skill.key}',
                      ),
                      option: skill,
                      onDeleted: () => widget.onToggleSkill(skill.key),
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CompositedTransformTarget(
                        key: _skillPickerTargetKey,
                        link: _skillPickerLayerLink,
                        child: OverlayPortal(
                          controller: _skillPickerPortalController,
                          overlayChildBuilder: _buildSkillPickerOverlay,
                          child: InkWell(
                            key: const Key('assistant-skill-picker-button'),
                            borderRadius: BorderRadius.circular(AppRadius.chip),
                            onTap: _toggleSkillPicker,
                            child: _ComposerToolbarChip(
                              icon: Icons.auto_awesome_rounded,
                              tooltip: _skillsTooltip(selectedSkills.length),
                              showChevron: true,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      PopupMenuButton<AssistantPermissionLevel>(
                        key: const Key('assistant-permission-button'),
                        tooltip: appText('权限', 'Permissions'),
                        onSelected: (value) {
                          controller.setAssistantPermissionLevel(value);
                        },
                        itemBuilder: (context) => AssistantPermissionLevel
                            .values
                            .map(
                              (value) =>
                                  PopupMenuItem<AssistantPermissionLevel>(
                                    value: value,
                                    child: Row(
                                      children: [
                                        Icon(value.icon, size: 18),
                                        const SizedBox(width: 10),
                                        Expanded(child: Text(value.label)),
                                        if (value == permissionLevel)
                                          const Icon(
                                            Icons.check_rounded,
                                            size: 18,
                                          ),
                                      ],
                                    ),
                                  ),
                            )
                            .toList(),
                        child: _ComposerToolbarChip(
                          icon: permissionLevel.icon,
                          tooltip: _permissionTooltip(permissionLevel),
                          showChevron: true,
                        ),
                      ),
                      const SizedBox(width: 6),
                      PopupMenuButton<String>(
                        key: const Key('assistant-thinking-button'),
                        tooltip: appText('推理强度', 'Reasoning'),
                        onSelected: widget.onThinkingChanged,
                        itemBuilder: (context) =>
                            const <String>['low', 'medium', 'high', 'max']
                                .map(
                                  (value) => PopupMenuItem<String>(
                                    value: value,
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            _assistantThinkingLabel(value),
                                          ),
                                        ),
                                        if (value == widget.thinkingLabel)
                                          const Icon(
                                            Icons.check_rounded,
                                            size: 18,
                                          ),
                                      ],
                                    ),
                                  ),
                                )
                                .toList(),
                        child: _ComposerToolbarChip(
                          icon: Icons.psychology_alt_outlined,
                          tooltip: _thinkingTooltip(widget.thinkingLabel),
                          showChevron: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: submitLabel,
                child: FilledButton(
                  key: const Key('assistant-submit-button'),
                  onPressed: connecting
                      ? null
                      : connected
                      ? widget.onSend
                      : singleAgent
                      ? widget.onSend
                      : reconnectAvailable
                      ? () async {
                          await widget.onReconnectGateway();
                        }
                      : widget.onOpenGateway,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    minimumSize: const Size(64, 28),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        connected
                            ? Icons.arrow_upward_rounded
                            : singleAgent
                            ? Icons.arrow_upward_rounded
                            : reconnectAvailable
                            ? Icons.refresh_rounded
                            : Icons.link_rounded,
                        size: 18,
                      ),
                      const SizedBox(width: 4),
                      Text(submitLabel),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
