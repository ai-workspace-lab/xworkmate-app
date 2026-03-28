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
  static const double _skillPickerPreferredMaxHeight = 460;
  static const double _skillPickerMinHeight = 220;
  static const double _skillPickerVerticalGap = 8;
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

  Widget _buildSkillPickerOverlay(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final targetBox =
        _skillPickerTargetKey.currentContext?.findRenderObject() as RenderBox?;
    final targetOrigin = targetBox?.localToGlobal(Offset.zero);
    final targetSize = targetBox?.size;
    final availableBelow = targetOrigin == null || targetSize == null
        ? _skillPickerPreferredMaxHeight
        : mediaQuery.size.height -
              mediaQuery.padding.bottom -
              (targetOrigin.dy + targetSize.height) -
              _skillPickerVerticalGap;
    final availableAbove = targetOrigin == null
        ? _skillPickerPreferredMaxHeight
        : targetOrigin.dy - mediaQuery.padding.top - _skillPickerVerticalGap;
    final openUpward =
        availableBelow < _skillPickerMinHeight &&
        availableAbove > availableBelow;
    final constrainedHeight = math.max(
      _skillPickerMinHeight,
      openUpward ? availableAbove : availableBelow,
    );
    final maxHeight = math.min(
      _skillPickerPreferredMaxHeight,
      constrainedHeight,
    );
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _hideSkillPicker,
            child: const SizedBox.expand(),
          ),
        ),
        CompositedTransformFollower(
          link: _skillPickerLayerLink,
          showWhenUnlinked: false,
          targetAnchor: openUpward ? Alignment.topLeft : Alignment.bottomLeft,
          followerAnchor: openUpward ? Alignment.bottomLeft : Alignment.topLeft,
          offset: Offset(0, openUpward ? -_skillPickerVerticalGap : 8),
          child: _SkillPickerPopover(
            maxHeight: maxHeight,
            searchController: _skillPickerSearchController,
            searchFocusNode: _skillPickerSearchFocusNode,
            selectedSkillKeys: widget.selectedSkillKeys,
            filteredSkills: _filteredSkillOptions(),
            isLoading: _refreshingSingleAgentSkills,
            hasQuery: _skillPickerQuery.trim().isNotEmpty,
            onQueryChanged: (value) {
              setState(() {
                _skillPickerQuery = value;
              });
            },
            onToggleSkill: (skillKey) => widget.onToggleSkill(skillKey),
          ),
        ),
      ],
    );
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
    final singleAgentNeedsAiGateway =
        controller.currentSingleAgentNeedsAiGatewayConfiguration;
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

class _ComposerIconButton extends StatefulWidget {
  const _ComposerIconButton({required this.icon});

  final IconData icon;

  @override
  State<_ComposerIconButton> createState() => _ComposerIconButtonState();
}

class _ComposerResizeHandle extends StatefulWidget {
  const _ComposerResizeHandle({super.key, required this.onDelta});

  final ValueChanged<double> onDelta;

  @override
  State<_ComposerResizeHandle> createState() => _ComposerResizeHandleState();
}

class _ComposerResizeHandleState extends State<_ComposerResizeHandle> {
  bool _hovered = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final highlight = _hovered || _dragging;

    return MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragStart: (_) => setState(() => _dragging = true),
        onVerticalDragEnd: (_) => setState(() => _dragging = false),
        onVerticalDragCancel: () => setState(() => _dragging = false),
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

class _ComposerIconButtonState extends State<_ComposerIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: _hovered ? palette.surfaceSecondary : palette.surfacePrimary,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: palette.strokeSoft),
        ),
        child: Icon(widget.icon, size: 18, color: palette.textMuted),
      ),
    );
  }
}

class _ComposerToolbarChip extends StatefulWidget {
  const _ComposerToolbarChip({
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
  State<_ComposerToolbarChip> createState() => _ComposerToolbarChipState();
}

class _ComposerToolbarChipState extends State<_ComposerToolbarChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Container(
          padding: widget.padding,
          decoration: BoxDecoration(
            color: _hovered ? palette.surfaceSecondary : palette.surfacePrimary,
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
      ),
    );
  }
}

