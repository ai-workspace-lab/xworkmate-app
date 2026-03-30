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
import 'assistant_page_components.dart';
import 'assistant_page_composer_bar.dart';
import 'assistant_page_composer_state_helpers.dart';
import 'assistant_page_composer_support.dart';
import 'assistant_page_tooltip_labels.dart';
import 'assistant_page_message_widgets.dart';
import 'assistant_page_task_models.dart';
import 'assistant_page_composer_skill_models.dart';
import 'assistant_page_composer_skill_picker.dart';
import 'assistant_page_composer_clipboard.dart';
import 'assistant_page_components_core.dart';
import 'assistant_page_state_closure.dart';
import 'assistant_page_state_actions.dart';

const double assistantComposerDefaultInputHeightInternal = 78;
const double assistantWorkspaceMinConversationHeightInternal = 180;
const double assistantWorkspaceMinLowerPaneHeightInternal = 160;
const double assistantHorizontalResizeHandleWidthInternal = 6;
const double assistantHorizontalPaneGapInternal = 2;
const double assistantVerticalResizeHandleHeightInternal = 10;
const double assistantArtifactPaneMinWidthInternal = 280;
const double assistantArtifactPaneDefaultWidthInternal = 360;
const double assistantCollapsedArtifactToggleClearanceInternal = 56;
const double assistantComposerSafeAreaGapInternal = 8;
const double assistantComposerBaseHeightCompactInternal = 168;
const double assistantComposerBaseHeightTallInternal = 188;
const int assistantTaskActionMaxRetryCountInternal = 5;

typedef AssistantClipboardImageReader = Future<XFile?> Function();

class AssistantPage extends StatefulWidget {
  const AssistantPage({
    super.key,
    required this.controller,
    required this.onOpenDetail,
    this.navigationPanelBuilder,
    this.showStandaloneTaskRail = true,
    this.unifiedPaneStartsCollapsed = false,
    this.clipboardImageReader,
  });

  final AppController controller;
  final ValueChanged<DetailPanelData> onOpenDetail;
  final Widget Function(double contentWidth)? navigationPanelBuilder;
  final bool showStandaloneTaskRail;
  final bool unifiedPaneStartsCollapsed;
  final AssistantClipboardImageReader? clipboardImageReader;

  @override
  State<AssistantPage> createState() => AssistantPageStateInternal();
}

class AssistantPageStateInternal extends State<AssistantPage> {
  static const double sidePaneMinWidthInternal = 184;
  static const double sidePaneContentMinWidthInternal = 140;
  static const double mainWorkspaceMinWidthInternal = 620;
  static const double sidePaneViewportPaddingInternal = 72;
  static const double sideTabRailWidthInternal = 46;

  late final TextEditingController inputControllerInternal;
  late final TextEditingController threadSearchControllerInternal;
  late final ScrollController conversationControllerInternal;
  late final FocusNode composerFocusNodeInternal;
  final String modeInternal = 'ask';
  String thinkingLabelInternal = 'high';
  double threadRailWidthInternal = 248;
  String threadQueryInternal = '';
  bool sidePaneCollapsedInternal = false;
  AssistantSidePaneInternal activeSidePaneInternal =
      AssistantSidePaneInternal.tasks;
  AssistantFocusEntry? activeFocusedDestinationInternal;
  final Map<String, AssistantTaskSeedInternal> taskSeedsInternal =
      <String, AssistantTaskSeedInternal>{};
  final Set<String> archivedTaskKeysInternal = <String>{};
  List<ComposerAttachmentInternal> attachmentsInternal =
      const <ComposerAttachmentInternal>[];
  String? lastAutoAgentLabelInternal;
  String lastConversationScrollSignatureInternal = '';
  double composerInputHeightInternal =
      assistantComposerDefaultInputHeightInternal;
  double composerMeasuredContentHeightInternal = 0;
  double workspaceLowerPaneHeightAdjustmentInternal = 0;
  bool artifactPaneCollapsedInternal = true;
  double artifactPaneWidthInternal = assistantArtifactPaneDefaultWidthInternal;

