// ignore_for_file: unused_import, unnecessary_import, invalid_use_of_protected_member

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
import '../../app/app_controller.dart';
import '../../app/app_metadata.dart';
import '../../app/ui_feature_manifest.dart';
import '../../i18n/app_language.dart';
import '../../models/app_models.dart';
import '../../runtime/gateway_acp_client.dart';
import '../../runtime/local_file_revealer.dart';
import '../../runtime/runtime_models.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../widgets/assistant_focus_panel.dart';
import '../../widgets/assistant_artifact_sidebar.dart';
import '../../widgets/assistant_task_progress_bar.dart';
import '../../widgets/desktop_workspace_scaffold.dart';
import '../../widgets/pane_resize_handle.dart';
import '../../widgets/surface_card.dart';
import 'assistant_page_main.dart';
import 'assistant_page_components.dart';
import 'assistant_page_composer_bar.dart';
import 'assistant_page_composer_state_helpers.dart';
import 'assistant_page_composer_support.dart';
import 'assistant_page_tooltip_labels.dart';
import 'assistant_page_message_widgets.dart';
import 'assistant_page_task_models.dart';
import 'assistant_page_composer_skill_picker.dart';
import 'assistant_page_composer_clipboard.dart';
import 'assistant_page_components_core.dart';
import 'assistant_page_state_actions.dart';