extension on AssistantExecutionTarget {
  IconData get icon => switch (this) {
    AssistantExecutionTarget.singleAgent => Icons.hub_outlined,
    AssistantExecutionTarget.local => Icons.computer_outlined,
    AssistantExecutionTarget.remote => Icons.cloud_outlined,
  };
}

extension on AssistantPermissionLevel {
  IconData get icon => switch (this) {
    AssistantPermissionLevel.defaultAccess => Icons.verified_user_outlined,
    AssistantPermissionLevel.fullAccess => Icons.error_outline_rounded,
  };
}

class _SingleAgentProviderBadge extends StatelessWidget {
  const _SingleAgentProviderBadge({required this.provider});

  final SingleAgentProvider provider;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final candidate = provider.badge.trim().isEmpty
        ? provider.label
        : provider.badge;
    final display = candidate.length <= 2
        ? candidate
        : candidate.substring(0, 2);
    final isAuto = provider == SingleAgentProvider.auto;
    return Container(
      width: 18,
      height: 18,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isAuto
            ? palette.accent.withValues(alpha: 0.16)
            : palette.surfaceSecondary,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isAuto
              ? palette.accent.withValues(alpha: 0.4)
              : palette.strokeSoft,
        ),
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

String _executionTargetTooltip(AssistantExecutionTarget target) =>
    appText('任务对话模式: ${target.label}', 'Task dialog mode: ${target.label}');

String _singleAgentProviderTooltip(SingleAgentProvider provider) => appText(
  '单机智能体执行器: ${provider.label}',
  'Single-agent provider: ${provider.label}',
);

String _modelTooltip(String modelLabel) =>
    appText('模型: $modelLabel', 'Model: $modelLabel');

String _skillsTooltip(int selectedCount) => selectedCount <= 0
    ? appText('技能', 'Skills')
    : appText('技能: 已选 $selectedCount 个', 'Skills: $selectedCount selected');

String _permissionTooltip(AssistantPermissionLevel level) =>
    appText('权限: ${level.label}', 'Permissions: ${level.label}');

String _thinkingTooltip(String level) => appText(
  '推理强度: ${_assistantThinkingLabel(level)}',
  'Reasoning: ${_assistantThinkingLabel(level)}',
);

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.label,
    required this.text,
    required this.alignRight,
    required this.tone,
    required this.messageViewMode,
  });

  final String label;
  final String text;
  final bool alignRight;
  final _BubbleTone tone;
  final AssistantMessageViewMode messageViewMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    final showLabel = !(alignRight && label == appText('你', 'You'));
    final backgroundColor = switch (tone) {
      _BubbleTone.user => palette.surfaceSecondary,
      _BubbleTone.agent => palette.surfaceTertiary.withValues(alpha: 0.78),
      _BubbleTone.assistant => palette.surfacePrimary,
    };
    final labelColor = switch (tone) {
      _BubbleTone.user => palette.textSecondary,
      _BubbleTone.agent => palette.success,
      _BubbleTone.assistant => palette.textMuted,
    };

    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: palette.strokeSoft),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showLabel) ...[
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: labelColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
              ],
              _MessageBubbleBody(
                text: text.isEmpty ? appText('暂无内容。', 'No content yet.') : text,
                renderMarkdown:
                    messageViewMode == AssistantMessageViewMode.rendered &&
                    tone != _BubbleTone.user,
                compactUserMetadata: tone == _BubbleTone.user,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageBubbleBody extends StatefulWidget {
  const _MessageBubbleBody({
    required this.text,
    required this.renderMarkdown,
    required this.compactUserMetadata,
  });

  final String text;
  final bool renderMarkdown;
  final bool compactUserMetadata;

  @override
  State<_MessageBubbleBody> createState() => _MessageBubbleBodyState();
}

class _MessageBubbleBodyState extends State<_MessageBubbleBody> {
  bool _attachmentsExpanded = false;
  bool _executionContextExpanded = false;
  bool _hovered = false;

  @override
  void didUpdateWidget(covariant _MessageBubbleBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _attachmentsExpanded = false;
      _executionContextExpanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    final messageBodyStyle = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurface,
      height: 1.5,
    );
    if (!widget.renderMarkdown) {
      final parsed = _PromptDebugSnapshot.fromMessage(widget.text);
      final canCompactMetadata =
          widget.compactUserMetadata &&
          (parsed.attachmentsBlock != null ||
              parsed.executionContextBlock != null);
      if (!canCompactMetadata) {
        return SelectableText(widget.text, style: messageBodyStyle);
      }

      final bodyText = parsed.bodyText.trim().isEmpty
          ? appText('暂无内容。', 'No content yet.')
          : parsed.bodyText;
      final showAttachments =
          _attachmentsExpanded && parsed.attachmentsBlock != null;
      final showExecutionContext =
          _executionContextExpanded && parsed.executionContextBlock != null;
      final content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(bodyText, style: messageBodyStyle),
          if (_hovered || showAttachments || showExecutionContext) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                if (parsed.attachmentsBlock != null)
                  _MessageMetaToggleButton(
                    key: const Key('assistant-user-meta-attachments-toggle'),
                    icon: Icons.attach_file_rounded,
                    expanded: _attachmentsExpanded,
                    tooltip: _attachmentsExpanded
                        ? appText('折叠附件信息', 'Collapse attached files')
                        : appText('展开附件信息', 'Expand attached files'),
                    onTap: () {
                      setState(() {
                        _attachmentsExpanded = !_attachmentsExpanded;
                      });
                    },
                  ),
                if (parsed.executionContextBlock != null)
                  _MessageMetaToggleButton(
                    key: const Key('assistant-user-meta-context-toggle'),
                    icon: Icons.tune_rounded,
                    expanded: _executionContextExpanded,
                    tooltip: _executionContextExpanded
                        ? appText('折叠执行上下文', 'Collapse execution context')
                        : appText('展开执行上下文', 'Expand execution context'),
                    onTap: () {
                      setState(() {
                        _executionContextExpanded = !_executionContextExpanded;
                      });
                    },
                  ),
              ],
            ),
          ],
          if (showAttachments) ...[
            const SizedBox(height: 6),
            _MessageMetaBlock(
              key: const Key('assistant-user-meta-attachments-block'),
              content: parsed.attachmentsBlock!,
            ),
          ],
          if (showExecutionContext) ...[
            const SizedBox(height: 6),
            _MessageMetaBlock(
              key: const Key('assistant-user-meta-context-block'),
              content: parsed.executionContextBlock!,
            ),
          ],
        ],
      );

      return MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: content,
      );
    }

    final styleSheet = MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: messageBodyStyle?.copyWith(height: 1.55),
      h1: theme.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w600,
        color: palette.textPrimary,
      ),
      h2: theme.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        color: palette.textPrimary,
      ),
      h3: theme.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w600,
        color: palette.textPrimary,
      ),
      code: theme.textTheme.bodyMedium?.copyWith(
        fontFamily: 'Menlo',
        height: 1.4,
      ),
      codeblockDecoration: BoxDecoration(
        color: context.palette.surfaceSecondary,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.palette.strokeSoft),
      ),
      blockquoteDecoration: BoxDecoration(
        color: context.palette.surfaceSecondary.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.palette.strokeSoft),
      ),
      blockquotePadding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 8,
      ),
      tableBorder: TableBorder.all(color: context.palette.strokeSoft),
      tableHead: theme.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w700,
      ),
    );

    return MarkdownBody(
      data: widget.text,
      selectable: true,
      styleSheet: styleSheet,
      extensionSet: md.ExtensionSet.gitHubWeb,
      sizedImageBuilder: (config) => SelectableText(
        config.alt?.trim().isNotEmpty == true
            ? '![${config.alt!.trim()}](${config.uri.toString()})'
            : config.uri.toString(),
        style: theme.textTheme.bodyMedium?.copyWith(
          color: context.palette.textSecondary,
          height: 1.4,
        ),
      ),
      onTapLink: (text, href, title) {},
    );
  }
}

