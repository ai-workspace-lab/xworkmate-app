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
import 'assistant_page_composer_state_helpers.dart';
import 'assistant_page_composer_support.dart';
import 'assistant_page_tooltip_labels.dart';
import 'assistant_page_message_widgets.dart';
import 'assistant_page_task_models.dart';
import 'assistant_page_composer_skill_models.dart';
import 'assistant_page_composer_skill_picker.dart';
import 'assistant_page_composer_clipboard.dart';
import 'assistant_page_components_core.dart';

class ComposerBarInternal extends StatefulWidget {
  const ComposerBarInternal({
    super.key,
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
  final List<ComposerAttachmentInternal> attachments;
  final List<ComposerSkillOptionInternal> availableSkills;
  final List<String> selectedSkillKeys;
  final ValueChanged<ComposerAttachmentInternal> onRemoveAttachment;
  final ValueChanged<String> onToggleSkill;
  final ValueChanged<String> onThinkingChanged;
  final Future<void> Function(String modelId) onModelChanged;
  final VoidCallback onOpenGateway;
  final VoidCallback onOpenAiGatewaySettings;
  final Future<void> Function() onReconnectGateway;
  final VoidCallback onPickAttachments;
  final ValueChanged<ComposerAttachmentInternal> onAddAttachment;
  final AssistantClipboardImageReader onPasteImageAttachment;
  final ValueChanged<double> onContentHeightChanged;
  final ValueChanged<double> onInputHeightChanged;
  final Future<void> Function() onSend;

  @override
  State<ComposerBarInternal> createState() => ComposerBarStateInternal();
}

class ComposerBarStateInternal extends State<ComposerBarInternal> {
  static const double minInputHeightInternal = 68;
  static const double defaultInputHeightInternal =
      assistantComposerDefaultInputHeightInternal;
  static const double maxInputHeightInternal = 220;
  static const Map<ShortcutActivator, Intent> pasteShortcutsInternal =
      <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.keyV, meta: true):
            AssistantPasteIntent(),
        SingleActivator(LogicalKeyboardKey.keyV, control: true):
            AssistantPasteIntent(),
      };

  late double inputHeightInternal;
  final GlobalKey skillPickerTargetKeyInternal = GlobalKey(
    debugLabel: 'assistant-skill-picker-target',
  );
  final GlobalKey contentKeyInternal = GlobalKey(
    debugLabel: 'assistant-composer-bar',
  );
  final LayerLink skillPickerLayerLinkInternal = LayerLink();
  final OverlayPortalController skillPickerPortalControllerInternal =
      OverlayPortalController(debugLabel: 'assistant-skill-picker');
  late final TextEditingController skillPickerSearchControllerInternal;
  late final FocusNode skillPickerSearchFocusNodeInternal;
  bool handlingPasteShortcutInternal = false;
  bool refreshingSingleAgentSkillsInternal = false;
  String skillPickerQueryInternal = '';

