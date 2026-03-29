// ignore_for_file: unused_import, unnecessary_import

import 'dart:convert';
import 'dart:math' as math;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import '../app/app_controller_web.dart';
import '../app/ui_feature_manifest.dart';
import '../i18n/app_language.dart';
import '../models/app_models.dart';
import '../runtime/runtime_models.dart';
import '../theme/app_palette.dart';
import '../widgets/assistant_artifact_sidebar.dart';
import '../widgets/desktop_workspace_scaffold.dart';
import '../widgets/pane_resize_handle.dart';
import '../widgets/surface_card.dart';
import 'web_focus_panel.dart';
import 'web_assistant_page_chrome.dart';
import 'web_assistant_page_workspace.dart';
import 'web_assistant_page_helpers.dart';

const double webAssistantSideTabRailWidthInternal = 46;
const double webAssistantSidePaneMinWidthInternal = 304;
const double webAssistantSidePaneMaxWidthInternal = 420;
const double webAssistantMainWorkspaceMinWidthInternal = 700;
const double webAssistantComposerMinHeightInternal = 164;
const double webAssistantConversationMinHeightInternal = 200;
const double webAssistantResizeHandleSizeInternal = 10;
const double webAssistantArtifactPaneMinWidthInternal = 280;
const double webAssistantArtifactPaneDefaultWidthInternal = 360;

class WebAssistantPage extends StatefulWidget {
  const WebAssistantPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<WebAssistantPage> createState() => WebAssistantPageStateInternal();
}

enum WebAssistantPaneInternal { tasks, quick }

class WebAssistantPageStateInternal extends State<WebAssistantPage> {
  final TextEditingController inputControllerInternal = TextEditingController();
  final TextEditingController searchControllerInternal =
      TextEditingController();
  final ScrollController scrollControllerInternal = ScrollController();

  String queryInternal = '';
  String thinkingLevelInternal = 'medium';
  AssistantPermissionLevel permissionLevelInternal =
      AssistantPermissionLevel.defaultAccess;
  bool useMultiAgentInternal = false;
  bool workspaceChromeCollapsedInternal = false;
  bool sidePaneCollapsedInternal = false;
  double sidePaneWidthInternal = 344;
  bool artifactPaneCollapsedInternal = true;
  double artifactPaneWidthInternal =
      webAssistantArtifactPaneDefaultWidthInternal;
  double composerHeightInternal = 196;
  WebAssistantPaneInternal activePaneInternal = WebAssistantPaneInternal.tasks;
  final List<WebComposerAttachmentInternal> attachmentsInternal =
      <WebComposerAttachmentInternal>[];