class _PromptDebugSnapshot {
  const _PromptDebugSnapshot({
    required this.bodyText,
    this.attachmentsBlock,
    this.executionContextBlock,
  });

  final String bodyText;
  final String? attachmentsBlock;
  final String? executionContextBlock;

  static _PromptDebugSnapshot fromMessage(String text) {
    var cursor = 0;
    String? attachments;
    String? preferredSkills;
    String? executionContext;

    void skipLeadingNewlines() {
      while (cursor < text.length && text[cursor] == '\n') {
        cursor++;
      }
    }

    String? consumeBlock(String heading) {
      final prefix = '$heading:\n';
      if (!text.startsWith(prefix, cursor)) {
        return null;
      }
      final blockStart = cursor;
      final divider = text.indexOf('\n\n', blockStart);
      if (divider == -1) {
        cursor = text.length;
        return text.substring(blockStart).trimRight();
      }
      cursor = divider + 2;
      return text.substring(blockStart, divider).trimRight();
    }

    while (cursor < text.length) {
      skipLeadingNewlines();
      final attachmentBlock = consumeBlock('Attached files');
      if (attachmentBlock != null) {
        attachments = attachmentBlock;
        continue;
      }
      final skillBlock = consumeBlock('Preferred skills');
      if (skillBlock != null) {
        preferredSkills = skillBlock;
        continue;
      }
      final executionBlock = consumeBlock('Execution context');
      if (executionBlock != null) {
        executionContext = executionBlock;
        continue;
      }
      break;
    }

    final remainder = text.substring(cursor).trimLeft();
    final executionContextParts = <String>[?preferredSkills, ?executionContext];

    return _PromptDebugSnapshot(
      bodyText: remainder.trim(),
      attachmentsBlock: attachments,
      executionContextBlock: executionContextParts.isEmpty
          ? null
          : executionContextParts.join('\n\n'),
    );
  }
}