extension AssistantPageStateClosureInternal on AssistantPageStateInternal {
  Widget buildMainWorkspaceInternal({
    required AppController controller,
    required List<TimelineItemInternal> timelineItems,
    required AssistantTaskEntryInternal currentTask,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
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
        // The transcript/composer boundary is overlaid on the seam like every
        // other pane boundary, so it reserves no height of its own.
        final availableWorkspaceHeight = math.max(0.0, constraints.maxHeight);
        final attachmentExtraHeight =
            estimatedComposerWrapSectionHeightInternal(
              itemCount: attachmentsInternal.length,
              availableWidth: composerContentWidth,
              averageChipWidth: 168,
            );
        final selectedSkillExtraHeight =
            estimatedComposerWrapSectionHeightInternal(
              itemCount: AssistantPageStateActionsInternal(
                this,
              ).selectedSkillKeysForInternal(controller).length,
              availableWidth: composerContentWidth,
              averageChipWidth: 132,
            );
        // The composer's minimum: toolbars, chips and a one-line writing area.
        // This is computed, never measured back from the rendered card — the
        // card now fills the pane, so measuring it would feed the pane's own
        // height into the height that sizes the pane, growing it every frame.
        final minComposerContentHeight =
            baseComposerHeight +
            attachmentExtraHeight +
            selectedSkillExtraHeight;
        final defaultComposerHeight = math.min(
          availableWorkspaceHeight,
          minComposerContentHeight + composerBottomSpacing,
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
          math.max(
                assistantWorkspaceMinLowerPaneHeightInternal,
                minComposerContentHeight,
              ) +
              composerBottomSpacing,
          composerHeightUpperBound,
        );
        final composerHeight =
            (defaultComposerHeight + workspaceLowerPaneHeightAdjustmentInternal)
                .clamp(composerHeightLowerBound, composerHeightUpperBound)
                .toDouble();
        // In focused mode the conversation canvas becomes full-width, but the
        // composer keeps the same work-column geometry it has with the global
        // navigation (336px) and artifact pane (360px) open. This prevents the
        // input surface from jumping wide when both sidebars are hidden.
        final useFocusedComposerGeometry =
            controller.sidebarState == AppSidebarState.hidden &&
            artifactPaneCollapsedInternal &&
            constraints.maxWidth >=
                assistantFocusedComposerLeftInsetInternal +
                    assistantFocusedComposerRightInsetInternal +
                    assistantFocusedComposerMinWidthInternal;
        final composerHorizontalInsets = useFocusedComposerGeometry
            ? const EdgeInsets.only(
                left: assistantFocusedComposerLeftInsetInternal,
                right: assistantFocusedComposerRightInsetInternal,
              )
            : EdgeInsets.zero;
        final activeSessionKey = currentTask.sessionKey.trim().isEmpty
            ? controller.currentSessionKey
            : currentTask.sessionKey.trim();
        final thread = controller.taskThreadForSessionInternal(
          activeSessionKey,
        );
        final progressState = assistantTaskProgressState(
          pending: controller.assistantSessionHasPendingRun(activeSessionKey),
          lifecycleStatus: thread?.lifecycleState.status ?? '',
          lastResultCode: thread?.lifecycleState.lastResultCode ?? '',
          artifactSyncStatus: thread?.lastArtifactSyncStatus ?? '',
        );

        return SurfaceCard(
          borderRadius: 0,
          padding: EdgeInsets.zero,
          tone: SurfaceCardTone.chrome,
          child: Stack(
            children: [
              Positioned.fill(
                child: Column(
                  children: [
                    Expanded(
                      child: KeyedSubtree(
                        key: const Key('assistant-conversation-shell'),
                        child: ConversationAreaInternal(
                          controller: controller,
                          currentTask: currentTask,
                          items: timelineItems,
                          messageViewMode: controller
                              .assistantMessageViewModeForSession(
                                activeSessionKey,
                              ),
                          bottomContentInset: composerBottomSpacing,
                          topTrailingInset: artifactPaneCollapsedInternal
                              ? assistantCollapsedArtifactToggleClearanceInternal
                              : 0,
                          scrollController: conversationControllerInternal,
                          onOpenDetail: widget.onOpenDetail,
                          onFocusComposer: AssistantPageStateActionsInternal(
                            this,
                          ).focusComposerInternal,
                          onOpenGateway: AssistantPageStateActionsInternal(
                            this,
                          ).openGatewaySettingsInternal,
                          onOpenAiGatewaySettings:
                              AssistantPageStateActionsInternal(
                                this,
                              ).openAiGatewaySettingsInternal,
                          onReconnectGateway: AssistantPageStateActionsInternal(
                            this,
                          ).connectFromSavedSettingsOrShowDialogInternal,
                          onMessageViewModeChanged:
                              controller.setAssistantMessageViewMode,
                          onRecallUserMessage:
                              AssistantPageStateActionsInternal(
                                this,
                              ).recallUserMessageInternal,
                          onEditUserMessage: AssistantPageStateActionsInternal(
                            this,
                          ).editUserMessageInternal,
                          onRunConversationWorkflow:
                              AssistantPageStateActionsInternal(
                                this,
                              ).runConversationWorkflowInternal,
                          workflowSupported: controller
                              .featuresFor(
                                resolveUiFeaturePlatformFromContext(context),
                              )
                              .supportsGitHubRepository,
                          workflowEnabled:
                              controller.canRunConversationWorkflow,
                          workflowRunning: publishingConversationInternal,
                        ),
                      ),
                    ),
                    AssistantTaskProgressBar(
                      state: progressState,
                      onStop: progressState.running
                          ? () {
                              unawaited(controller.abortRun());
                            }
                          : null,
                      onContinue: progressState.recoverable
                          ? () {
                              unawaited(
                                AssistantPageStateActionsInternal(
                                  this,
                                ).continueCurrentTaskInternal(activeSessionKey),
                              );
                            }
                          : null,
                    ),
                    SizedBox(
                      key: const Key('assistant-composer-shell'),
                      height: composerHeight,
                      child: AssistantLowerPaneInternal(
                        bottomContentInset: composerBottomSpacing,
                        horizontalContentInsets: composerHorizontalInsets,
                        inputController: inputControllerInternal,
                        focusNode: composerFocusNodeInternal,
                        thinkingLabel: thinkingLabelInternal,
                        showModelControl: true,
                        modelLabel: controller.assistantDisplayModelForSession(
                          activeSessionKey,
                        ),
                        modelOptions: controller.assistantModelChoices,
                        attachments: attachmentsInternal,
                        availableSkills: AssistantPageStateActionsInternal(
                          this,
                        ).availableSkillOptionsInternal(controller),
                        selectedSkillKeys: AssistantPageStateActionsInternal(
                          this,
                        ).selectedSkillKeysForInternal(controller),
                        controller: controller,
                        onRemoveAttachment: (attachment) {
                          setState(() {
                            attachmentsInternal = attachmentsInternal
                                .where((item) => item.path != attachment.path)
                                .toList(growable: false);
                            saveComposerAttachmentsForSessionInternal(
                              activeSessionKey,
                            );
                          });
                        },
                        onToggleSkill: (key) {
                          unawaited(
                            controller.toggleAssistantSkillForSession(
                              activeSessionKey,
                              key,
                            ),
                          );
                          AssistantPageStateActionsInternal(
                            this,
                          ).focusComposerInternal();
                        },
                        onThinkingChanged: (value) {
                          setState(() => thinkingLabelInternal = value);
                        },
                        onModelChanged: (modelId) =>
                            controller.selectAssistantModelForSession(
                              activeSessionKey,
                              modelId,
                            ),
                        onPickAttachments: AssistantPageStateActionsInternal(
                          this,
                        ).pickAttachmentsInternal,
                        onAddAttachment: (attachment) {
                          setState(() {
                            attachmentsInternal = [
                              ...attachmentsInternal,
                              attachment,
                            ];
                            saveComposerAttachmentsForSessionInternal(
                              activeSessionKey,
                            );
                          });
                        },
                        onPasteImageAttachment:
                            widget.clipboardImageReader ??
                            readClipboardImageAsXFileInternal,
                        onSend: AssistantPageStateActionsInternal(
                          this,
                        ).submitPromptInternal,
                      ),
                    ),
                  ],
                ),
              ),
              // Same grammar as every other pane boundary: overlaid on the
              // seam, so the transcript and the composer stay flush and the
              // divider costs no layout height. Dragging it is the single
              // control over the composer's height.
              Positioned(
                key: const Key('assistant-workspace-resize-handle'),
                left: 0,
                right: 0,
                bottom: composerHeight - PaneResizeHandle.defaultHitExtent / 2,
                height: PaneResizeHandle.defaultHitExtent,
                child: PaneResizeHandle(
                  axis: Axis.vertical,
                  // Persist once the gesture settles, not on every move.
                  onDragEnd: () => unawaited(
                    controller.saveAssistantComposerHeightAdjustment(
                      workspaceLowerPaneHeightAdjustmentInternal,
                    ),
                  ),
                  onDelta: (delta) {
                    // Capture before the layout changes: whether the reader was
                    // at the newest message decides whether the transcript
                    // follows the composer or holds its place.
                    final wasAtBottom = conversationIsAtBottomInternal;
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
                    if (wasAtBottom) {
                      pinConversationToBottomInternal();
                    }
                  },
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
        final activeSessionKey = currentTask.sessionKey.trim().isEmpty
            ? controller.currentSessionKey
            : currentTask.sessionKey.trim();
        final activeThread = controller.taskThreadForSessionInternal(
          activeSessionKey,
        );
        final panel = Row(
          children: [
            Expanded(child: child),
            if (!artifactPaneCollapsedInternal) ...[
              SizedBox(
                width: paneWidth,
                child: AssistantArtifactSidebar(
                  sessionKey: activeSessionKey,
                  threadTitle: currentTask.title,
                  workspacePath: controller
                      .assistantWorkspaceDisplayPathForSession(
                        activeSessionKey,
                      ),
                  workspaceKind: controller.assistantWorkspaceKindForSession(
                    activeSessionKey,
                  ),
                  artifactSyncAtMs: controller
                      .assistantArtifactSyncAtMsForSession(activeSessionKey),
                  artifactSyncStatus: controller
                      .assistantArtifactSyncStatusForSession(activeSessionKey),
                  taskContextMessageCount: activeThread?.messages.length ?? 0,
                  taskContextSelectedSkillKeys:
                      activeThread?.selectedSkillKeys ?? const <String>[],
                  taskContextRemoteWorkingDirectory:
                      activeThread?.lastRemoteWorkingDirectory ?? '',
                  taskContextOpenClawRunId:
                      activeThread?.openClawTaskAssociation?.runId ?? '',
                  taskContextOpenClawStatus:
                      activeThread?.openClawTaskAssociation?.status ?? '',
                  onCollapse: () {
                    setState(() {
                      artifactPaneCollapsedInternal = true;
                    });
                  },
                  onOpenWorkspace: () async {
                    final workspacePath = controller
                        .assistantWorkspacePathForSession(activeSessionKey)
                        .trim();
                    if (workspacePath.isEmpty) {
                      return;
                    }
                    if (Platform.isMacOS) {
                      await Process.run('open', <String>[workspacePath]);
                      return;
                    }
                    if (Platform.isLinux) {
                      await Process.run('xdg-open', <String>[workspacePath]);
                      return;
                    }
                    if (Platform.isWindows) {
                      await Process.run('explorer.exe', <String>[
                        workspacePath,
                      ]);
                    }
                  },
                  onOpenEntryLocation: (entry) async {
                    final workspacePath = controller
                        .assistantArtifactWorkspacePathForEntry(
                          entry,
                          sessionKey: activeSessionKey,
                        )
                        .trim();
                    if (workspacePath.isEmpty) {
                      return;
                    }
                    final targetPath =
                        entry.relativePath.startsWith('/') ||
                            entry.relativePath.startsWith('\\') ||
                            entry.relativePath.contains(':\\')
                        ? entry.relativePath
                        : '${workspacePath.replaceAll(RegExp(r'[\\/]+$'), '')}${Platform.pathSeparator}${entry.relativePath}';
                    await revealLocalFile(targetPath);
                  },
                  loadSnapshot: () => controller.loadAssistantArtifactSnapshot(
                    sessionKey: activeSessionKey,
                  ),
                  loadPreview: (entry) =>
                      controller.loadAssistantArtifactPreview(
                        entry,
                        sessionKey: activeSessionKey,
                      ),
                ),
              ),
            ],
          ],
        );
        return Stack(
          children: [
            Positioned.fill(child: panel),
            if (!artifactPaneCollapsedInternal)
              Positioned(
                key: const Key('assistant-artifact-pane-resize-handle'),
                right: paneWidth - PaneResizeHandle.defaultHitExtent / 2,
                top: 0,
                bottom: 0,
                width: PaneResizeHandle.defaultHitExtent,
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
            if (artifactPaneCollapsedInternal)
              Positioned(
                right: 12,
                top: 12,
                child: SizedBox(
                  child: AssistantArtifactSidebarRevealButton(
                    onTap: () {
                      setState(() {
                        artifactPaneCollapsedInternal = false;
                      });
                    },
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  List<TimelineItemInternal> buildTimelineItemsInternal(
    AppController controller,
    List<GatewayChatMessage> messages,
  ) {
    final items = <TimelineItemInternal>[];
    final ownerLabel = AssistantPageStateActionsInternal(
      this,
    ).conversationOwnerLabelInternal(controller);

    for (final message in messages) {
      if ((message.toolName ?? '').trim().isNotEmpty) {
        items.add(
          TimelineItemInternal.toolCall(
            key: timelineItemKeyInternal(message),
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
            key: timelineItemKeyInternal(message),
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
            key: timelineItemKeyInternal(message),
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
            key: timelineItemKeyInternal(message),
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

  String timelineItemKeyInternal(GatewayChatMessage message) {
    final id = message.id.trim();
    if (id.isNotEmpty) {
      return id;
    }
    return '${message.role}:${message.timestampMs}:${message.text.hashCode}';
  }
}