  @override
  void dispose() {
    inputControllerInternal.dispose();
    searchControllerInternal.dispose();
    scrollControllerInternal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final currentMessages = controller.chatMessages;
        final connectionState = controller.currentAssistantConnectionState;

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !scrollControllerInternal.hasClients) {
            return;
          }
          scrollControllerInternal.animateTo(
            scrollControllerInternal.position.maxScrollExtent,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
          );
        });

        return DesktopWorkspaceScaffold(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxSidePaneWidth = math.min(
                webAssistantSidePaneMaxWidthInternal,
                math.max(
                  webAssistantSidePaneMinWidthInternal,
                  constraints.maxWidth -
                      webAssistantMainWorkspaceMinWidthInternal,
                ),
              );
              final sidePaneWidth = sidePaneWidthInternal.clamp(
                webAssistantSidePaneMinWidthInternal,
                maxSidePaneWidth,
              );
              final collapsedWidth = webAssistantSideTabRailWidthInternal;

              return Column(
                children: [
                  AssistantWorkspaceChromeInternal(
                    controller: controller,
                    collapsed: workspaceChromeCollapsedInternal,
                    onToggleCollapsed: () {
                      setState(() {
                        workspaceChromeCollapsedInternal =
                            !workspaceChromeCollapsedInternal;
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Row(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          width: sidePaneCollapsedInternal
                              ? collapsedWidth
                              : sidePaneWidth,
                          child: AssistantSidePaneInternal(
                            collapsed: sidePaneCollapsedInternal,
                            activePane: activePaneInternal,
                            controller: controller,
                            query: queryInternal,
                            searchController: searchControllerInternal,
                            permissionLevel: permissionLevelInternal,
                            onQueryChanged: (value) {
                              setState(
                                () =>
                                    queryInternal = value.trim().toLowerCase(),
                              );
                            },
                            onClearQuery: () {
                              searchControllerInternal.clear();
                              setState(() => queryInternal = '');
                            },
                            onToggleCollapsed: () {
                              setState(() {
                                sidePaneCollapsedInternal =
                                    !sidePaneCollapsedInternal;
                              });
                            },
                            onPaneChanged: (pane) {
                              setState(() {
                                activePaneInternal = pane;
                                sidePaneCollapsedInternal = false;
                              });
                            },
                            onPermissionChanged: (value) {
                              setState(() => permissionLevelInternal = value);
                            },
                            onRename: renameConversationInternal,
                            onArchive: (sessionKey) => controller
                                .saveAssistantTaskArchived(sessionKey, true),
                            onOpenActions: openConversationActionsInternal,
                          ),
                        ),
                        if (!sidePaneCollapsedInternal)
                          SizedBox(
                            width: 8,
                            child: PaneResizeHandle(
                              axis: Axis.horizontal,
                              onDelta: (delta) {
                                setState(() {
                                  sidePaneWidthInternal =
                                      (sidePaneWidthInternal + delta)
                                          .clamp(
                                            webAssistantSidePaneMinWidthInternal,
                                            maxSidePaneWidth,
                                          )
                                          .toDouble();
                                });
                              },
                            ),
                          ),
                        Expanded(
                          child: buildWorkspaceWithArtifactsInternal(
                            controller: controller,
                            child: ConversationWorkspaceInternal(
                              controller: controller,
                              scrollController: scrollControllerInternal,
                              inputController: inputControllerInternal,
                              currentMessages: currentMessages,
                              connectionState: connectionState,
                              thinkingLevel: thinkingLevelInternal,
                              permissionLevel: permissionLevelInternal,
                              useMultiAgent: useMultiAgentInternal,
                              attachments: attachmentsInternal,
                              composerHeight: composerHeightInternal,
                              onComposerHeightChanged: (value) {
                                setState(() => composerHeightInternal = value);
                              },
                              onThinkingChanged: (value) {
                                setState(() => thinkingLevelInternal = value);
                              },
                              onPermissionChanged: (value) {
                                setState(() => permissionLevelInternal = value);
                              },
                              onToggleMultiAgent: (value) {
                                setState(() => useMultiAgentInternal = value);
                              },
                              onAddAttachment: pickAttachmentsInternal,
                              onRemoveAttachment: (index) {
                                setState(
                                  () => attachmentsInternal.removeAt(index),
                                );
                              },
                              onOpenSessionSettings:
                                  openSessionSettingsInternal,
                              onSubmit: submitPromptInternal,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Future<void> openSessionSettingsInternal() async {
    if (!mounted) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return AssistantSessionSettingsSheetInternal(
          controller: widget.controller,
          thinkingLevel: thinkingLevelInternal,
          permissionLevel: permissionLevelInternal,
          onThinkingChanged: (value) {
            setState(() => thinkingLevelInternal = value);
          },
          onPermissionChanged: (value) {
            setState(() => permissionLevelInternal = value);
          },
        );
      },
    );
  }

  Future<void> openConversationActionsInternal(String sessionKey) async {
    final controller = widget.controller;
    if (!mounted) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.drive_file_rename_outline_rounded),
                title: Text(appText('重命名', 'Rename')),
                onTap: () {
                  Navigator.of(context).pop();
                  renameConversationInternal(sessionKey);
                },
              ),
              ListTile(
                leading: const Icon(Icons.archive_outlined),
                title: Text(appText('归档', 'Archive')),
                onTap: () async {
                  Navigator.of(context).pop();
                  await controller.saveAssistantTaskArchived(sessionKey, true);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> renameConversationInternal(String sessionKey) async {
    final controller = widget.controller;
    final initial = controller.conversations
        .firstWhere(
          (item) => item.sessionKey == sessionKey,
          orElse: () => WebConversationSummary(
            sessionKey: sessionKey,
            title: '',
            preview: '',
            updatedAtMs: 0,
            executionTarget: AssistantExecutionTarget.singleAgent,
            pending: false,
            current: false,
          ),
        )
        .title;
    final renameController = TextEditingController(text: initial);
    final value = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            0,
            16,
            MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                appText('重命名任务线程', 'Rename task thread'),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: renameController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: appText('输入标题', 'Enter a title'),
                ),
                onSubmitted: (value) => Navigator.of(context).pop(value),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(appText('取消', 'Cancel')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () =>
                          Navigator.of(context).pop(renameController.text),
                      child: Text(appText('保存', 'Save')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
    renameController.dispose();
    if (value == null) {
      return;
    }
    await controller.saveAssistantTaskTitle(sessionKey, value);
  }

  Future<void> pickAttachmentsInternal() async {
    final controller = widget.controller;
    final uiFeatures = controller.featuresFor(UiFeaturePlatform.web);
    if (!uiFeatures.supportsFileAttachments) {
      return;
    }
    final files = await openFiles(
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(
          label: 'Images',
          extensions: <String>['png', 'jpg', 'jpeg', 'gif', 'webp'],
        ),
        XTypeGroup(
          label: 'Documents',
          extensions: <String>[
            'txt',
            'md',
            'json',
            'csv',
            'pdf',
            'yaml',
            'yml',
          ],
        ),
      ],
    );
    if (!mounted || files.isEmpty) {
      return;
    }
    setState(() {
      attachmentsInternal.addAll(
        files.map(WebComposerAttachmentInternal.fromXFile),
      );
    });
  }

  Future<void> submitPromptInternal() async {
    final controller = widget.controller;
    final value = inputControllerInternal.text.trim();
    if (value.isEmpty) {
      return;
    }

    final payloads = <GatewayChatAttachmentPayload>[];
    for (final attachment in attachmentsInternal) {
      final bytes = await attachment.file.readAsBytes();
      payloads.add(
        GatewayChatAttachmentPayload(
          type: attachment.mimeType.startsWith('image/') ? 'image' : 'file',
          mimeType: attachment.mimeType,
          fileName: attachment.name,
          content: base64Encode(bytes),
        ),
      );
    }

    final selectedSkillLabels = controller
        .assistantImportedSkillsForSession(controller.currentSessionKey)
        .where(
          (item) => controller
              .assistantSelectedSkillKeysForSession(
                controller.currentSessionKey,
              )
              .contains(item.key),
        )
        .map((item) => item.label)
        .where((item) => item.trim().isNotEmpty)
        .toList(growable: false);

    await controller.sendMessage(
      value,
      thinking: thinkingLevelInternal,
      attachments: payloads,
      selectedSkillLabels: selectedSkillLabels,
      useMultiAgent: useMultiAgentInternal,
    );

    if (!mounted) {
      return;
    }
    inputControllerInternal.clear();
    setState(() => attachmentsInternal.clear());
  }

  Widget buildWorkspaceWithArtifactsInternal({
    required AppController controller,
    required Widget child,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxPaneWidth = math.min(
          520.0,
          math.max(
            webAssistantArtifactPaneMinWidthInternal,
            constraints.maxWidth * 0.48,
          ),
        );
        final paneWidth = artifactPaneWidthInternal
            .clamp(webAssistantArtifactPaneMinWidthInternal, maxPaneWidth)
            .toDouble();
        final workspace = Row(
          children: [
            Expanded(child: child),
            if (!artifactPaneCollapsedInternal) ...[
              SizedBox(
                key: const Key('assistant-artifact-pane-resize-handle'),
                width: 8,
                child: PaneResizeHandle(
                  axis: Axis.horizontal,
                  onDelta: (delta) {
                    setState(() {
                      artifactPaneWidthInternal =
                          (artifactPaneWidthInternal - delta)
                              .clamp(
                                webAssistantArtifactPaneMinWidthInternal,
                                maxPaneWidth,
                              )
                              .toDouble();
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: paneWidth,
                child: AssistantArtifactSidebar(
                  sessionKey: controller.currentSessionKey,
                  threadTitle: controller.currentConversationTitle,
                  workspaceRef: controller
                      .assistantWorkspaceDisplayPathForSession(
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
                  onOpenWorkspace: null,
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
            Positioned.fill(child: workspace),
            if (artifactPaneCollapsedInternal)
              Positioned(
                right: 8,
                top: 12,
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
}