class _MessageMetaToggleButton extends StatelessWidget {
  const _MessageMetaToggleButton({
    super.key,
    required this.icon,
    required this.expanded,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final bool expanded;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final iconColor = expanded ? palette.accent : palette.textMuted;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: expanded
                ? palette.surfaceSecondary
                : palette.surfacePrimary.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: expanded
                  ? palette.accent.withValues(alpha: 0.34)
                  : palette.strokeSoft,
            ),
          ),
          child: Icon(icon, size: 12, color: iconColor),
        ),
      ),
    );
  }
}

class _MessageMetaBlock extends StatelessWidget {
  const _MessageMetaBlock({super.key, required this.content});

  final String content;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: palette.surfaceSecondary.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.strokeSoft),
      ),
      child: SelectableText(
        content,
        style: theme.textTheme.bodySmall?.copyWith(
          color: palette.textSecondary,
          height: 1.35,
        ),
      ),
    );
  }
}

class _ToolCallTile extends StatefulWidget {
  const _ToolCallTile({
    required this.toolName,
    required this.summary,
    required this.pending,
    required this.error,
    required this.onOpenDetail,
  });

  final String toolName;
  final String summary;
  final bool pending;
  final bool error;
  final VoidCallback onOpenDetail;

  @override
  State<_ToolCallTile> createState() => _ToolCallTileState();
}