  @override
  void initState() {
    super.initState();
    inputHeightInternal = defaultInputHeightInternal;
    skillPickerSearchControllerInternal = TextEditingController();
    skillPickerSearchFocusNodeInternal = FocusNode();
    widget.controller.addListener(handleControllerChangedInternal);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      widget.onInputHeightChanged(inputHeightInternal);
      reportContentHeightInternal();
    });
  }

  @override
  void didUpdateWidget(covariant ComposerBarInternal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(handleControllerChangedInternal);
      widget.controller.addListener(handleControllerChangedInternal);
    }
    reportContentHeightInternal();
  }

  Future<void> refreshSingleAgentSkillsInternal() async {
    if (refreshingSingleAgentSkillsInternal) {
      return;
    }
    setState(() {
      refreshingSingleAgentSkillsInternal = true;
    });
    try {
      await widget.controller.refreshSingleAgentLocalSkillsForSession(
        widget.controller.currentSessionKey,
      );
    } finally {
      if (mounted) {
        setState(() {
          refreshingSingleAgentSkillsInternal = false;
        });
      }
    }
  }

  List<ComposerSkillOptionInternal> activeSkillOptionsInternal() {
    if (widget.controller.isSingleAgentMode) {
      return widget.controller
          .assistantImportedSkillsForSession(
            widget.controller.currentSessionKey,
          )
          .map(skillOptionFromThreadSkillInternal)
          .toList(growable: false);
    }
    return widget.availableSkills;
  }

  List<ComposerSkillOptionInternal> filteredSkillOptionsInternal() {
    final normalizedQuery = skillPickerQueryInternal.trim().toLowerCase();
    if (normalizedQuery.isEmpty) {
      return activeSkillOptionsInternal();
    }
    return activeSkillOptionsInternal()
        .where((skill) {
          final haystack =
              '${skill.label}\n${skill.description}\n${skill.sourceLabel}'
                  .toLowerCase();
          return haystack.contains(normalizedQuery);
        })
        .toList(growable: false);
  }

  Widget buildSkillPickerOverlayInternal(BuildContext context) =>
      buildSkillPickerOverlayForInternal(this, context);

  void hideSkillPickerInternal() {
    if (skillPickerPortalControllerInternal.isShowing) {
      skillPickerPortalControllerInternal.hide();
    }
    if (skillPickerQueryInternal.isNotEmpty ||
        skillPickerSearchControllerInternal.text.isNotEmpty) {
      setState(resetSkillPickerSearchInternal);
    }
  }

  void toggleSkillPickerInternal() {
    if (skillPickerPortalControllerInternal.isShowing) {
      hideSkillPickerInternal();
      return;
    }
    setState(resetSkillPickerSearchInternal);
    skillPickerPortalControllerInternal.show();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !skillPickerPortalControllerInternal.isShowing) {
        return;
      }
      skillPickerSearchFocusNodeInternal.requestFocus();
    });
    if (widget.controller.isSingleAgentMode) {
      unawaited(refreshSingleAgentSkillsInternal());
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(handleControllerChangedInternal);
    if (skillPickerPortalControllerInternal.isShowing) {
      skillPickerPortalControllerInternal.hide();
    }
    skillPickerSearchControllerInternal.dispose();
    skillPickerSearchFocusNodeInternal.dispose();
    super.dispose();
  }

  void handleControllerChangedInternal() {
    if (!mounted || !skillPickerPortalControllerInternal.isShowing) {
      return;
    }
    setState(() {});
  }

  void reportContentHeightInternal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final height = contentKeyInternal.currentContext?.size?.height;
      if (height == null || !height.isFinite || height <= 0) {
        return;
      }
      widget.onContentHeightChanged(height);
    });
  }

  void resizeInputInternal(double delta) {
    final nextHeight = (inputHeightInternal + delta).clamp(
      minInputHeightInternal,
      maxInputHeightInternal,
    );
    if (nextHeight == inputHeightInternal) {
      return;
    }
    setState(() {
      inputHeightInternal = nextHeight;
    });
    widget.onInputHeightChanged(inputHeightInternal);
  }

  Future<void> handlePasteShortcutInternal() async {
    if (handlingPasteShortcutInternal) {
      return;
    }
    handlingPasteShortcutInternal = true;
    try {
      if (widget.controller
          .featuresFor(resolveUiFeaturePlatformFromContext(context))
          .supportsFileAttachments) {
        final imageFile = await widget.onPasteImageAttachment();
        if (!mounted) {
          return;
        }
        if (imageFile != null) {
          widget.onAddAttachment(
            ComposerAttachmentInternal.fromXFile(imageFile),
          );
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
      insertTextAtSelectionInternal(text);
    } finally {
      handlingPasteShortcutInternal = false;
    }
  }

  void insertTextAtSelectionInternal(String text) {
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

  void resetSkillPickerSearchInternal() {
    skillPickerSearchControllerInternal.clear();
    skillPickerQueryInternal = '';
  }

  void setSkillPickerQueryInternal(String value) {
    setState(() {
      skillPickerQueryInternal = value;
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
    final visibleExecutionTargets = controller.visibleAssistantExecutionTargets(
      uiFeatures.availableExecutionTargets,
    );
    final currentExecutionTarget = controller.assistantExecutionTarget;
    final executionTarget =
        visibleExecutionTargets.contains(currentExecutionTarget)
        ? currentExecutionTarget
        : (visibleExecutionTargets.isNotEmpty
              ? visibleExecutionTargets.first
              : currentExecutionTarget);
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

    reportContentHeightInternal();

    return Padding(
      key: contentKeyInternal,
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
                  child: const ComposerIconButtonInternal(
                    icon: Icons.add_rounded,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              if (visibleExecutionTargets.isNotEmpty) ...[
                PopupMenuButton<AssistantExecutionTarget>(
                  key: const Key('assistant-execution-target-button'),
                  tooltip: appText('任务对话模式', 'Task Dialog Mode'),
                  onSelected: (value) {
                    controller.setAssistantExecutionTarget(value);
                  },
                  itemBuilder: (context) => visibleExecutionTargets
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
                  child: ComposerToolbarChipInternal(
                    icon: executionTarget.icon,
                    tooltip: executionTargetTooltipInternal(executionTarget),
                    showChevron: true,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              if (singleAgent &&
                  executionTarget != AssistantExecutionTarget.auto) ...[
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
                              SingleAgentProviderBadgeInternal(provider: value),
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
                  child: ComposerToolbarChipInternal(
                    leading: SingleAgentProviderBadgeInternal(
                      provider: controller.currentSingleAgentProvider,
                    ),
                    tooltip: singleAgentProviderTooltipInternal(
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
                    ? ComposerToolbarChipInternal(
                        key: const Key('assistant-model-button'),
                        icon: Icons.bolt_rounded,
                        tooltip: modelTooltipInternal(widget.modelLabel),
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
                        child: ComposerToolbarChipInternal(
                          icon: Icons.bolt_rounded,
                          tooltip: modelTooltipInternal(widget.modelLabel),
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
                      child: ComposerToolbarChipInternal(
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
            height: inputHeightInternal,
            child: Shortcuts(
              shortcuts: pasteShortcutsInternal,
              child: Actions(
                actions: <Type, Action<Intent>>{
                  AssistantPasteIntent: CallbackAction<AssistantPasteIntent>(
                    onInvoke: (_) {
                      unawaited(handlePasteShortcutInternal());
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
          ComposerResizeHandleInternal(
            key: const Key('assistant-composer-resize-handle'),
            onDelta: resizeInputInternal,
          ),
          if (selectedSkills.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: selectedSkills
                  .map(
                    (skill) => ComposerSelectedSkillChipInternal(
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
                        key: skillPickerTargetKeyInternal,
                        link: skillPickerLayerLinkInternal,
                        child: OverlayPortal(
                          controller: skillPickerPortalControllerInternal,
                          overlayChildBuilder: buildSkillPickerOverlayInternal,
                          child: InkWell(
                            key: const Key('assistant-skill-picker-button'),
                            borderRadius: BorderRadius.circular(AppRadius.chip),
                            onTap: toggleSkillPickerInternal,
                            child: ComposerToolbarChipInternal(
                              icon: Icons.auto_awesome_rounded,
                              tooltip: skillsTooltipInternal(
                                selectedSkills.length,
                              ),
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
                        child: ComposerToolbarChipInternal(
                          icon: permissionLevel.icon,
                          tooltip: permissionTooltipInternal(permissionLevel),
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
                                            assistantThinkingLabelInternal(
                                              value,
                                            ),
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
                        child: ComposerToolbarChipInternal(
                          icon: Icons.psychology_alt_outlined,
                          tooltip: thinkingTooltipInternal(
                            widget.thinkingLabel,
                          ),
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
