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
import 'package:super_clipboard/super_clipboard.dart';
import '../../app/app_controller.dart';
import '../../app/app_metadata.dart';
import '../../app/ui_feature_manifest.dart';
import '../../i18n/app_language.dart';
import '../../models/app_models.dart';
import '../../runtime/multi_agent_orchestrator.dart';
import '../../runtime/gateway_acp_client.dart';
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
import 'assistant_page_composer_skill_models.dart';
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
              itemCount: AssistantPageStateActionsInternal(
                this,
              ).selectedSkillKeysForInternal(controller).length,
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
          runtimeBudgetMinutes:
              thread?.openClawTaskAssociation?.runtimeBudgetMinutes ?? 10,
        );

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
                    messageViewMode: controller
                        .assistantMessageViewModeForSession(activeSessionKey),
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
                    onOpenAiGatewaySettings: AssistantPageStateActionsInternal(
                      this,
                    ).openAiGatewaySettingsInternal,
                    onReconnectGateway: AssistantPageStateActionsInternal(
                      this,
                    ).connectFromSavedSettingsOrShowDialogInternal,
                    onMessageViewModeChanged:
                        controller.setAssistantMessageViewMode,
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
                  onComposerContentHeightChanged:
                      handleComposerContentHeightChangedInternal,
                  onComposerInputHeightChanged:
                      handleComposerInputHeightChangedInternal,
                  onSend: AssistantPageStateActionsInternal(
                    this,
                  ).submitPromptInternal,
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
        final palette = context.palette;
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
        final panel = Row(
          children: [
            Expanded(child: child),
            if (!artifactPaneCollapsedInternal) ...[
              DecoratedBox(
                decoration: BoxDecoration(color: palette.chromeBackground),
                child: SizedBox(
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
              ),
              const SizedBox(width: assistantHorizontalPaneGapInternal),
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
                        .assistantWorkspacePathForSession(activeSessionKey)
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
                    if (Platform.isMacOS) {
                      await Process.run('open', <String>['-R', targetPath]);
                      return;
                    }
                    if (Platform.isLinux) {
                      await Process.run('xdg-open', <String>[
                        File(targetPath).parent.path,
                      ]);
                      return;
                    }
                    if (Platform.isWindows) {
                      await Process.run('explorer.exe', <String>[
                        '/select,$targetPath',
                      ]);
                    }
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
            if (artifactPaneCollapsedInternal)
              Positioned(
                right: 10,
                top: 10,
                child: SizedBox(
                  height: 40,
                  child: Center(
                    child: AssistantArtifactSidebarRevealButton(
                      onTap: () {
                        setState(() {
                          artifactPaneCollapsedInternal = false;
                        });
                      },
                    ),
                  ),
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