class _ToolCallTileState extends State<_ToolCallTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    final statusLabel = widget.pending
        ? 'running'
        : (widget.error ? 'error' : 'completed');
    final statusStyle = _pillStyleForStatus(context, statusLabel);
    final collapsedSummary = widget.summary.trim().isEmpty
        ? appText('工具调用进行中。', 'Tool call in progress.')
        : widget.summary.trim().replaceAll('\n', ' ');

    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Container(
          decoration: BoxDecoration(
            color: palette.surfaceSecondary.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: palette.strokeSoft),
          ),
          child: Column(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(AppRadius.card),
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: statusStyle.foregroundColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: RichText(
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          text: TextSpan(
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: palette.textSecondary,
                            ),
                            children: [
                              TextSpan(
                                text: widget.toolName,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                              const TextSpan(text: '  '),
                              TextSpan(text: collapsedSummary),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _StatusPill(
                        label: _toolCallStatusLabel(statusLabel),
                        backgroundColor: statusStyle.backgroundColor,
                        textColor: statusStyle.foregroundColor,
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        _expanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        size: 18,
                        color: palette.textMuted,
                      ),
                    ],
                  ),
                ),
              ),
              ClipRect(
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOutCubic,
                  child: _expanded
                      ? Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.sm,
                            0,
                            AppSpacing.sm,
                            AppSpacing.xs,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Divider(height: 1, color: palette.strokeSoft),
                              const SizedBox(height: 6),
                              Text(
                                widget.summary.trim().isEmpty
                                    ? appText(
                                        '工具调用进行中。',
                                        'Tool call in progress.',
                                      )
                                    : widget.summary.trim(),
                                style: theme.textTheme.bodySmall,
                              ),
                              const SizedBox(height: 4),
                              TextButton(
                                onPressed: widget.onOpenDetail,
                                child: Text(appText('打开详情', 'Open detail')),
                              ),
                            ],
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    this.backgroundColor,
    this.textColor,
  });

  final String label;
  final Color? backgroundColor;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color:
            backgroundColor ??
            Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.badge),
        border: Border.all(color: context.palette.strokeSoft),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(color: textColor),
      ),
    );
  }
}

class _ConnectionChip extends StatelessWidget {
  const _ConnectionChip({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connectionState = controller.currentAssistantConnectionState;
    final color = connectionState.isSingleAgent
        ? (connectionState.connected
              ? context.palette.accentMuted
              : context.palette.surfaceSecondary)
        : switch (connectionState.status) {
            RuntimeConnectionStatus.connected => context.palette.accentMuted,
            RuntimeConnectionStatus.connecting =>
              context.palette.surfaceSecondary,
            RuntimeConnectionStatus.error => context.palette.danger.withValues(
              alpha: 0.10,
            ),
            RuntimeConnectionStatus.offline => context.palette.surfaceSecondary,
          };

    return Container(
      key: const Key('assistant-connection-chip'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(color: context.palette.strokeSoft),
      ),
      child: Text(
        '${controller.assistantConnectionStatusLabel} · ${controller.assistantConnectionTargetLabel}',
        style: theme.textTheme.labelMedium,
      ),
    );
  }
}

class _MessageViewModeChip extends StatelessWidget {
  const _MessageViewModeChip({required this.value, required this.onSelected});

  final AssistantMessageViewMode value;
  final Future<void> Function(AssistantMessageViewMode mode) onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);

    return PopupMenuButton<AssistantMessageViewMode>(
      key: const Key('assistant-message-view-mode-button'),
      tooltip: appText('消息视图', 'Message view'),
      onSelected: (mode) => unawaited(onSelected(mode)),
      itemBuilder: (context) => AssistantMessageViewMode.values
          .map(
            (mode) => PopupMenuItem<AssistantMessageViewMode>(
              value: mode,
              child: Row(
                children: [
                  Expanded(child: Text(mode.label)),
                  if (mode == value) const Icon(Icons.check_rounded, size: 18),
                ],
              ),
            ),
          )
          .toList(growable: false),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: 5,
        ),
        decoration: BoxDecoration(
          color: palette.surfaceSecondary,
          borderRadius: BorderRadius.circular(AppRadius.chip),
          border: Border.all(color: palette.strokeSoft),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.notes_rounded, size: 14, color: palette.textMuted),
            const SizedBox(width: 4),
            Text(value.label, style: theme.textTheme.labelMedium),
            const SizedBox(width: 2),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 14,
              color: palette.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

enum _BubbleTone { user, assistant, agent }

enum _TimelineItemKind { user, assistant, agent, toolCall }

class _TimelineItem {
  const _TimelineItem._({
    required this.kind,
    this.label,
    this.text,
    this.title,
    this.pending = false,
    this.error = false,
  });