  @override
  void initState() {
    super.initState();
    inputControllerInternal = TextEditingController();
    threadSearchControllerInternal = TextEditingController();
    conversationControllerInternal = ScrollController();
    composerFocusNodeInternal = FocusNode();
    sidePaneCollapsedInternal = widget.unifiedPaneStartsCollapsed;
  }

  @override
  void didUpdateWidget(covariant AssistantPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.unifiedPaneStartsCollapsed !=
        widget.unifiedPaneStartsCollapsed) {
      sidePaneCollapsedInternal = widget.unifiedPaneStartsCollapsed;
    }
  }

  void handleComposerContentHeightChangedInternal(double value) {
    if (!mounted || !value.isFinite || value <= 0) {
      return;
    }
    if ((composerMeasuredContentHeightInternal - value).abs() < 0.5) {
      return;
    }
    setState(() {
      composerMeasuredContentHeightInternal = value;
    });
  }

  @override
  void dispose() {
    inputControllerInternal.dispose();
    threadSearchControllerInternal.dispose();
    conversationControllerInternal.dispose();
    composerFocusNodeInternal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        final messages = List<GatewayChatMessage>.from(controller.chatMessages);
        final timelineItems = buildTimelineItemsInternal(controller, messages);
        final tasks = buildTaskEntriesInternal(controller);
        final visibleTasks = filterTasksInternal(tasks);
        final currentTask = resolveCurrentTaskInternal(
          tasks,
          controller.currentSessionKey,
        );
        final scrollSignature = messages.isEmpty
            ? controller.currentSessionKey
            : '${controller.currentSessionKey}:${messages.length}:${messages.last.id}:${messages.last.pending}:${messages.last.error}';

        if (scrollSignature != lastConversationScrollSignatureInternal) {
          lastConversationScrollSignatureInternal = scrollSignature;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !conversationControllerInternal.hasClients) {
              return;
            }
            conversationControllerInternal.animateTo(
              conversationControllerInternal.position.maxScrollExtent,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
            );
          });
        }

        return DesktopWorkspaceScaffold(
          padding: EdgeInsets.zero,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final showThreadRail =
                  widget.showStandaloneTaskRail &&
                  constraints.maxWidth >= 860;
              final mainWorkspace = buildMainWorkspaceInternal(
                controller: controller,
                timelineItems: timelineItems,
                currentTask: currentTask,
              );
              final workspaceWithArtifacts =
                  buildWorkspaceWithArtifactsInternal(
                    controller: controller,
                    currentTask: currentTask,
                    child: mainWorkspace,
                  );
              if (!showThreadRail) {
                return workspaceWithArtifacts;
              }

              final maxThreadRailWidth = resolveMaxSidePaneWidthInternal(
                constraints.maxWidth,
              );
              final threadRailWidth = threadRailWidthInternal
                  .clamp(sidePaneMinWidthInternal, maxThreadRailWidth)
                  .toDouble();

              return Row(
                children: [
                  SizedBox(
                    width: threadRailWidth,
                    child: AssistantTaskRailInternal(
                      key: const Key('assistant-task-rail'),
                      controller: controller,
                      tasks: visibleTasks,
                      query: threadQueryInternal,
                      searchController: threadSearchControllerInternal,
                      onQueryChanged: (value) {
                        setState(() {
                          threadQueryInternal = value.trim();
                        });
                      },
                      onClearQuery: () {
                        threadSearchControllerInternal.clear();
                        setState(() {
                          threadQueryInternal = '';
                        });
                      },
                      onRefreshTasks: refreshTasksWithRetryInternal,
                      onCreateTask: createNewThreadInternal,
                      onSelectTask: switchSessionWithRetryInternal,
                      onArchiveTask: archiveTaskInternal,
                      onRenameTask: renameTaskInternal,
                    ),
                  ),
                  SizedBox(
                    width: assistantHorizontalResizeHandleWidthInternal,
                    child: PaneResizeHandle(
                      axis: Axis.horizontal,
                      onDelta: (delta) {
                        setState(() {
                          threadRailWidthInternal =
                              (threadRailWidthInternal + delta)
                                  .clamp(
                                    sidePaneMinWidthInternal,
                                    maxThreadRailWidth,
                                  )
                                  .toDouble();
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: assistantHorizontalPaneGapInternal),
                  Expanded(child: workspaceWithArtifacts),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

enum AssistantSidePaneInternal { tasks, navigation, focused }

class AssistantUnifiedSidePaneInternal extends StatelessWidget {
  const AssistantUnifiedSidePaneInternal({
    super.key,
    required this.activePane,
    required this.activeFocusedDestination,
    required this.collapsed,
    required this.favoriteDestinations,
    required this.taskPanel,
    required this.navigationPanel,
    required this.focusedPanel,
    required this.onSelectPane,
    required this.onSelectFocusedDestination,
    required this.onToggleCollapsed,
  });

  final AssistantSidePaneInternal activePane;
  final AssistantFocusEntry? activeFocusedDestination;
  final bool collapsed;
  final List<AssistantFocusEntry> favoriteDestinations;
  final Widget taskPanel;
  final Widget navigationPanel;
  final Widget? focusedPanel;
  final ValueChanged<AssistantSidePaneInternal> onSelectPane;
  final ValueChanged<AssistantFocusEntry> onSelectFocusedDestination;
  final VoidCallback onToggleCollapsed;

  @override
  Widget build(BuildContext context) {
    final sidePaneContent = activePane == AssistantSidePaneInternal.tasks
        ? taskPanel
        : activePane == AssistantSidePaneInternal.focused &&
              focusedPanel != null
        ? focusedPanel!
        : navigationPanel;

    return Row(
      children: [
        AssistantSideTabRailInternal(
          activePane: activePane,
          activeFocusedDestination: activeFocusedDestination,
          collapsed: collapsed,
          favoriteDestinations: favoriteDestinations,
          onSelectPane: onSelectPane,
          onSelectFocusedDestination: onSelectFocusedDestination,
          onToggleCollapsed: onToggleCollapsed,
        ),
        if (!collapsed) ...[
          const SizedBox(width: 6),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: KeyedSubtree(
                key: ValueKey<String>(switch (activePane) {
                  AssistantSidePaneInternal.tasks =>
                    'assistant-side-pane-tasks',
                  AssistantSidePaneInternal.navigation =>
                    'assistant-side-pane-navigation',
                  AssistantSidePaneInternal.focused =>
                    'assistant-side-pane-focused-${activeFocusedDestination?.name ?? 'none'}',
                }),
                child: sidePaneContent,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class AssistantSideTabRailInternal extends StatelessWidget {
  const AssistantSideTabRailInternal({
    super.key,
    required this.activePane,
    required this.activeFocusedDestination,
    required this.collapsed,
    required this.favoriteDestinations,
    required this.onSelectPane,
    required this.onSelectFocusedDestination,
    required this.onToggleCollapsed,
  });

  final AssistantSidePaneInternal activePane;
  final AssistantFocusEntry? activeFocusedDestination;
  final bool collapsed;
  final List<AssistantFocusEntry> favoriteDestinations;
  final ValueChanged<AssistantSidePaneInternal> onSelectPane;
  final ValueChanged<AssistantFocusEntry> onSelectFocusedDestination;
  final VoidCallback onToggleCollapsed;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      key: const Key('assistant-side-pane'),
      width: 46,
      decoration: BoxDecoration(
        color: palette.chromeSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: palette.strokeSoft),
      ),
      child: Column(
        children: [
          const SizedBox(height: 4),
          AssistantSideTabButtonInternal(
            key: const Key('assistant-side-pane-tab-tasks'),
            icon: Icons.checklist_rtl_rounded,
            selected: activePane == AssistantSidePaneInternal.tasks,
            tooltip: appText('任务', 'Tasks'),
            onTap: () => onSelectPane(AssistantSidePaneInternal.tasks),
          ),
          const SizedBox(height: 4),
          AssistantSideTabButtonInternal(
            key: const Key('assistant-side-pane-tab-navigation'),
            icon: Icons.dashboard_customize_outlined,
            selected: activePane == AssistantSidePaneInternal.navigation,
            tooltip: appText('导航', 'Navigation'),
            onTap: () => onSelectPane(AssistantSidePaneInternal.navigation),
          ),
          if (favoriteDestinations.isNotEmpty) ...[
            const SizedBox(height: 4),
            Container(width: 24, height: 1, color: palette.strokeSoft),
            const SizedBox(height: 4),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.zero,
                child: Column(
                  children: favoriteDestinations
                      .map(
                        (destination) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: AssistantSideTabButtonInternal(
                            key: ValueKey<String>(
                              'assistant-side-pane-tab-focus-${destination.name}',
                            ),
                            icon: destination.icon,
                            selected:
                                activePane ==
                                    AssistantSidePaneInternal.focused &&
                                activeFocusedDestination == destination,
                            tooltip: destination.label,
                            onTap: () =>
                                onSelectFocusedDestination(destination),
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
            ),
          ] else
            const Spacer(),
          IconButton(
            key: const Key('assistant-side-pane-toggle'),
            tooltip: collapsed
                ? appText('展开侧板', 'Expand side pane')
                : appText('收起侧板', 'Collapse side pane'),
            onPressed: onToggleCollapsed,
            style: IconButton.styleFrom(
              backgroundColor: palette.surfacePrimary,
              foregroundColor: palette.textSecondary,
              side: BorderSide(color: palette.strokeSoft),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: Icon(
              collapsed
                  ? Icons.keyboard_double_arrow_right_rounded
                  : Icons.keyboard_double_arrow_left_rounded,
              size: 18,
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class AssistantSideTabButtonInternal extends StatefulWidget {
  const AssistantSideTabButtonInternal({
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
  State<AssistantSideTabButtonInternal> createState() =>
      AssistantSideTabButtonStateInternal();
}

class AssistantSideTabButtonStateInternal
    extends State<AssistantSideTabButtonInternal> {
  bool hoveredInternal = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => hoveredInternal = true),
        onExit: (_) => setState(() => hoveredInternal = false),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: widget.onTap,
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: widget.selected
                    ? palette.surfacePrimary
                    : hoveredInternal
                    ? palette.surfaceSecondary
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: widget.selected || hoveredInternal
                      ? palette.strokeSoft
                      : Colors.transparent,
                ),
              ),
              child: Icon(
                widget.icon,
                size: 18,
                color: widget.selected
                    ? palette.textPrimary
                    : palette.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AssistantLowerPaneInternal extends StatelessWidget {
  const AssistantLowerPaneInternal({
    super.key,
    required this.bottomContentInset,
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
    required this.onComposerContentHeightChanged,
    required this.onComposerInputHeightChanged,
    required this.onSend,
  });

  final double bottomContentInset;
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
  final ValueChanged<double> onComposerContentHeightChanged;
  final ValueChanged<double> onComposerInputHeightChanged;
  final Future<void> Function() onSend;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return ColoredBox(
      color: palette.canvas,
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        padding: EdgeInsets.only(bottom: bottomContentInset),
        child: ComposerBarInternal(
          controller: controller,
          inputController: inputController,
          focusNode: focusNode,
          thinkingLabel: thinkingLabel,
          showModelControl: showModelControl,
          modelLabel: modelLabel,
          modelOptions: modelOptions,
          attachments: attachments,
          availableSkills: availableSkills,
          selectedSkillKeys: selectedSkillKeys,
          onRemoveAttachment: onRemoveAttachment,
          onToggleSkill: onToggleSkill,
          onThinkingChanged: onThinkingChanged,
          onModelChanged: onModelChanged,
          onOpenGateway: onOpenGateway,
          onOpenAiGatewaySettings: onOpenAiGatewaySettings,
          onReconnectGateway: onReconnectGateway,
          onPickAttachments: onPickAttachments,
          onAddAttachment: onAddAttachment,
          onPasteImageAttachment: onPasteImageAttachment,
          onContentHeightChanged: onComposerContentHeightChanged,
          onInputHeightChanged: onComposerInputHeightChanged,
          onSend: onSend,
        ),
      ),
    );
  }
}

class ConversationAreaInternal extends StatelessWidget {
  const ConversationAreaInternal({
    super.key,
    required this.controller,
    required this.currentTask,
    required this.items,
    required this.messageViewMode,
    required this.bottomContentInset,
    required this.topTrailingInset,
    required this.scrollController,
    required this.onOpenDetail,
    required this.onFocusComposer,
    required this.onOpenGateway,
    required this.onOpenAiGatewaySettings,
    required this.onReconnectGateway,
    required this.onMessageViewModeChanged,
  });

  final AppController controller;
  final AssistantTaskEntryInternal currentTask;
  final List<TimelineItemInternal> items;
  final AssistantMessageViewMode messageViewMode;
  final double bottomContentInset;
  final double topTrailingInset;
  final ScrollController scrollController;
  final ValueChanged<DetailPanelData> onOpenDetail;
  final VoidCallback onFocusComposer;
  final VoidCallback onOpenGateway;
  final VoidCallback onOpenAiGatewaySettings;
  final Future<void> Function() onReconnectGateway;
  final Future<void> Function(AssistantMessageViewMode mode)
  onMessageViewModeChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(10, 8, 10 + topTrailingInset, 8),
          child: Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              alignment: WrapAlignment.end,
              children: [
                MessageViewModeChipInternal(
                  value: messageViewMode,
                  onSelected: onMessageViewModeChanged,
                ),
                ConnectionChipInternal(controller: controller),
              ],
            ),
          ),
        ),
        Divider(height: 1, color: palette.strokeSoft),
        Expanded(
          child: Container(
            decoration: BoxDecoration(color: palette.canvas),
            child: items.isEmpty
                ? AssistantEmptyStateInternal(
                    controller: controller,
                    onFocusComposer: onFocusComposer,
                    onOpenGateway: onOpenGateway,
                    onOpenAiGatewaySettings: onOpenAiGatewaySettings,
                    onReconnectGateway: onReconnectGateway,
                  )
                : ListView.separated(
                    controller: scrollController,
                    padding: EdgeInsets.fromLTRB(
                      10,
                      8,
                      10,
                      8 + bottomContentInset,
                    ),
                    physics: const BouncingScrollPhysics(),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return switch (item.kind) {
                        TimelineItemKindInternal.user => MessageBubbleInternal(
                          label: item.label!,
                          text: item.text!,
                          alignRight: true,
                          tone: BubbleToneInternal.user,
                          messageViewMode: messageViewMode,
                        ),
                        TimelineItemKindInternal.assistant =>
                          MessageBubbleInternal(
                            label: item.label!,
                            text: item.text!,
                            alignRight: false,
                            tone: BubbleToneInternal.assistant,
                            messageViewMode: messageViewMode,
                          ),
                        TimelineItemKindInternal.agent => MessageBubbleInternal(
                          label: item.label!,
                          text: item.text!,
                          alignRight: false,
                          tone: BubbleToneInternal.agent,
                          messageViewMode: messageViewMode,
                        ),
                        TimelineItemKindInternal.toolCall =>
                          ToolCallTileInternal(
                            toolName: item.title!,
                            summary: item.text!,
                            pending: item.pending,
                            error: item.error,
                            onOpenDetail: () => onOpenDetail(
                              DetailPanelData(
                                title: item.title!,
                                subtitle: appText('工具调用', 'Tool Call'),
                                icon: Icons.build_circle_outlined,
                                status: StatusInfo(
                                  item.pending
                                      ? appText('运行中', 'Running')
                                      : appText('已完成', 'Completed'),
                                  item.error
                                      ? StatusTone.danger
                                      : StatusTone.accent,
                                ),
                                description: item.text ?? '',
                                meta: [
                                  controller.currentSessionKey,
                                  controller.activeAgentName,
                                ],
                                actions: [appText('复制', 'Copy')],
                                sections: const [],
                              ),
                            ),
                          ),
                      };
                    },
                  ),
          ),
        ),
      ],
    );
  }
}
