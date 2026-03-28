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
              final showUnifiedSidePane =
                  widget.navigationPanelBuilder != null &&
                  constraints.maxWidth >= 860;
              final showThreadRail =
                  !showUnifiedSidePane &&
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
              if (!showThreadRail && !showUnifiedSidePane) {
                return workspaceWithArtifacts;
              }

              final maxThreadRailWidth = resolveMaxSidePaneWidthInternal(
                constraints.maxWidth,
              );
              final threadRailWidth = threadRailWidthInternal
                  .clamp(sidePaneMinWidthInternal, maxThreadRailWidth)
                  .toDouble();

              if (showUnifiedSidePane) {
                final favoriteDestinations =
                    controller.assistantNavigationDestinations;
                final activeFocusedDestination =
                    resolveFocusedDestinationInternal(favoriteDestinations);
                final effectiveActiveSidePane =
                    activeSidePaneInternal ==
                            AssistantSidePaneInternal.focused &&
                        activeFocusedDestination == null
                    ? AssistantSidePaneInternal.navigation
                    : activeSidePaneInternal;
                final sidePanelContentWidth =
                    (threadRailWidth - sideTabRailWidthInternal - 2)
                        .clamp(sidePaneContentMinWidthInternal, threadRailWidth)
                        .toDouble();
                return Row(
                  children: [
                    AnimatedContainer(
                      key: const Key('assistant-unified-side-pane-shell'),
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      width: sidePaneCollapsedInternal
                          ? sideTabRailWidthInternal
                          : threadRailWidth,
                      child: AssistantUnifiedSidePaneInternal(
                        activePane: effectiveActiveSidePane,
                        activeFocusedDestination: activeFocusedDestination,
                        collapsed: sidePaneCollapsedInternal,
                        favoriteDestinations: favoriteDestinations,
                        taskPanel: AssistantTaskRailInternal(
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
                        navigationPanel: widget.navigationPanelBuilder!(
                          sidePanelContentWidth,
                        ),
                        focusedPanel: activeFocusedDestination == null
                            ? null
                            : SingleChildScrollView(
                                padding: const EdgeInsets.all(6),
                                child: AssistantFocusDestinationCard(
                                  controller: controller,
                                  destination: activeFocusedDestination,
                                  onOpenPage: () => controller.navigateTo(
                                    activeFocusedDestination.destination ??
                                        WorkspaceDestination.settings,
                                  ),
                                  onRemoveFavorite: () async {
                                    await controller
                                        .toggleAssistantNavigationDestination(
                                          activeFocusedDestination,
                                        );
                                    if (!mounted) {
                                      return;
                                    }
                                    setState(() {
                                      activeFocusedDestinationInternal =
                                          resolveFocusedDestinationInternal(
                                            controller
                                                .assistantNavigationDestinations,
                                          );
                                      activeSidePaneInternal =
                                          activeFocusedDestinationInternal ==
                                              null
                                          ? AssistantSidePaneInternal.navigation
                                          : AssistantSidePaneInternal.focused;
                                    });
                                  },
                                ),
                              ),
                        onSelectPane: (pane) {
                          setState(() {
                            final normalizedPane =
                                pane == AssistantSidePaneInternal.focused
                                ? AssistantSidePaneInternal.navigation
                                : pane;
                            if (effectiveActiveSidePane == normalizedPane) {
                              sidePaneCollapsedInternal =
                                  !sidePaneCollapsedInternal;
                              return;
                            }
                            activeSidePaneInternal = normalizedPane;
                            if (normalizedPane !=
                                AssistantSidePaneInternal.focused) {
                              activeFocusedDestinationInternal = null;
                            }
                            sidePaneCollapsedInternal = false;
                          });
                        },
                        onSelectFocusedDestination: (destination) {
                          setState(() {
                            final isSameSelection =
                                effectiveActiveSidePane ==
                                    AssistantSidePaneInternal.focused &&
                                activeFocusedDestination == destination;
                            if (isSameSelection) {
                              sidePaneCollapsedInternal =
                                  !sidePaneCollapsedInternal;
                              return;
                            }
                            activeFocusedDestinationInternal = destination;
                            activeSidePaneInternal =
                                AssistantSidePaneInternal.focused;
                            sidePaneCollapsedInternal = false;
                          });
                        },
                        onToggleCollapsed: () {
                          setState(() {
                            sidePaneCollapsedInternal =
                                !sidePaneCollapsedInternal;
                          });
                        },
                      ),
                    ),
                    if (!sidePaneCollapsedInternal)
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
              }

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

  Widget buildMainWorkspaceInternal({
    required AppController controller,
    required List<TimelineItemInternal> timelineItems,
    required AssistantTaskEntryInternal currentTask,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final palette = context.palette;
        final mediaQuery = MediaQuery.of(context);
        final composerBottomInset = math.max(
          mediaQuery.viewPadding.bottom,
          mediaQuery.viewInsets.bottom,
        );
        final composerBottomSpacing = composerBottomInset > 0
            ? composerBottomInset + assistantComposerSafeAreaGapInternal
            : assistantComposerSafeAreaGapInternal;
        final baseComposerHeight = constraints.maxHeight >= 900
            ? assistantComposerBaseHeightTallInternal
            : assistantComposerBaseHeightCompactInternal;
        final composerContentWidth = math.max(240.0, constraints.maxWidth - 32);
        final availableWorkspaceHeight = math.max(
          0.0,
          constraints.maxHeight - assistantVerticalResizeHandleHeightInternal,
        );
        final attachmentExtraHeight =
            estimatedComposerWrapSectionHeightInternal(
              itemCount: attachmentsInternal.length,
              availableWidth: composerContentWidth,
              averageChipWidth: 168,
            );
        final selectedSkillExtraHeight =
            estimatedComposerWrapSectionHeightInternal(
              itemCount: selectedSkillKeysForInternal(controller).length,
              availableWidth: composerContentWidth,
              averageChipWidth: 132,
            );
        final fallbackComposerContentHeight =
            baseComposerHeight +
            math.max(
              0.0,
              composerInputHeightInternal -
                  assistantComposerDefaultInputHeightInternal,
            ) +
            attachmentExtraHeight +
            selectedSkillExtraHeight;
        final composerContentHeight = composerMeasuredContentHeightInternal > 0
            ? composerMeasuredContentHeightInternal
            : fallbackComposerContentHeight;
        final defaultComposerHeight = math.min(
          availableWorkspaceHeight,
          composerContentHeight + composerBottomSpacing,
        );
        final composerHeightUpperBound = math.min(
          availableWorkspaceHeight,
          math.max(
            assistantWorkspaceMinLowerPaneHeightInternal +
                composerBottomSpacing,
            availableWorkspaceHeight -
                assistantWorkspaceMinConversationHeightInternal,
          ),
        );
        final composerHeightLowerBound = math.min(
          assistantWorkspaceMinLowerPaneHeightInternal + composerBottomSpacing,
          composerHeightUpperBound,
        );
        final composerHeight =
            (defaultComposerHeight + workspaceLowerPaneHeightAdjustmentInternal)
                .clamp(composerHeightLowerBound, composerHeightUpperBound)
                .toDouble();

        return SurfaceCard(
          borderRadius: 0,
          padding: EdgeInsets.zero,
          tone: SurfaceCardTone.chrome,
          child: Column(
            children: [
              Expanded(
                child: KeyedSubtree(
                  key: const Key('assistant-conversation-shell'),
                  child: ConversationAreaInternal(
                    controller: controller,
                    currentTask: currentTask,
                    items: timelineItems,
                    messageViewMode: controller.currentAssistantMessageViewMode,
                    bottomContentInset: composerBottomSpacing,
                    topTrailingInset: artifactPaneCollapsedInternal
                        ? assistantCollapsedArtifactToggleClearanceInternal
                        : 0,
                    scrollController: conversationControllerInternal,
                    onOpenDetail: widget.onOpenDetail,
                    onFocusComposer: focusComposerInternal,
                    onOpenGateway: openGatewaySettingsInternal,
                    onOpenAiGatewaySettings: openAiGatewaySettingsInternal,
                    onReconnectGateway:
                        connectFromSavedSettingsOrShowDialogInternal,
                    onMessageViewModeChanged:
                        controller.setAssistantMessageViewMode,
                  ),
                ),
              ),
              ColoredBox(
                color: palette.canvas,
                child: SizedBox(
                  key: const Key('assistant-workspace-resize-handle'),
                  height: assistantVerticalResizeHandleHeightInternal,
                  child: PaneResizeHandle(
                    axis: Axis.vertical,
                    onDelta: (delta) {
                      setState(() {
                        final nextComposerHeight = (composerHeight - delta)
                            .clamp(
                              composerHeightLowerBound,
                              composerHeightUpperBound,
                            )
                            .toDouble();
                        workspaceLowerPaneHeightAdjustmentInternal =
                            nextComposerHeight - defaultComposerHeight;
                      });
                    },
                  ),
                ),
              ),
              SizedBox(
                key: const Key('assistant-composer-shell'),
                height: composerHeight,
                child: AssistantLowerPaneInternal(
                  bottomContentInset: composerBottomSpacing,
                  inputController: inputControllerInternal,
                  focusNode: composerFocusNodeInternal,
                  thinkingLabel: thinkingLabelInternal,
                  showModelControl: !controller.isSingleAgentMode
                      ? true
                      : controller.currentSingleAgentShouldShowModelControl,
                  modelLabel: controller.isSingleAgentMode
                      ? controller.currentSingleAgentModelDisplayLabel
                      : controller.resolvedAssistantModel.isEmpty
                      ? appText('未选择模型', 'No model selected')
                      : controller.resolvedAssistantModel,
                  modelOptions: controller.assistantModelChoices,
                  attachments: attachmentsInternal,
                  availableSkills: availableSkillOptionsInternal(controller),
                  selectedSkillKeys: selectedSkillKeysForInternal(controller),
                  controller: controller,
                  onRemoveAttachment: (attachment) {
                    setState(() {
                      attachmentsInternal = attachmentsInternal
                          .where((item) => item.path != attachment.path)
                          .toList(growable: false);
                    });
                  },
                  onToggleSkill: (key) {
                    unawaited(
                      controller.toggleAssistantSkillForSession(
                        controller.currentSessionKey,
                        key,
                      ),
                    );
                    focusComposerInternal();
                  },
                  onThinkingChanged: (value) {
                    setState(() => thinkingLabelInternal = value);
                  },
                  onModelChanged: (modelId) =>
                      controller.selectAssistantModelForSession(
                        controller.currentSessionKey,
                        modelId,
                      ),
                  onOpenGateway: openGatewaySettingsInternal,
                  onOpenAiGatewaySettings: openAiGatewaySettingsInternal,
                  onReconnectGateway:
                      connectFromSavedSettingsOrShowDialogInternal,
                  onPickAttachments: pickAttachmentsInternal,
                  onAddAttachment: (attachment) {
                    setState(() {
                      attachmentsInternal = [
                        ...attachmentsInternal,
                        attachment,
                      ];
                    });
                  },
                  onPasteImageAttachment:
                      widget.clipboardImageReader ??
                      readClipboardImageAsXFileInternal,
                  onComposerContentHeightChanged:
                      handleComposerContentHeightChangedInternal,
                  onComposerInputHeightChanged:
                      handleComposerInputHeightChangedInternal,
                  onSend: submitPromptInternal,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget buildWorkspaceWithArtifactsInternal({
    required AppController controller,
    required AssistantTaskEntryInternal currentTask,
    required Widget child,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxPaneWidth = math.min(
          560.0,
          math.max(
            assistantArtifactPaneMinWidthInternal,
            constraints.maxWidth * 0.48,
          ),
        );
        final paneWidth = artifactPaneWidthInternal
            .clamp(assistantArtifactPaneMinWidthInternal, maxPaneWidth)
            .toDouble();
        final panel = Row(
          children: [
            Expanded(child: child),
            if (!artifactPaneCollapsedInternal) ...[
              SizedBox(
                key: const Key('assistant-artifact-pane-resize-handle'),
                width: assistantHorizontalResizeHandleWidthInternal,
                child: PaneResizeHandle(
                  axis: Axis.horizontal,
                  onDelta: (delta) {
                    setState(() {
                      artifactPaneWidthInternal =
                          (artifactPaneWidthInternal - delta)
                              .clamp(
                                assistantArtifactPaneMinWidthInternal,
                                maxPaneWidth,
                              )
                              .toDouble();
                    });
                  },
                ),
              ),
              const SizedBox(width: assistantHorizontalPaneGapInternal),
              SizedBox(
                width: paneWidth,
                child: AssistantArtifactSidebar(
                  sessionKey: controller.currentSessionKey,
                  threadTitle: currentTask.title,
                  workspaceRef: controller.assistantWorkspaceRefForSession(
                    controller.currentSessionKey,
                  ),
                  workspaceRefKind: controller
                      .assistantWorkspaceRefKindForSession(
                        controller.currentSessionKey,
                      ),
                  onCollapse: () {
                    setState(() {
                      artifactPaneCollapsedInternal = true;
                    });
                  },
                  loadSnapshot: () =>
                      controller.loadAssistantArtifactSnapshot(),
                  loadPreview: (entry) =>
                      controller.loadAssistantArtifactPreview(entry),
                ),
              ),
            ],
          ],
        );
        return Stack(
          children: [
            Positioned.fill(child: panel),
            if (artifactPaneCollapsedInternal)
              Positioned(
                right: 0,
                top: 0,
                child: AssistantArtifactSidebarRevealButton(
                  onTap: () {
                    setState(() {
                      artifactPaneCollapsedInternal = false;
                    });
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  void handleComposerInputHeightChangedInternal(double value) {
    if (!mounted || value == composerInputHeightInternal) {
      return;
    }
    setState(() {
      composerInputHeightInternal = value;
    });
  }

  List<TimelineItemInternal> buildTimelineItemsInternal(
    AppController controller,
    List<GatewayChatMessage> messages,
  ) {
    final items = <TimelineItemInternal>[];
    final ownerLabel = conversationOwnerLabelInternal(controller);

    for (final message in messages) {
      if ((message.toolName ?? '').trim().isNotEmpty) {
        items.add(
          TimelineItemInternal.toolCall(
            toolName: message.toolName!,
            summary: message.text,
            pending: message.pending,
            error: message.error,
          ),
        );
        continue;
      }

      final role = message.role.toLowerCase();
      if (role == 'user') {
        items.add(
          TimelineItemInternal.message(
            kind: TimelineItemKindInternal.user,
            label: appText('你', 'You'),
            text: message.text,
            pending: message.pending,
            error: message.error,
          ),
        );
      } else if (role == 'assistant') {
        items.add(
          TimelineItemInternal.message(
            kind: TimelineItemKindInternal.assistant,
            label: kProductBrandName,
            text: message.text,
            pending: message.pending,
            error: message.error,
          ),
        );
      } else {
        items.add(
          TimelineItemInternal.message(
            kind: TimelineItemKindInternal.agent,
            label: lastAutoAgentLabelInternal ?? ownerLabel,
            text: message.text,
            pending: message.pending,
            error: message.error,
          ),
        );
      }
    }

    return items;
  }

  Future<void> pickAttachmentsInternal() async {
    final uiFeatures = widget.controller.featuresFor(
      resolveUiFeaturePlatformFromContext(context),
    );
    if (!uiFeatures.supportsFileAttachments) {
      return;
    }
    final files = await openFiles(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Images',
          extensions: ['png', 'jpg', 'jpeg', 'gif', 'webp'],
        ),
        XTypeGroup(label: 'Logs', extensions: ['log', 'txt', 'json', 'csv']),
        XTypeGroup(
          label: 'Files',
          extensions: ['md', 'pdf', 'yaml', 'yml', 'zip'],
        ),
      ],
    );
    if (!mounted || files.isEmpty) {
      return;
    }

    setState(() {
      attachmentsInternal = [
        ...attachmentsInternal,
        ...files.map(ComposerAttachmentInternal.fromXFile),
      ];
    });
  }

  Future<void> submitPromptInternal() async {
    final controller = widget.controller;
    final uiFeatures = controller.featuresFor(
      resolveUiFeaturePlatformFromContext(context),
    );
    final settings = controller.settings;
    final executionTarget = controller.assistantExecutionTarget;
    final rawPrompt = inputControllerInternal.text.trim();
    if (rawPrompt.isEmpty) {
      return;
    }

    final shouldUseGatewayAgent =
        executionTarget != AssistantExecutionTarget.singleAgent;
    final autoAgent = shouldUseGatewayAgent
        ? pickAutoAgentInternal(controller, rawPrompt)
        : null;
    if (autoAgent != null) {
      await controller.selectAgent(autoAgent.id);
    }

    final submittedAttachments = List<ComposerAttachmentInternal>.from(
      attachmentsInternal,
      growable: false,
    );
    final attachmentNames = submittedAttachments
        .map((item) => item.name)
        .toList(growable: false);
    final selectedSkillLabels = resolveSelectedSkillLabelsInternal(controller);
    final connectionState = controller.currentAssistantConnectionState;
    final prompt = composePromptInternal(
      mode: modeInternal,
      prompt: rawPrompt,
      attachmentNames: attachmentNames,
      selectedSkillLabels: selectedSkillLabels,
      executionTarget: executionTarget,
      singleAgentProvider: controller.currentSingleAgentProvider,
      permissionLevel: settings.assistantPermissionLevel,
      workspacePath: controller.assistantWorkspaceRefForSession(
        controller.currentSessionKey,
      ),
    );

    setState(() {
      lastAutoAgentLabelInternal =
          autoAgent?.name ?? conversationOwnerLabelInternal(controller);
      attachmentsInternal = const <ComposerAttachmentInternal>[];
      touchTaskSeedInternal(
        sessionKey: controller.currentSessionKey,
        title:
            taskSeedsInternal[controller.currentSessionKey]?.title ??
            fallbackSessionTitleInternal(controller.currentSessionKey),
        preview: rawPrompt,
        status:
            controller.hasAssistantPendingRun ||
                executionTarget == AssistantExecutionTarget.singleAgent ||
                connectionState.connected
            ? 'running'
            : 'queued',
        owner: autoAgent?.name ?? conversationOwnerLabelInternal(controller),
        surface: 'Assistant',
        executionTarget: executionTarget,
        draft: controller.currentSessionKey.trim().startsWith('draft:'),
      );
    });
    inputControllerInternal.clear();

    try {
      if (uiFeatures.supportsMultiAgent &&
          controller.settings.multiAgent.enabled) {
        final collaborationAttachments = submittedAttachments
            .map(
              (item) => CollaborationAttachment(
                name: item.name,
                description: item.mimeType,
                path: item.path,
              ),
            )
            .toList(growable: false);
        await controller.runMultiAgentCollaboration(
          rawPrompt: rawPrompt,
          composedPrompt: prompt,
          attachments: collaborationAttachments,
          selectedSkillLabels: selectedSkillLabels,
        );
      } else {
        final attachmentPayloads = await buildAttachmentPayloadsInternal(
          submittedAttachments,
        );
        await controller.sendChatMessage(
          prompt,
          thinking: thinkingLabelInternal,
          attachments: attachmentPayloads,
          localAttachments: submittedAttachments
              .map(
                (item) => CollaborationAttachment(
                  name: item.name,
                  description: item.mimeType,
                  path: item.path,
                ),
              )
              .toList(growable: false),
          selectedSkillLabels: selectedSkillLabels,
        );
      }
    } catch (_) {
      if (!mounted) {
        rethrow;
      }
      if (inputControllerInternal.text.trim().isEmpty) {
        inputControllerInternal.value = TextEditingValue(
          text: rawPrompt,
          selection: TextSelection.collapsed(offset: rawPrompt.length),
        );
      }
      if (attachmentsInternal.isEmpty && submittedAttachments.isNotEmpty) {
        setState(() {
          attachmentsInternal = submittedAttachments;
        });
      }
      rethrow;
    }
  }

  Future<List<GatewayChatAttachmentPayload>> buildAttachmentPayloadsInternal(
    List<ComposerAttachmentInternal> attachments,
  ) async {
    final payloads = <GatewayChatAttachmentPayload>[];
    for (final attachment in attachments) {
      final file = File(attachment.path);
      if (!await file.exists()) {
        continue;
      }
      final bytes = await file.readAsBytes();
      final mimeType = attachment.mimeType;
      payloads.add(
        GatewayChatAttachmentPayload(
          type: mimeType.startsWith('image/') ? 'image' : 'file',
          mimeType: mimeType,
          fileName: attachment.name,
          content: base64Encode(bytes),
        ),
      );
    }
    return payloads;
  }

  GatewayAgentSummary? pickAutoAgentInternal(
    AppController controller,
    String prompt,
  ) {
    final text = prompt.toLowerCase();
    final agents = controller.agents;
    if (agents.isEmpty) {
      return null;
    }

    GatewayAgentSummary? byName(String name) {
      for (final agent in agents) {
        if (agent.name.toLowerCase().contains(name)) {
          return agent;
        }
      }
      return null;
    }

    if (text.contains('browser') ||
        text.contains('search') ||
        text.contains('website') ||
        text.contains('网页') ||
        text.contains('爬') ||
        text.contains('抓取')) {
      return byName('browser');
    }

    if (text.contains('research') ||
        text.contains('analyze') ||
        text.contains('compare') ||
        text.contains('summary') ||
        text.contains('研究') ||
        text.contains('分析') ||
        text.contains('调研')) {
      return byName('research');
    }

    if (text.contains('code') ||
        text.contains('deploy') ||
        text.contains('build') ||
        text.contains('test') ||
        text.contains('log') ||
        text.contains('bug') ||
        text.contains('代码') ||
        text.contains('部署') ||
        text.contains('日志')) {
      return byName('coding');
    }

    return byName('coding') ?? byName('browser') ?? byName('research');
  }

  List<ComposerSkillOptionInternal> availableSkillOptionsInternal(
    AppController controller,
  ) {
    if (controller.isSingleAgentMode) {
      return controller
          .assistantImportedSkillsForSession(controller.currentSessionKey)
          .map(skillOptionFromThreadSkillInternal)
          .toList(growable: false);
    }
    final options = <ComposerSkillOptionInternal>[];
    final seenKeys = <String>{};

    void addOption(ComposerSkillOptionInternal option) {
      if (seenKeys.add(option.key)) {
        options.add(option);
      }
    }

    for (final skill in controller.skills) {
      final option = skillOptionFromGatewayInternal(skill);
      addOption(option);
    }

    for (final option in fallbackSkillOptionsInternal) {
      addOption(option);
    }

    return options;
  }

  List<String> selectedSkillKeysForInternal(AppController controller) {
    return controller.assistantSelectedSkillKeysForSession(
      controller.currentSessionKey,
    );
  }

  List<String> resolveSelectedSkillLabelsInternal(AppController controller) {
    final optionsByKey = <String, ComposerSkillOptionInternal>{
      for (final option in availableSkillOptionsInternal(controller))
        option.key: option,
    };
    return selectedSkillKeysForInternal(controller)
        .map((key) => optionsByKey[key]?.label)
        .whereType<String>()
        .toList(growable: false);
  }

  String composePromptInternal({
    required String mode,
    required String prompt,
    required List<String> attachmentNames,
    required List<String> selectedSkillLabels,
    required AssistantExecutionTarget executionTarget,
    required SingleAgentProvider singleAgentProvider,
    required AssistantPermissionLevel permissionLevel,
    required String workspacePath,
  }) {
    final attachmentBlock = attachmentNames.isEmpty
        ? ''
        : 'Attached files:\n${attachmentNames.map((name) => '- $name').join('\n')}\n\n';
    final skillBlock = selectedSkillLabels.isEmpty
        ? ''
        : 'Preferred skills:\n${selectedSkillLabels.map((name) => '- $name').join('\n')}\n\n';
    final targetRoot = workspacePath.trim();
    final executionContext =
        'Execution context:\n'
        '- target: ${executionTarget.promptValue}\n'
        '${executionTarget == AssistantExecutionTarget.singleAgent ? '- provider: ${singleAgentProvider.providerId}\n' : ''}'
        '- workspace_root: ${targetRoot.isEmpty ? 'not-set' : targetRoot}\n'
        '- permission: ${permissionLevel.promptValue}\n\n';

    return switch (mode) {
      'craft' =>
        '$attachmentBlock$skillBlock$executionContext'
            'Craft a polished result for this request:\n$prompt',
      'plan' =>
        '$attachmentBlock$skillBlock$executionContext'
            'Create a clear execution plan for this task:\n$prompt',
      _ => '$attachmentBlock$skillBlock$executionContext$prompt',
    };
  }

  void openGatewaySettingsInternal() {
    widget.controller.openSettings(
      detail: SettingsDetailPage.gatewayConnection,
      navigationContext: SettingsNavigationContext(
        rootLabel: appText('助手', 'Assistant'),
        destination: WorkspaceDestination.assistant,
        sectionLabel: appText('集成', 'Integrations'),
      ),
    );
  }

  Future<void> connectFromSavedSettingsOrShowDialogInternal() async {
    if (!widget.controller.canQuickConnectGateway) {
      openGatewaySettingsInternal();
      return;
    }
    await widget.controller.connectSavedGateway();
  }

  void openAiGatewaySettingsInternal() {
    widget.controller.openSettings(tab: SettingsTab.gateway);
  }

  void focusComposerInternal() {
    if (!mounted) {
      return;
    }
    composerFocusNodeInternal.requestFocus();
  }

  Future<bool> runTaskSessionActionWithRetryInternal(
    String label,
    Future<void> Function() action,
  ) async {
    Object? lastError;
    for (
      var attempt = 1;
      attempt <= assistantTaskActionMaxRetryCountInternal;
      attempt++
    ) {
      try {
        await action();
        return true;
      } catch (error) {
        lastError = error;
        if (attempt >= assistantTaskActionMaxRetryCountInternal) {
          break;
        }
        await Future<void>.delayed(Duration(milliseconds: 240 * attempt));
      }
    }
    if (!mounted) {
      return false;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          appText(
            '$label 失败，弱网环境下已重试 $assistantTaskActionMaxRetryCountInternal 次。',
            '$label failed after $assistantTaskActionMaxRetryCountInternal retries on a weak network.',
          ),
        ),
      ),
    );
    debugPrint('$label failed after retries: $lastError');
    return false;
  }

  Future<void> refreshTasksWithRetryInternal() async {
    await runTaskSessionActionWithRetryInternal(
      appText('刷新任务列表', 'Refresh task list'),
      widget.controller.refreshSessions,
    );
  }

  Future<void> switchSessionWithRetryInternal(String sessionKey) async {
    final switched = await runTaskSessionActionWithRetryInternal(
      appText('切换会话', 'Switch session'),
      () => widget.controller.switchSession(sessionKey),
    );
    if (switched) {
      focusComposerInternal();
    }
  }

  Future<void> createNewThreadInternal() async {
    final sessionKey = buildDraftSessionKeyInternal(widget.controller);
    final inheritedTarget = widget.controller.currentAssistantExecutionTarget;
    final inheritedViewMode = widget.controller.currentAssistantMessageViewMode;
    setState(() {
      archivedTaskKeysInternal.removeWhere(
        (value) => sessionKeysMatchInternal(value, sessionKey),
      );
      taskSeedsInternal[sessionKey] = AssistantTaskSeedInternal(
        sessionKey: sessionKey,
        title: appText('新对话', 'New conversation'),
        preview: appText(
          '等待描述这个任务的第一条消息',
          'Waiting for the first message of this task',
        ),
        status: 'queued',
        updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
        owner: conversationOwnerLabelInternal(widget.controller),
        surface: 'Assistant',
        executionTarget: inheritedTarget,
        draft: true,
      );
    });
    widget.controller.initializeAssistantThreadContext(
      sessionKey,
      title: appText('新对话', 'New conversation'),
      executionTarget: inheritedTarget,
      messageViewMode: inheritedViewMode,
      singleAgentProvider: widget.controller.currentSingleAgentProvider,
    );
    await switchSessionWithRetryInternal(sessionKey);
  }

  List<AssistantTaskEntryInternal> buildTaskEntriesInternal(
    AppController controller,
  ) {
    archivedTaskKeysInternal
      ..clear()
      ..addAll(controller.settings.assistantArchivedTaskKeys);
    synchronizeTaskSeedsInternal(controller);
    final entries =
        taskSeedsInternal.values
            .where((item) => !isArchivedTaskInternal(item.sessionKey))
            .map((item) {
              final isCurrent = sessionKeysMatchInternal(
                item.sessionKey,
                controller.currentSessionKey,
              );
              final entry = item.toEntry(isCurrent: isCurrent);
              if (!isCurrent) {
                return entry;
              }
              return entry.copyWith(
                owner: conversationOwnerLabelInternal(controller),
              );
            })
            .toList(growable: true)
          ..sort((left, right) {
            if (left.isCurrent != right.isCurrent) {
              return left.isCurrent ? -1 : 1;
            }
            return (right.updatedAtMs ?? 0).compareTo(left.updatedAtMs ?? 0);
          });
    return entries;
  }

  List<AssistantTaskEntryInternal> filterTasksInternal(
    List<AssistantTaskEntryInternal> items,
  ) {
    final query = threadQueryInternal.trim().toLowerCase();
    if (query.isEmpty) {
      return items;
    }
    return items
        .where((item) {
          final haystack = '${item.title}\n${item.preview}\n${item.sessionKey}'
              .toLowerCase();
          return haystack.contains(query);
        })
        .toList(growable: false);
  }

  AssistantTaskEntryInternal resolveCurrentTaskInternal(
    List<AssistantTaskEntryInternal> items,
    String sessionKey,
  ) {
    for (final item in items) {
      if (sessionKeysMatchInternal(item.sessionKey, sessionKey)) {
        return item;
      }
    }
    return AssistantTaskEntryInternal(
      sessionKey: sessionKey,
      title: resolvedTaskTitleInternal(widget.controller, sessionKey),
      preview: '',
      status: 'queued',
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
      owner: conversationOwnerLabelInternal(widget.controller),
      surface: 'Assistant',
      executionTarget: widget.controller.currentAssistantExecutionTarget,
      isCurrent: true,
      draft: true,
    );
  }

  void synchronizeTaskSeedsInternal(AppController controller) {
    for (final session in controller.assistantSessions) {
      if (isArchivedTaskInternal(session.key)) {
        continue;
      }
      taskSeedsInternal[session.key] = AssistantTaskSeedInternal(
        sessionKey: session.key,
        title: resolvedTaskTitleInternal(
          controller,
          session.key,
          session: session,
        ),
        preview:
            sessionPreviewInternal(session) ??
            appText('等待继续执行这个任务', 'Waiting to continue this task'),
        status: sessionStatusInternal(
          session,
          sessionPending: controller.assistantSessionHasPendingRun(session.key),
        ),
        updatedAtMs:
            session.updatedAtMs ??
            DateTime.now().millisecondsSinceEpoch.toDouble(),
        owner: conversationOwnerLabelInternal(controller),
        surface: session.surface ?? session.kind ?? 'Assistant',
        executionTarget: controller.assistantExecutionTargetForSession(
          session.key,
        ),
        draft: session.key.trim().startsWith('draft:'),
      );
    }

    final currentSeed = taskSeedsInternal[controller.currentSessionKey];
    final currentPreview = currentTaskPreviewInternal(controller.chatMessages);
    final currentStatus = currentTaskStatusInternal(
      controller.chatMessages,
      controller,
    );

    if (isArchivedTaskInternal(controller.currentSessionKey)) {
      return;
    }
    taskSeedsInternal[controller.currentSessionKey] = AssistantTaskSeedInternal(
      sessionKey: controller.currentSessionKey,
      title: resolvedTaskTitleInternal(
        controller,
        controller.currentSessionKey,
        fallbackTitle: currentSeed?.title,
      ),
      preview:
          currentPreview ??
          currentSeed?.preview ??
          appText(
            '等待描述这个任务的第一条消息',
            'Waiting for the first message of this task',
          ),
      status: currentStatus ?? currentSeed?.status ?? 'queued',
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
      owner: conversationOwnerLabelInternal(controller),
      surface: currentSeed?.surface ?? 'Assistant',
      executionTarget: controller.assistantExecutionTargetForSession(
        controller.currentSessionKey,
      ),
      draft: controller.currentSessionKey.trim().startsWith('draft:'),
    );
  }

  GatewaySessionSummary? sessionByKeyInternal(
    AppController controller,
    String sessionKey,
  ) {
    for (final session in controller.assistantSessions) {
      if (sessionKeysMatchInternal(session.key, sessionKey)) {
        return session;
      }
    }
    return null;
  }

  String resolvedTaskTitleInternal(
    AppController controller,
    String sessionKey, {
    GatewaySessionSummary? session,
    String? fallbackTitle,
  }) {
    final customTitle = controller.assistantCustomTaskTitle(sessionKey);
    if (customTitle.isNotEmpty) {
      return customTitle;
    }
    final resolvedSession =
        session ?? sessionByKeyInternal(controller, sessionKey);
    if (resolvedSession != null) {
      return sessionDisplayTitleInternal(resolvedSession);
    }
    final fallback = fallbackTitle?.trim() ?? '';
    if (fallback.isNotEmpty) {
      return fallback;
    }
    return fallbackSessionTitleInternal(sessionKey);
  }

  String defaultTaskTitleInternal(
    AppController controller,
    String sessionKey, {
    GatewaySessionSummary? session,
  }) {
    final resolvedSession =
        session ?? sessionByKeyInternal(controller, sessionKey);
    if (resolvedSession != null) {
      return sessionDisplayTitleInternal(resolvedSession);
    }
    return fallbackSessionTitleInternal(sessionKey);
  }

  void touchTaskSeedInternal({
    required String sessionKey,
    required String title,
    required String preview,
    required String status,
    required String owner,
    required String surface,
    required AssistantExecutionTarget executionTarget,
    required bool draft,
  }) {
    taskSeedsInternal[sessionKey] = AssistantTaskSeedInternal(
      sessionKey: sessionKey,
      title: title,
      preview: preview,
      status: status,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
      owner: owner,
      surface: surface,
      executionTarget: executionTarget,
      draft: draft,
    );
  }

  bool isArchivedTaskInternal(String sessionKey) {
    for (final archivedKey in archivedTaskKeysInternal) {
      if (sessionKeysMatchInternal(archivedKey, sessionKey)) {
        return true;
      }
    }
    return false;
  }

  Future<void> archiveTaskInternal(String sessionKey) async {
    final isCurrent = sessionKeysMatchInternal(
      sessionKey,
      widget.controller.currentSessionKey,
    );
    if (widget.controller.assistantSessionHasPendingRun(sessionKey)) {
      return;
    }
    final archived = await runTaskSessionActionWithRetryInternal(
      appText('归档任务', 'Archive task'),
      () => widget.controller.saveAssistantTaskArchived(sessionKey, true),
    );
    if (!archived) {
      return;
    }
    setState(() {
      archivedTaskKeysInternal.add(sessionKey);
      taskSeedsInternal.removeWhere(
        (key, _) => sessionKeysMatchInternal(key, sessionKey),
      );
    });

    if (!isCurrent) {
      return;
    }

    for (final candidate in taskSeedsInternal.keys) {
      if (isArchivedTaskInternal(candidate) ||
          sessionKeysMatchInternal(candidate, sessionKey)) {
        continue;
      }
      await switchSessionWithRetryInternal(candidate);
      return;
    }

    await createNewThreadInternal();
  }

  Future<void> renameTaskInternal(AssistantTaskEntryInternal entry) async {
    final controller = widget.controller;
    final input = TextEditingController(text: entry.title);
    final renamed = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(appText('重命名任务', 'Rename task')),
          content: TextField(
            key: const Key('assistant-task-rename-input'),
            controller: input,
            autofocus: true,
            maxLines: 1,
            decoration: InputDecoration(
              labelText: appText('任务名称', 'Task name'),
              hintText: appText(
                '留空后恢复默认名称',
                'Leave empty to restore the default title',
              ),
            ),
            onSubmitted: (value) => Navigator.of(context).pop(value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(appText('取消', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(input.text),
              child: Text(appText('保存', 'Save')),
            ),
          ],
        );
      },
    );
    if (!mounted || renamed == null) {
      return;
    }
    final normalized = renamed.trim();
    final nextTitle = normalized.isNotEmpty
        ? normalized
        : defaultTaskTitleInternal(controller, entry.sessionKey);
    final saved = await runTaskSessionActionWithRetryInternal(
      appText('重命名任务', 'Rename task'),
      () => controller.saveAssistantTaskTitle(entry.sessionKey, normalized),
    );
    if (!saved) {
      return;
    }
    setState(() {
      final existing = taskSeedsInternal[entry.sessionKey];
      if (existing != null) {
        taskSeedsInternal[entry.sessionKey] = AssistantTaskSeedInternal(
          sessionKey: existing.sessionKey,
          title: nextTitle,
          preview: existing.preview,
          status: existing.status,
          updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
          owner: existing.owner,
          surface: existing.surface,
          executionTarget: existing.executionTarget,
          draft: existing.draft,
        );
      }
    });
  }

  String buildDraftSessionKeyInternal(AppController controller) {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    if (controller.isSingleAgentMode) {
      return 'draft:$stamp';
    }
    final selectedAgentId = controller.selectedAgentId.trim();
    if (selectedAgentId.isEmpty) {
      return 'draft:$stamp';
    }
    return 'draft:$selectedAgentId:$stamp';
  }

  AssistantFocusEntry? resolveFocusedDestinationInternal(
    List<AssistantFocusEntry> favorites,
  ) {
    if (favorites.isEmpty) {
      return null;
    }
    if (activeFocusedDestinationInternal != null &&
        favorites.contains(activeFocusedDestinationInternal)) {
      return activeFocusedDestinationInternal;
    }
    return favorites.first;
  }

  double resolveMaxSidePaneWidthInternal(double viewportWidth) {
    final maxWidthByViewport =
        viewportWidth -
        mainWorkspaceMinWidthInternal -
        sidePaneViewportPaddingInternal -
        assistantHorizontalResizeHandleWidthInternal -
        assistantHorizontalPaneGapInternal;
    return maxWidthByViewport
        .clamp(
          sidePaneMinWidthInternal,
          viewportWidth - sidePaneViewportPaddingInternal,
        )
        .toDouble();
  }

  String conversationOwnerLabelInternal(AppController controller) {
    return controller.assistantConversationOwnerLabel;
  }

  String? currentTaskPreviewInternal(List<GatewayChatMessage> messages) {
    for (final message in messages.reversed) {
      final text = message.text.trim();
      if (text.isNotEmpty) {
        return text;
      }
    }
    return null;
  }

  String? currentTaskStatusInternal(
    List<GatewayChatMessage> messages,
    AppController controller,
  ) {
    if (controller.hasAssistantPendingRun) {
      return 'running';
    }
    if (messages.isEmpty) {
      return null;
    }
    final last = messages.last;
    if (last.error) {
      return 'failed';
    }
    if (last.role.trim().toLowerCase() == 'user') {
      return 'queued';
    }
    return 'open';
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