  const _TimelineItem.message({
    required _TimelineItemKind kind,
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

  const _TimelineItem.toolCall({
    required String toolName,
    required String summary,
    required bool pending,
    required bool error,
  }) : this._(
         kind: _TimelineItemKind.toolCall,
         title: toolName,
         text: summary,
         pending: pending,
         error: error,
       );

  final _TimelineItemKind kind;
  final String? label;
  final String? text;
  final String? title;
  final bool pending;
  final bool error;
}

class _AssistantTaskSeed {
  const _AssistantTaskSeed({
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

  _AssistantTaskEntry toEntry({required bool isCurrent}) {
    return _AssistantTaskEntry(
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

class _AssistantTaskEntry {
  const _AssistantTaskEntry({
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

  _AssistantTaskEntry copyWith({
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
    return _AssistantTaskEntry(
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

  String get updatedAtLabel => _sessionUpdatedAtLabel(updatedAtMs);
}

class _AssistantTaskGroup {
  const _AssistantTaskGroup({
    required this.executionTarget,
    required this.items,
  });

  final AssistantExecutionTarget executionTarget;
  final List<_AssistantTaskEntry> items;
}

class _PillStyle {
  const _PillStyle({
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final Color backgroundColor;
  final Color foregroundColor;
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.label, required this.icon});

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

_PillStyle _pillStyleForStatus(BuildContext context, String label) {
  final theme = Theme.of(context);
  final normalized = _normalizedTaskStatus(label);
  return switch (normalized) {
    'running' => _PillStyle(
      backgroundColor: context.palette.accentMuted,
      foregroundColor: theme.colorScheme.primary,
    ),
    'queued' => _PillStyle(
      backgroundColor: context.palette.surfaceSecondary,
      foregroundColor: context.palette.textSecondary,
    ),
    'failed' || 'error' => _PillStyle(
      backgroundColor: context.palette.surfacePrimary,
      foregroundColor: theme.colorScheme.error,
    ),
    _ => _PillStyle(
      backgroundColor: context.palette.surfacePrimary,
      foregroundColor: theme.colorScheme.tertiary,
    ),
  };
}

String _normalizedTaskStatus(String status) {
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

String _toolCallStatusLabel(String status) =>
    switch (_normalizedTaskStatus(status)) {
      'running' => appText('运行中', 'Running'),
      'failed' || 'error' => appText('错误', 'Error'),
      _ => appText('已完成', 'Completed'),
    };

String _assistantThinkingLabel(String level) => switch (level) {
  'low' => appText('低', 'Low'),
  'medium' => appText('中', 'Medium'),
  'max' => appText('超高', 'Max'),
  _ => appText('高', 'High'),
};

String _sessionDisplayTitle(GatewaySessionSummary session) {
  final label = session.label.trim();
  if (label.isEmpty || label == session.key) {
    return _fallbackSessionTitle(session.key);
  }
  if ((label == 'main' || label == 'agent:main:main') &&
      (session.derivedTitle ?? '').trim().toLowerCase() == 'main') {
    return _fallbackSessionTitle(session.key);
  }
  return label;
}

String _fallbackSessionTitle(String sessionKey) {
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

String? _sessionPreview(GatewaySessionSummary session) {
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

String _sessionStatus(
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

String _sessionUpdatedAtLabel(double? updatedAtMs) {
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

double _estimatedComposerWrapSectionHeight({
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

bool _sessionKeysMatch(String incoming, String current) {
  final left = incoming.trim().toLowerCase();
  final right = current.trim().toLowerCase();
  if (left == right) {
    return true;
  }
  return (left == 'agent:main:main' && right == 'main') ||
      (left == 'main' && right == 'agent:main:main');
}

const List<_ComposerSkillOption> _fallbackSkillOptions = <_ComposerSkillOption>[
  _ComposerSkillOption(
    key: '1password',
    label: '1password',
    description: '安全读取和注入本地凭据。',
    sourceLabel: 'Local',
    icon: Icons.auto_awesome_rounded,
  ),
  _ComposerSkillOption(
    key: 'xlsx',
    label: 'xlsx',
    description: '读取、整理和生成表格文件。',
    sourceLabel: 'Local',
    icon: Icons.auto_awesome_rounded,
  ),
  _ComposerSkillOption(
    key: 'web-processing',
    label: '网页处理',
    description: '打开网页、提取内容并完成网页操作。',
    sourceLabel: 'Web',
    icon: Icons.language_rounded,
  ),
  _ComposerSkillOption(
    key: 'apple-reminders',
    label: 'apple-reminders',
    description: '管理提醒事项和任务提醒。',
    sourceLabel: 'Local',
    icon: Icons.auto_awesome_rounded,
  ),
  _ComposerSkillOption(
    key: 'blogwatcher',
    label: 'blogwatcher',
    description: '跟踪博客更新并生成摘要。',
    sourceLabel: 'Local',
    icon: Icons.auto_awesome_rounded,
  ),
];

_ComposerSkillOption _skillOptionFromGateway(GatewaySkillSummary skill) {
  final normalizedKey = skill.skillKey.trim().toLowerCase();
  final normalizedName = skill.name.trim().toLowerCase();
  final isWebSkill =
      normalizedKey.contains('browser') ||
      normalizedKey.contains('open-link') ||
      normalizedKey.contains('web') ||
      normalizedName.contains('browser') ||
      normalizedName.contains('网页');
  final label = isWebSkill ? '网页处理' : skill.name.trim();
  final key = isWebSkill ? 'web-processing' : normalizedKey;
  final sourceLabel = skill.source.trim().isEmpty ? 'Gateway' : skill.source;
  final description = skill.description.trim().isEmpty
      ? appText('可在当前任务中调用的技能。', 'Skill available in the current task.')
      : skill.description.trim();

  return _ComposerSkillOption(
    key: key,
    label: label,
    description: description,
    sourceLabel: sourceLabel,
    icon: isWebSkill ? Icons.language_rounded : Icons.auto_awesome_rounded,
  );
}

_ComposerSkillOption _skillOptionFromThreadSkill(
  AssistantThreadSkillEntry skill,
) {
  return _ComposerSkillOption(
    key: skill.key,
    label: skill.label.trim().isEmpty ? skill.key : skill.label.trim(),
    description: skill.description.trim().isEmpty
        ? appText('已绑定到当前线程的本地技能。', 'Local skill bound to this thread.')
        : skill.description.trim(),
    sourceLabel: skill.sourceLabel.trim().isEmpty
        ? skill.sourcePath
        : skill.sourceLabel.trim(),
    icon: Icons.auto_awesome_rounded,
  );
}

class _ComposerSkillOption {
  const _ComposerSkillOption({
    required this.key,
    required this.label,
    required this.description,
    required this.sourceLabel,
    required this.icon,
  });

  final String key;
  final String label;
  final String description;
  final String sourceLabel;
  final IconData icon;
}

class _ComposerSelectedSkillChip extends StatelessWidget {
  const _ComposerSelectedSkillChip({
    super.key,
    required this.option,
    required this.onDeleted,
  });

  final _ComposerSkillOption option;
  final VoidCallback onDeleted;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: _skillOptionTooltip(option),
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

class _SkillPickerPopover extends StatelessWidget {
  const _SkillPickerPopover({
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
  final List<_ComposerSkillOption> filteredSkills;
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
                          return _SkillPickerTile(
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

class _SkillPickerTile extends StatelessWidget {
  const _SkillPickerTile({
    super.key,
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final _ComposerSkillOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;

    return Tooltip(
      message: _skillOptionTooltip(option),
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

String _skillOptionTooltip(_ComposerSkillOption option) {
  final sourceLabel = option.sourceLabel.trim();
  return sourceLabel.isEmpty ? option.label : sourceLabel;
}

class _ComposerAttachment {
  const _ComposerAttachment({
    required this.name,
    required this.path,
    required this.icon,
    required this.mimeType,
  });

  final String name;
  final String path;
  final IconData icon;
  final String mimeType;

  factory _ComposerAttachment.fromXFile(XFile file) {
    final extension = file.name.split('.').last.toLowerCase();
    final mimeType = switch (extension) {
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'json' => 'application/json',
      'csv' => 'text/csv',
      'txt' || 'log' || 'md' || 'yaml' || 'yml' => 'text/plain',
      'pdf' => 'application/pdf',
      'zip' => 'application/zip',
      _ => 'application/octet-stream',
    };
    final icon = switch (extension) {
      'png' || 'jpg' || 'jpeg' || 'gif' || 'webp' => Icons.image_outlined,
      'log' || 'txt' || 'json' || 'csv' => Icons.description_outlined,
      _ => Icons.insert_drive_file_outlined,
    };

    return _ComposerAttachment(
      name: file.name,
      path: file.path,
      icon: icon,
      mimeType: mimeType,
    );
  }
}

class AssistantPasteIntent extends Intent {
  const AssistantPasteIntent();
}

Future<XFile?> _readClipboardImageAsXFile() async {
  final clipboard = SystemClipboard.instance;
  if (clipboard == null) {
    return null;
  }
  final reader = await clipboard.read();
  return await _readClipboardImageForFormat(
        reader,
        format: Formats.png,
        extension: 'png',
        mimeType: 'image/png',
      ) ??
      await _readClipboardImageForFormat(
        reader,
        format: Formats.jpeg,
        extension: 'jpg',
        mimeType: 'image/jpeg',
      ) ??
      await _readClipboardImageForFormat(
        reader,
        format: Formats.gif,
        extension: 'gif',
        mimeType: 'image/gif',
      ) ??
      await _readClipboardImageForFormat(
        reader,
        format: Formats.webp,
        extension: 'webp',
        mimeType: 'image/webp',
      );
}

Future<XFile?> _readClipboardImageForFormat(
  ClipboardReader reader, {
  required FileFormat format,
  required String extension,
  required String mimeType,
}) async {
  if (!reader.canProvide(format)) {
    return null;
  }
  final bytes = await _readClipboardFileBytes(reader, format);
  if (bytes == null || bytes.isEmpty) {
    return null;
  }
  final temporaryDirectory = await _resolveClipboardAttachmentTempDirectory();
  final fileName =
      'clipboard-image-${DateTime.now().microsecondsSinceEpoch}.$extension';
  final file = File('${temporaryDirectory.path}/$fileName');
  await file.writeAsBytes(bytes, flush: true);
  return XFile(file.path, mimeType: mimeType, name: fileName);
}

Future<Uint8List?> _readClipboardFileBytes(
  ClipboardReader reader,
  FileFormat format,
) {
  final completer = Completer<Uint8List?>();
  final progress = reader.getFile(
    format,
    (file) async {
      try {
        final bytes = await file.readAll();
        if (!completer.isCompleted) {
          completer.complete(bytes);
        }
      } catch (error, stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      }
    },
    onError: (error) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    },
  );
  if (progress == null) {
    return Future<Uint8List?>.value(null);
  }
  return completer.future;
}

Future<Directory> _resolveClipboardAttachmentTempDirectory() async {
  Directory rootDirectory;
  try {
    rootDirectory = await getTemporaryDirectory();
  } catch (_) {
    rootDirectory = Directory.systemTemp;
  }
  final clipboardDirectory = Directory(
    '${rootDirectory.path}/xworkmate-clipboard-attachments',
  );
  await clipboardDirectory.create(recursive: true);
  return clipboardDirectory;
}
