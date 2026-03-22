import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

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
import '../../widgets/gateway_connect_dialog.dart';
import '../../widgets/desktop_workspace_scaffold.dart';
import '../../widgets/pane_resize_handle.dart';
import '../../widgets/surface_card.dart';

class AssistantPage extends StatefulWidget {
  const AssistantPage({
    super.key,
    required this.controller,
    required this.onOpenDetail,
    this.navigationPanelBuilder,
    this.showStandaloneTaskRail = true,
    this.unifiedPaneStartsCollapsed = false,
  });

  final AppController controller;
  final ValueChanged<DetailPanelData> onOpenDetail;
  final Widget Function(double contentWidth)? navigationPanelBuilder;
  final bool showStandaloneTaskRail;
  final bool unifiedPaneStartsCollapsed;

  @override
  State<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends State<AssistantPage> {
  static const double _sidePaneMinWidth = 184;
  static const double _sidePaneContentMinWidth = 140;
  static const double _mainWorkspaceMinWidth = 620;
  static const double _sidePaneViewportPadding = 72;
  static const double _sideTabRailWidth = 46;

  late final TextEditingController _inputController;
  late final TextEditingController _threadSearchController;
  late final ScrollController _conversationController;
  late final FocusNode _composerFocusNode;
  final String _mode = 'ask';
  String _thinkingLabel = 'high';
  double _threadRailWidth = 248;
  String _threadQuery = '';
  bool _sidePaneCollapsed = false;
  _AssistantSidePane _activeSidePane = _AssistantSidePane.tasks;
  WorkspaceDestination? _activeFocusedDestination;
  final Map<String, _AssistantTaskSeed> _taskSeeds =
      <String, _AssistantTaskSeed>{};
  final Set<String> _archivedTaskKeys = <String>{};
  List<_ComposerAttachment> _attachments = const <_ComposerAttachment>[];
  String? _lastSubmittedPrompt;
  String? _lastSubmittedSessionKey;
  String? _lastAutoAgentLabel;
  List<String> _lastSubmittedAttachments = const <String>[];

  @override
  void initState() {
    super.initState();
    _inputController = TextEditingController();
    _threadSearchController = TextEditingController();
    _conversationController = ScrollController();
    _composerFocusNode = FocusNode();
    _sidePaneCollapsed = widget.unifiedPaneStartsCollapsed;
  }

  @override
  void didUpdateWidget(covariant AssistantPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.unifiedPaneStartsCollapsed !=
        widget.unifiedPaneStartsCollapsed) {
      _sidePaneCollapsed = widget.unifiedPaneStartsCollapsed;
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    _threadSearchController.dispose();
    _conversationController.dispose();
    _composerFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        final messages = List<GatewayChatMessage>.from(controller.chatMessages);
        final timelineItems = _buildTimelineItems(controller, messages);
        final tasks = _buildTaskEntries(controller);
        final visibleTasks = _filterTasks(tasks);
        final currentTask = _resolveCurrentTask(
          tasks,
          controller.currentSessionKey,
        );

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_conversationController.hasClients) {
            return;
          }
          _conversationController.animateTo(
            _conversationController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
          );
        });

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
              final mainWorkspace = _buildMainWorkspace(
                controller: controller,
                timelineItems: timelineItems,
                currentTask: currentTask,
              );
              if (!showThreadRail && !showUnifiedSidePane) {
                return mainWorkspace;
              }

              final maxThreadRailWidth = _resolveMaxSidePaneWidth(
                constraints.maxWidth,
              );
              final threadRailWidth = _threadRailWidth
                  .clamp(_sidePaneMinWidth, maxThreadRailWidth)
                  .toDouble();

              if (showUnifiedSidePane) {
                final favoriteDestinations =
                    controller.assistantNavigationDestinations;
                final activeFocusedDestination = _resolveFocusedDestination(
                  favoriteDestinations,
                );
                final effectiveActiveSidePane =
                    _activeSidePane == _AssistantSidePane.focused &&
                        activeFocusedDestination == null
                    ? _AssistantSidePane.navigation
                    : _activeSidePane;
                final sidePanelContentWidth =
                    (threadRailWidth - _sideTabRailWidth - 2)
                        .clamp(_sidePaneContentMinWidth, threadRailWidth)
                        .toDouble();
                return Row(
                  children: [
                    AnimatedContainer(
                      key: const Key('assistant-unified-side-pane-shell'),
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      width: _sidePaneCollapsed
                          ? _sideTabRailWidth
                          : threadRailWidth,
                      child: _AssistantUnifiedSidePane(
                        activePane: effectiveActiveSidePane,
                        activeFocusedDestination: activeFocusedDestination,
                        collapsed: _sidePaneCollapsed,
                        favoriteDestinations: favoriteDestinations,
                        taskPanel: _AssistantTaskRail(
                          key: const Key('assistant-task-rail'),
                          controller: controller,
                          tasks: visibleTasks,
                          query: _threadQuery,
                          searchController: _threadSearchController,
                          onQueryChanged: (value) {
                            setState(() {
                              _threadQuery = value.trim();
                            });
                          },
                          onClearQuery: () {
                            _threadSearchController.clear();
                            setState(() {
                              _threadQuery = '';
                            });
                          },
                          onRefreshTasks: controller.refreshSessions,
                          onCreateTask: _createNewThread,
                          onSelectTask: (sessionKey) async {
                            await controller.switchSession(sessionKey);
                            _focusComposer();
                          },
                          onArchiveTask: _archiveTask,
                          onRenameTask: _renameTask,
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
                                    activeFocusedDestination,
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
                                      _activeFocusedDestination =
                                          _resolveFocusedDestination(
                                            controller
                                                .assistantNavigationDestinations,
                                          );
                                      _activeSidePane =
                                          _activeFocusedDestination == null
                                          ? _AssistantSidePane.navigation
                                          : _AssistantSidePane.focused;
                                    });
                                  },
                                ),
                              ),
                        onSelectPane: (pane) {
                          setState(() {
                            final normalizedPane =
                                pane == _AssistantSidePane.focused
                                ? _AssistantSidePane.navigation
                                : pane;
                            if (effectiveActiveSidePane == normalizedPane) {
                              _sidePaneCollapsed = !_sidePaneCollapsed;
                              return;
                            }
                            _activeSidePane = normalizedPane;
                            if (normalizedPane != _AssistantSidePane.focused) {
                              _activeFocusedDestination = null;
                            }
                            _sidePaneCollapsed = false;
                          });
                        },
                        onSelectFocusedDestination: (destination) {
                          setState(() {
                            final isSameSelection =
                                effectiveActiveSidePane ==
                                    _AssistantSidePane.focused &&
                                activeFocusedDestination == destination;
                            if (isSameSelection) {
                              _sidePaneCollapsed = !_sidePaneCollapsed;
                              return;
                            }
                            _activeFocusedDestination = destination;
                            _activeSidePane = _AssistantSidePane.focused;
                            _sidePaneCollapsed = false;
                          });
                        },
                        onToggleCollapsed: () {
                          setState(() {
                            _sidePaneCollapsed = !_sidePaneCollapsed;
                          });
                        },
                      ),
                    ),
                    if (!_sidePaneCollapsed)
                      SizedBox(
                        width: 6,
                        child: PaneResizeHandle(
                          axis: Axis.horizontal,
                          onDelta: (delta) {
                            setState(() {
                              _threadRailWidth = (_threadRailWidth + delta)
                                  .clamp(_sidePaneMinWidth, maxThreadRailWidth)
                                  .toDouble();
                            });
                          },
                        ),
                      ),
                    const SizedBox(width: 2),
                    Expanded(child: mainWorkspace),
                  ],
                );
              }

              return Row(
                children: [
                  SizedBox(
                    width: threadRailWidth,
                    child: _AssistantTaskRail(
                      key: const Key('assistant-task-rail'),
                      controller: controller,
                      tasks: visibleTasks,
                      query: _threadQuery,
                      searchController: _threadSearchController,
                      onQueryChanged: (value) {
                        setState(() {
                          _threadQuery = value.trim();
                        });
                      },
                      onClearQuery: () {
                        _threadSearchController.clear();
                        setState(() {
                          _threadQuery = '';
                        });
                      },
                      onRefreshTasks: controller.refreshSessions,
                      onCreateTask: _createNewThread,
                      onSelectTask: (sessionKey) async {
                        await controller.switchSession(sessionKey);
                        _focusComposer();
                      },
                      onArchiveTask: _archiveTask,
                      onRenameTask: _renameTask,
                    ),
                  ),
                  SizedBox(
                    width: 6,
                    child: PaneResizeHandle(
                      axis: Axis.horizontal,
                      onDelta: (delta) {
                        setState(() {
                          _threadRailWidth = (_threadRailWidth + delta)
                              .clamp(_sidePaneMinWidth, maxThreadRailWidth)
                              .toDouble();
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 2),
                  Expanded(child: mainWorkspace),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildMainWorkspace({
    required AppController controller,
    required List<_TimelineItem> timelineItems,
    required _AssistantTaskEntry currentTask,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final composerHeight = constraints.maxHeight >= 900 ? 180.0 : 152.0;

        return Column(
          children: [
            Expanded(
              child: _ConversationArea(
                controller: controller,
                currentTask: currentTask,
                items: timelineItems,
                messageViewMode: controller.currentAssistantMessageViewMode,
                scrollController: _conversationController,
                onOpenDetail: widget.onOpenDetail,
                onFocusComposer: _focusComposer,
                onOpenGateway: _showConnectDialog,
                onOpenAiGatewaySettings: _openAiGatewaySettings,
                onReconnectGateway: _connectFromSavedSettingsOrShowDialog,
                onMessageViewModeChanged:
                    controller.setAssistantMessageViewMode,
              ),
            ),
            const SizedBox(height: 2),
            SizedBox(
              height: composerHeight,
              child: _AssistantLowerPane(
                inputController: _inputController,
                focusNode: _composerFocusNode,
                thinkingLabel: _thinkingLabel,
                modelLabel: controller.resolvedAssistantModel.isEmpty
                    ? appText('未选择模型', 'No model selected')
                    : controller.resolvedAssistantModel,
                modelOptions: controller.assistantModelChoices,
                attachments: _attachments,
                availableSkills: _availableSkillOptions(controller),
                discoveredSkills: _discoveredSkillOptions(controller),
                selectedSkillKeys: _selectedSkillKeysFor(controller),
                controller: controller,
                onRemoveAttachment: (attachment) {
                  setState(() {
                    _attachments = _attachments
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
                  _focusComposer();
                },
                onConfirmImportedSkills: (skillKeys) {
                  unawaited(
                    controller.confirmImportedSkillsForSession(
                      controller.currentSessionKey,
                      skillKeys,
                    ),
                  );
                },
                onDismissDiscoveredSkills: () {
                  return controller.dismissDiscoveredSkillsForSession(
                    controller.currentSessionKey,
                  );
                },
                onThinkingChanged: (value) {
                  setState(() => _thinkingLabel = value);
                },
                onModelChanged: (modelId) =>
                    controller.selectAssistantModelForSession(
                      controller.currentSessionKey,
                      modelId,
                    ),
                onOpenGateway: _showConnectDialog,
                onOpenAiGatewaySettings: _openAiGatewaySettings,
                onReconnectGateway: _connectFromSavedSettingsOrShowDialog,
                onPickAttachments: _pickAttachments,
                onSend: _submitPrompt,
              ),
            ),
          ],
        );
      },
    );
  }

  List<_TimelineItem> _buildTimelineItems(
    AppController controller,
    List<GatewayChatMessage> messages,
  ) {
    final items = <_TimelineItem>[];
    final ownerLabel = _conversationOwnerLabel(controller);

    for (final message in messages) {
      if ((message.toolName ?? '').trim().isNotEmpty) {
        items.add(
          _TimelineItem.toolCall(
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
          _TimelineItem.message(
            kind: _TimelineItemKind.user,
            label: appText('你', 'You'),
            text: message.text,
            pending: message.pending,
            error: message.error,
          ),
        );
      } else if (role == 'assistant') {
        items.add(
          _TimelineItem.message(
            kind: _TimelineItemKind.assistant,
            label: kProductBrandName,
            text: message.text,
            pending: message.pending,
            error: message.error,
          ),
        );
      } else {
        items.add(
          _TimelineItem.message(
            kind: _TimelineItemKind.agent,
            label: _lastAutoAgentLabel ?? ownerLabel,
            text: message.text,
            pending: message.pending,
            error: message.error,
          ),
        );
      }
    }

    final hasPendingTask =
        controller.hasAssistantPendingRun || controller.activeRunId != null;
    final lastMessage = messages.isEmpty ? null : messages.last;
    final lastRole = lastMessage?.role.toLowerCase();
    if (_lastSubmittedPrompt != null &&
        _sessionKeysMatch(
          _lastSubmittedSessionKey ?? '',
          controller.currentSessionKey,
        )) {
      final status = hasPendingTask
          ? 'running'
          : (lastMessage?.error ?? false)
          ? 'failed'
          : (lastRole == 'user' ? 'queued' : 'open');
      items.add(
        _TimelineItem.taskCard(
          title: _lastSubmittedPrompt!,
          status: status,
          summary: switch (status) {
            'queued' => appText('已提交到任务队列', 'Submitted to the task queue'),
            'running' => appText(
              '正在由 ${_lastAutoAgentLabel ?? ownerLabel} 执行',
              'Executing with ${_lastAutoAgentLabel ?? ownerLabel}',
            ),
            'failed' => appText(
              '这次执行返回了错误',
              'This execution returned an error',
            ),
            _ => appText(
              '本轮已回复，可继续在当前线程处理',
              'This turn finished. You can continue in the same thread.',
            ),
          },
          detail: _lastSubmittedAttachments.isEmpty
              ? '${controller.currentSessionKey} · ${_lastAutoAgentLabel ?? ownerLabel}'
              : appText(
                  '${controller.currentSessionKey} · ${_lastSubmittedAttachments.length} 个附件',
                  '${controller.currentSessionKey} · ${_lastSubmittedAttachments.length} attachment(s)',
                ),
          owner: _lastAutoAgentLabel ?? ownerLabel,
          sessionKey: controller.currentSessionKey,
        ),
      );
    }

    return items;
  }

  Future<void> _pickAttachments() async {
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
      _attachments = [
        ..._attachments,
        ...files.map(_ComposerAttachment.fromXFile),
      ];
    });
  }

  Future<void> _submitPrompt() async {
    final controller = widget.controller;
    final uiFeatures = controller.featuresFor(
      resolveUiFeaturePlatformFromContext(context),
    );
    final settings = controller.settings;
    final executionTarget = controller.assistantExecutionTarget;
    final rawPrompt = _inputController.text.trim();
    if (rawPrompt.isEmpty) {
      return;
    }

    final shouldUseGatewayAgent =
        executionTarget != AssistantExecutionTarget.aiGatewayOnly;
    final autoAgent = shouldUseGatewayAgent
        ? _pickAutoAgent(controller, rawPrompt)
        : null;
    if (autoAgent != null) {
      await controller.selectAgent(autoAgent.id);
    }

    final attachmentNames = _attachments
        .map((item) => item.name)
        .toList(growable: false);
    final selectedSkillLabels = _resolveSelectedSkillLabels(controller);
    final connectionState = controller.currentAssistantConnectionState;
    final prompt = _composePrompt(
      mode: _mode,
      prompt: rawPrompt,
      attachmentNames: attachmentNames,
      selectedSkillLabels: selectedSkillLabels,
      executionTarget: executionTarget,
      permissionLevel: settings.assistantPermissionLevel,
      workspacePath: settings.workspacePath,
      remoteProjectRoot: settings.remoteProjectRoot,
    );

    setState(() {
      _lastSubmittedPrompt = rawPrompt;
      _lastSubmittedSessionKey = controller.currentSessionKey;
      _lastAutoAgentLabel =
          autoAgent?.name ?? _conversationOwnerLabel(controller);
      _lastSubmittedAttachments = attachmentNames;
      _touchTaskSeed(
        sessionKey: controller.currentSessionKey,
        title:
            _taskSeeds[controller.currentSessionKey]?.title ??
            _fallbackSessionTitle(controller.currentSessionKey),
        preview: rawPrompt,
        status:
            controller.hasAssistantPendingRun ||
                executionTarget == AssistantExecutionTarget.aiGatewayOnly ||
                connectionState.connected
            ? 'running'
            : 'queued',
        owner: autoAgent?.name ?? _conversationOwnerLabel(controller),
        surface: 'Assistant',
        executionTarget: executionTarget,
        draft: controller.currentSessionKey.trim().startsWith('draft:'),
      );
    });

    if (uiFeatures.supportsMultiAgent &&
        controller.settings.multiAgent.enabled) {
      final collaborationAttachments = _attachments
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
      final attachmentPayloads = await _buildAttachmentPayloads(_attachments);
      await controller.sendChatMessage(
        prompt,
        thinking: _thinkingLabel,
        attachments: attachmentPayloads,
      );
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _attachments = const <_ComposerAttachment>[];
    });
    _inputController.clear();
  }

  Future<List<GatewayChatAttachmentPayload>> _buildAttachmentPayloads(
    List<_ComposerAttachment> attachments,
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

  GatewayAgentSummary? _pickAutoAgent(AppController controller, String prompt) {
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

  List<_ComposerSkillOption> _availableSkillOptions(AppController controller) {
    if (controller.isAiGatewayOnlyMode) {
      return controller
          .assistantImportedSkillsForSession(controller.currentSessionKey)
          .map(_skillOptionFromThreadSkill)
          .toList(growable: false);
    }
    final options = <_ComposerSkillOption>[];
    final seenKeys = <String>{};

    void addOption(_ComposerSkillOption option) {
      if (seenKeys.add(option.key)) {
        options.add(option);
      }
    }

    for (final skill in controller.skills) {
      final option = _skillOptionFromGateway(skill);
      addOption(option);
    }

    for (final option in _fallbackSkillOptions) {
      addOption(option);
    }

    return options;
  }

  List<_ComposerSkillOption> _discoveredSkillOptions(AppController controller) {
    return controller
        .assistantDiscoveredSkillsForSession(controller.currentSessionKey)
        .map(_skillOptionFromThreadSkill)
        .toList(growable: false);
  }

  List<String> _selectedSkillKeysFor(AppController controller) {
    return controller.assistantSelectedSkillKeysForSession(
      controller.currentSessionKey,
    );
  }

  List<String> _resolveSelectedSkillLabels(AppController controller) {
    final optionsByKey = <String, _ComposerSkillOption>{
      for (final option in _availableSkillOptions(controller))
        option.key: option,
    };
    return _selectedSkillKeysFor(controller)
        .map((key) => optionsByKey[key]?.label)
        .whereType<String>()
        .toList(growable: false);
  }

  String _composePrompt({
    required String mode,
    required String prompt,
    required List<String> attachmentNames,
    required List<String> selectedSkillLabels,
    required AssistantExecutionTarget executionTarget,
    required AssistantPermissionLevel permissionLevel,
    required String workspacePath,
    required String remoteProjectRoot,
  }) {
    final attachmentBlock = attachmentNames.isEmpty
        ? ''
        : 'Attached files:\n${attachmentNames.map((name) => '- $name').join('\n')}\n\n';
    final skillBlock = selectedSkillLabels.isEmpty
        ? ''
        : 'Preferred skills:\n${selectedSkillLabels.map((name) => '- $name').join('\n')}\n\n';
    final targetRoot = executionTarget == AssistantExecutionTarget.local
        ? workspacePath.trim()
        : remoteProjectRoot.trim();
    final executionContext =
        'Execution context:\n'
        '- target: ${executionTarget.promptValue}\n'
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

  void _showConnectDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => GatewayConnectDialog(
        controller: widget.controller,
        onDone: () => Navigator.of(context).pop(),
      ),
    );
  }

  Future<void> _connectFromSavedSettingsOrShowDialog() async {
    if (!widget.controller.canQuickConnectGateway) {
      _showConnectDialog();
      return;
    }
    await widget.controller.connectSavedGateway();
  }

  void _openAiGatewaySettings() {
    widget.controller.navigateTo(WorkspaceDestination.aiGateway);
  }

  void _focusComposer() {
    if (!mounted) {
      return;
    }
    _composerFocusNode.requestFocus();
  }

  Future<void> _createNewThread() async {
    final sessionKey = _buildDraftSessionKey(widget.controller);
    final inheritedTarget = widget.controller.currentAssistantExecutionTarget;
    final inheritedViewMode = widget.controller.currentAssistantMessageViewMode;
    setState(() {
      _archivedTaskKeys.removeWhere(
        (value) => _sessionKeysMatch(value, sessionKey),
      );
      _taskSeeds[sessionKey] = _AssistantTaskSeed(
        sessionKey: sessionKey,
        title: appText('新对话', 'New conversation'),
        preview: appText(
          '等待描述这个任务的第一条消息',
          'Waiting for the first message of this task',
        ),
        status: 'queued',
        updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
        owner: _conversationOwnerLabel(widget.controller),
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
    );
    await widget.controller.switchSession(sessionKey);
    _focusComposer();
  }

  List<_AssistantTaskEntry> _buildTaskEntries(AppController controller) {
    _archivedTaskKeys
      ..clear()
      ..addAll(controller.settings.assistantArchivedTaskKeys);
    _synchronizeTaskSeeds(controller);
    final entries =
        _taskSeeds.values
            .where((item) => !_isArchivedTask(item.sessionKey))
            .map((item) {
              final isCurrent = _sessionKeysMatch(
                item.sessionKey,
                controller.currentSessionKey,
              );
              final entry = item.toEntry(isCurrent: isCurrent);
              if (!isCurrent) {
                return entry;
              }
              return entry.copyWith(owner: _conversationOwnerLabel(controller));
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

  List<_AssistantTaskEntry> _filterTasks(List<_AssistantTaskEntry> items) {
    final query = _threadQuery.trim().toLowerCase();
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

  _AssistantTaskEntry _resolveCurrentTask(
    List<_AssistantTaskEntry> items,
    String sessionKey,
  ) {
    for (final item in items) {
      if (_sessionKeysMatch(item.sessionKey, sessionKey)) {
        return item;
      }
    }
    return _AssistantTaskEntry(
      sessionKey: sessionKey,
      title: _resolvedTaskTitle(widget.controller, sessionKey),
      preview: '',
      status: 'queued',
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
      owner: _conversationOwnerLabel(widget.controller),
      surface: 'Assistant',
      executionTarget: widget.controller.currentAssistantExecutionTarget,
      isCurrent: true,
      draft: true,
    );
  }

  void _synchronizeTaskSeeds(AppController controller) {
    for (final session in controller.assistantSessions) {
      if (_isArchivedTask(session.key)) {
        continue;
      }
      _taskSeeds[session.key] = _AssistantTaskSeed(
        sessionKey: session.key,
        title: _resolvedTaskTitle(controller, session.key, session: session),
        preview:
            _sessionPreview(session) ??
            appText('等待继续执行这个任务', 'Waiting to continue this task'),
        status: _sessionStatus(
          session,
          sessionPending: controller.assistantSessionHasPendingRun(session.key),
        ),
        updatedAtMs:
            session.updatedAtMs ??
            DateTime.now().millisecondsSinceEpoch.toDouble(),
        owner: _conversationOwnerLabel(controller),
        surface: session.surface ?? session.kind ?? 'Assistant',
        executionTarget: controller.assistantExecutionTargetForSession(
          session.key,
        ),
        draft: session.key.trim().startsWith('draft:'),
      );
    }

    final currentSeed = _taskSeeds[controller.currentSessionKey];
    final currentPreview = _currentTaskPreview(controller.chatMessages);
    final currentStatus = _currentTaskStatus(
      controller.chatMessages,
      controller,
    );

    if (_isArchivedTask(controller.currentSessionKey)) {
      return;
    }
    _taskSeeds[controller.currentSessionKey] = _AssistantTaskSeed(
      sessionKey: controller.currentSessionKey,
      title: _resolvedTaskTitle(
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
      owner: _conversationOwnerLabel(controller),
      surface: currentSeed?.surface ?? 'Assistant',
      executionTarget: controller.assistantExecutionTargetForSession(
        controller.currentSessionKey,
      ),
      draft: controller.currentSessionKey.trim().startsWith('draft:'),
    );
  }

  GatewaySessionSummary? _sessionByKey(
    AppController controller,
    String sessionKey,
  ) {
    for (final session in controller.assistantSessions) {
      if (_sessionKeysMatch(session.key, sessionKey)) {
        return session;
      }
    }
    return null;
  }

  String _resolvedTaskTitle(
    AppController controller,
    String sessionKey, {
    GatewaySessionSummary? session,
    String? fallbackTitle,
  }) {
    final customTitle = controller.assistantCustomTaskTitle(sessionKey);
    if (customTitle.isNotEmpty) {
      return customTitle;
    }
    final resolvedSession = session ?? _sessionByKey(controller, sessionKey);
    if (resolvedSession != null) {
      return _sessionDisplayTitle(resolvedSession);
    }
    final fallback = fallbackTitle?.trim() ?? '';
    if (fallback.isNotEmpty) {
      return fallback;
    }
    return _fallbackSessionTitle(sessionKey);
  }

  String _defaultTaskTitle(
    AppController controller,
    String sessionKey, {
    GatewaySessionSummary? session,
  }) {
    final resolvedSession = session ?? _sessionByKey(controller, sessionKey);
    if (resolvedSession != null) {
      return _sessionDisplayTitle(resolvedSession);
    }
    return _fallbackSessionTitle(sessionKey);
  }

  void _touchTaskSeed({
    required String sessionKey,
    required String title,
    required String preview,
    required String status,
    required String owner,
    required String surface,
    required AssistantExecutionTarget executionTarget,
    required bool draft,
  }) {
    _taskSeeds[sessionKey] = _AssistantTaskSeed(
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

  bool _isArchivedTask(String sessionKey) {
    for (final archivedKey in _archivedTaskKeys) {
      if (_sessionKeysMatch(archivedKey, sessionKey)) {
        return true;
      }
    }
    return false;
  }

  Future<void> _archiveTask(String sessionKey) async {
    final isCurrent = _sessionKeysMatch(
      sessionKey,
      widget.controller.currentSessionKey,
    );
    if (widget.controller.assistantSessionHasPendingRun(sessionKey)) {
      return;
    }
    setState(() {
      _archivedTaskKeys.add(sessionKey);
      _taskSeeds.removeWhere((key, _) => _sessionKeysMatch(key, sessionKey));
    });
    await widget.controller.saveAssistantTaskArchived(sessionKey, true);

    if (!isCurrent) {
      return;
    }

    for (final candidate in _taskSeeds.keys) {
      if (_isArchivedTask(candidate) ||
          _sessionKeysMatch(candidate, sessionKey)) {
        continue;
      }
      await widget.controller.switchSession(candidate);
      _focusComposer();
      return;
    }

    await _createNewThread();
  }

  Future<void> _renameTask(_AssistantTaskEntry entry) async {
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
        : _defaultTaskTitle(controller, entry.sessionKey);
    setState(() {
      final existing = _taskSeeds[entry.sessionKey];
      if (existing != null) {
        _taskSeeds[entry.sessionKey] = _AssistantTaskSeed(
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
    await controller.saveAssistantTaskTitle(entry.sessionKey, normalized);
  }

  String _buildDraftSessionKey(AppController controller) {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    if (controller.isAiGatewayOnlyMode) {
      return 'draft:$stamp';
    }
    final selectedAgentId = controller.selectedAgentId.trim();
    if (selectedAgentId.isEmpty) {
      return 'draft:$stamp';
    }
    return 'draft:$selectedAgentId:$stamp';
  }

  WorkspaceDestination? _resolveFocusedDestination(
    List<WorkspaceDestination> favorites,
  ) {
    if (favorites.isEmpty) {
      return null;
    }
    if (_activeFocusedDestination != null &&
        favorites.contains(_activeFocusedDestination)) {
      return _activeFocusedDestination;
    }
    return favorites.first;
  }

  double _resolveMaxSidePaneWidth(double viewportWidth) {
    final maxWidthByViewport =
        viewportWidth - _mainWorkspaceMinWidth - _sidePaneViewportPadding;
    return maxWidthByViewport
        .clamp(_sidePaneMinWidth, viewportWidth - _sidePaneViewportPadding)
        .toDouble();
  }

  String _conversationOwnerLabel(AppController controller) {
    return controller.assistantConversationOwnerLabel;
  }

  String? _currentTaskPreview(List<GatewayChatMessage> messages) {
    for (final message in messages.reversed) {
      final text = message.text.trim();
      if (text.isNotEmpty) {
        return text;
      }
    }
    return null;
  }

  String? _currentTaskStatus(
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

enum _AssistantSidePane { tasks, navigation, focused }

class _AssistantUnifiedSidePane extends StatelessWidget {
  const _AssistantUnifiedSidePane({
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

  final _AssistantSidePane activePane;
  final WorkspaceDestination? activeFocusedDestination;
  final bool collapsed;
  final List<WorkspaceDestination> favoriteDestinations;
  final Widget taskPanel;
  final Widget navigationPanel;
  final Widget? focusedPanel;
  final ValueChanged<_AssistantSidePane> onSelectPane;
  final ValueChanged<WorkspaceDestination> onSelectFocusedDestination;
  final VoidCallback onToggleCollapsed;

  @override
  Widget build(BuildContext context) {
    final sidePaneContent = activePane == _AssistantSidePane.tasks
        ? taskPanel
        : activePane == _AssistantSidePane.focused && focusedPanel != null
        ? focusedPanel!
        : navigationPanel;

    return Row(
      children: [
        _AssistantSideTabRail(
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
                  _AssistantSidePane.tasks => 'assistant-side-pane-tasks',
                  _AssistantSidePane.navigation =>
                    'assistant-side-pane-navigation',
                  _AssistantSidePane.focused =>
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

class _AssistantSideTabRail extends StatelessWidget {
  const _AssistantSideTabRail({
    required this.activePane,
    required this.activeFocusedDestination,
    required this.collapsed,
    required this.favoriteDestinations,
    required this.onSelectPane,
    required this.onSelectFocusedDestination,
    required this.onToggleCollapsed,
  });

  final _AssistantSidePane activePane;
  final WorkspaceDestination? activeFocusedDestination;
  final bool collapsed;
  final List<WorkspaceDestination> favoriteDestinations;
  final ValueChanged<_AssistantSidePane> onSelectPane;
  final ValueChanged<WorkspaceDestination> onSelectFocusedDestination;
  final VoidCallback onToggleCollapsed;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      key: const Key('assistant-side-pane'),
      width: 46,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            palette.chromeHighlight.withValues(alpha: 0.96),
            palette.chromeSurface,
          ],
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: palette.chromeStroke),
        boxShadow: [palette.chromeShadowAmbient],
      ),
      child: Column(
        children: [
          const SizedBox(height: 4),
          _AssistantSideTabButton(
            key: const Key('assistant-side-pane-tab-tasks'),
            icon: Icons.checklist_rtl_rounded,
            selected: activePane == _AssistantSidePane.tasks,
            tooltip: appText('任务', 'Tasks'),
            onTap: () => onSelectPane(_AssistantSidePane.tasks),
          ),
          const SizedBox(height: 4),
          _AssistantSideTabButton(
            key: const Key('assistant-side-pane-tab-navigation'),
            icon: Icons.dashboard_customize_outlined,
            selected: activePane == _AssistantSidePane.navigation,
            tooltip: appText('导航', 'Navigation'),
            onTap: () => onSelectPane(_AssistantSidePane.navigation),
          ),
          if (favoriteDestinations.isNotEmpty) ...[
            const SizedBox(height: 4),
            Container(width: 24, height: 1, color: palette.chromeStroke),
            const SizedBox(height: 4),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.zero,
                child: Column(
                  children: favoriteDestinations
                      .map(
                        (destination) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: _AssistantSideTabButton(
                            key: ValueKey<String>(
                              'assistant-side-pane-tab-focus-${destination.name}',
                            ),
                            icon: destination.icon,
                            selected:
                                activePane == _AssistantSidePane.focused &&
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
              backgroundColor: palette.chromeSurface,
              foregroundColor: palette.textSecondary,
              side: BorderSide(color: palette.chromeStroke),
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
                          widget.selected
                              ? palette.chromeSurface
                              : palette.chromeSurfacePressed,
                        ],
                      )
                    : null,
                color: widget.selected || _hovered ? null : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: widget.selected || _hovered
                      ? palette.chromeStroke
                      : Colors.transparent,
                ),
                boxShadow: widget.selected
                    ? [palette.chromeShadowLift]
                    : const [],
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

class _AssistantLowerPane extends StatelessWidget {
  const _AssistantLowerPane({
    required this.controller,
    required this.inputController,
    required this.focusNode,
    required this.thinkingLabel,
    required this.modelLabel,
    required this.modelOptions,
    required this.attachments,
    required this.availableSkills,
    required this.discoveredSkills,
    required this.selectedSkillKeys,
    required this.onRemoveAttachment,
    required this.onToggleSkill,
    required this.onConfirmImportedSkills,
    required this.onDismissDiscoveredSkills,
    required this.onThinkingChanged,
    required this.onModelChanged,
    required this.onOpenGateway,
    required this.onOpenAiGatewaySettings,
    required this.onReconnectGateway,
    required this.onPickAttachments,
    required this.onSend,
  });

  final AppController controller;
  final TextEditingController inputController;
  final FocusNode focusNode;
  final String thinkingLabel;
  final String modelLabel;
  final List<String> modelOptions;
  final List<_ComposerAttachment> attachments;
  final List<_ComposerSkillOption> availableSkills;
  final List<_ComposerSkillOption> discoveredSkills;
  final List<String> selectedSkillKeys;
  final ValueChanged<_ComposerAttachment> onRemoveAttachment;
  final ValueChanged<String> onToggleSkill;
  final ValueChanged<List<String>> onConfirmImportedSkills;
  final Future<void> Function() onDismissDiscoveredSkills;
  final ValueChanged<String> onThinkingChanged;
  final Future<void> Function(String modelId) onModelChanged;
  final VoidCallback onOpenGateway;
  final VoidCallback onOpenAiGatewaySettings;
  final Future<void> Function() onReconnectGateway;
  final VoidCallback onPickAttachments;
  final Future<void> Function() onSend;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: _ComposerBar(
          controller: controller,
          inputController: inputController,
          focusNode: focusNode,
          thinkingLabel: thinkingLabel,
          modelLabel: modelLabel,
          modelOptions: modelOptions,
          attachments: attachments,
          availableSkills: availableSkills,
          discoveredSkills: discoveredSkills,
          selectedSkillKeys: selectedSkillKeys,
          onRemoveAttachment: onRemoveAttachment,
          onToggleSkill: onToggleSkill,
          onConfirmImportedSkills: onConfirmImportedSkills,
          onDismissDiscoveredSkills: onDismissDiscoveredSkills,
          onThinkingChanged: onThinkingChanged,
          onModelChanged: onModelChanged,
          onOpenGateway: onOpenGateway,
          onOpenAiGatewaySettings: onOpenAiGatewaySettings,
          onReconnectGateway: onReconnectGateway,
          onPickAttachments: onPickAttachments,
          onSend: onSend,
        ),
      ),
    );
  }
}

class _ConversationArea extends StatelessWidget {
  const _ConversationArea({
    required this.controller,
    required this.currentTask,
    required this.items,
    required this.messageViewMode,
    required this.scrollController,
    required this.onOpenDetail,
    required this.onFocusComposer,
    required this.onOpenGateway,
    required this.onOpenAiGatewaySettings,
    required this.onReconnectGateway,
    required this.onMessageViewModeChanged,
  });

  final AppController controller;
  final _AssistantTaskEntry currentTask;
  final List<_TimelineItem> items;
  final AssistantMessageViewMode messageViewMode;
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
    final theme = Theme.of(context);
    final statusStyle = _pillStyleForStatus(context, currentTask.status);

    return SurfaceCard(
      borderRadius: 0,
      padding: EdgeInsets.zero,
      tone: SurfaceCardTone.chrome,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        currentTask.title,
                        key: const Key('assistant-conversation-title'),
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _StatusPill(
                            label: currentTask.draft
                                ? appText('草稿任务', 'Draft task')
                                : _taskStatusLabel(currentTask.status),
                            backgroundColor: statusStyle.backgroundColor,
                            textColor: statusStyle.foregroundColor,
                          ),
                          _MetaPill(
                            label: currentTask.owner,
                            icon: Icons.smart_toy_outlined,
                          ),
                          _MetaPill(
                            label: currentTask.surface,
                            icon: Icons.forum_outlined,
                          ),
                          _MetaPill(
                            label: controller.currentSessionKey,
                            icon: Icons.tag_rounded,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _MessageViewModeChip(
                      value: messageViewMode,
                      onSelected: onMessageViewModeChanged,
                    ),
                    const SizedBox(width: 6),
                    _ConnectionChip(controller: controller),
                  ],
                ),
              ],
            ),
          ),
          Divider(height: 1, color: palette.strokeSoft),
          Expanded(
            child: Container(
              decoration: BoxDecoration(color: palette.canvas),
              child: items.isEmpty
                  ? _AssistantEmptyState(
                      controller: controller,
                      onFocusComposer: onFocusComposer,
                      onOpenGateway: onOpenGateway,
                      onOpenAiGatewaySettings: onOpenAiGatewaySettings,
                      onReconnectGateway: onReconnectGateway,
                    )
                  : ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                      physics: const BouncingScrollPhysics(),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return switch (item.kind) {
                          _TimelineItemKind.user => _MessageBubble(
                            label: item.label!,
                            text: item.text!,
                            alignRight: true,
                            tone: _BubbleTone.user,
                            messageViewMode: messageViewMode,
                          ),
                          _TimelineItemKind.assistant => _MessageBubble(
                            label: item.label!,
                            text: item.text!,
                            alignRight: false,
                            tone: _BubbleTone.assistant,
                            messageViewMode: messageViewMode,
                          ),
                          _TimelineItemKind.agent => _MessageBubble(
                            label: item.label!,
                            text: item.text!,
                            alignRight: false,
                            tone: _BubbleTone.agent,
                            messageViewMode: messageViewMode,
                          ),
                          _TimelineItemKind.toolCall => _ToolCallTile(
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
                          _TimelineItemKind.taskCard => _TaskStatusCard(
                            title: item.title!,
                            status: item.status!,
                            summary: item.summary!,
                            detail: item.detail!,
                            owner: item.owner!,
                            sessionKey: item.sessionKey!,
                            isCurrentSession:
                                item.sessionKey == controller.currentSessionKey,
                            onContinueConversation: () {
                              controller.switchSession(item.sessionKey!);
                              onFocusComposer();
                            },
                            onOpenTasks: () {
                              controller.navigateTo(WorkspaceDestination.tasks);
                            },
                          ),
                        };
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AssistantTaskRail extends StatelessWidget {
  const _AssistantTaskRail({
    super.key,
    required this.controller,
    required this.tasks,
    required this.query,
    required this.searchController,
    required this.onQueryChanged,
    required this.onClearQuery,
    required this.onRefreshTasks,
    required this.onCreateTask,
    required this.onSelectTask,
    required this.onArchiveTask,
    required this.onRenameTask,
  });

  final AppController controller;
  final List<_AssistantTaskEntry> tasks;
  final String query;
  final TextEditingController searchController;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onClearQuery;
  final Future<void> Function() onRefreshTasks;
  final Future<void> Function() onCreateTask;
  final Future<void> Function(String sessionKey) onSelectTask;
  final Future<void> Function(String sessionKey) onArchiveTask;
  final Future<void> Function(_AssistantTaskEntry entry) onRenameTask;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    final groupedTasks = _groupTasksForRail(tasks);
    final runningCount = tasks
        .where((task) => _normalizedTaskStatus(task.status) == 'running')
        .length;
    final openCount = tasks
        .where((task) => _normalizedTaskStatus(task.status) == 'open')
        .length;

    return SurfaceCard(
      borderRadius: 0,
      padding: EdgeInsets.zero,
      tone: SurfaceCardTone.chrome,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('assistant-task-search'),
                        controller: searchController,
                        onChanged: onQueryChanged,
                        decoration: InputDecoration(
                          hintText: appText('搜索任务', 'Search tasks'),
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: query.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: appText('清除搜索', 'Clear search'),
                                  onPressed: onClearQuery,
                                  icon: const Icon(Icons.close_rounded),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      key: const Key('assistant-task-refresh'),
                      tooltip: appText('刷新任务', 'Refresh tasks'),
                      onPressed: () async {
                        await onRefreshTasks();
                      },
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    key: const Key('assistant-new-task-button'),
                    onPressed: () async {
                      await onCreateTask();
                    },
                    icon: const Icon(Icons.edit_note_rounded),
                    label: Text(appText('新对话', 'New conversation')),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 32),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _MetaPill(
                      label: '${appText('运行中', 'Running')} $runningCount',
                      icon: Icons.play_circle_outline_rounded,
                    ),
                    _MetaPill(
                      label: '${appText('当前', 'Open')} $openCount',
                      icon: Icons.forum_outlined,
                    ),
                    _MetaPill(
                      label:
                          '${appText('技能', 'Skills')} ${controller.skills.length}',
                      icon: Icons.auto_awesome_rounded,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Divider(height: 1, color: palette.strokeSoft),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
            child: Row(
              children: [
                Text(
                  appText('任务列表', 'Task list'),
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(width: 6),
                Text(
                  '${tasks.length}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: palette.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: tasks.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        appText(
                          '没有匹配的任务，试试新建一个。',
                          'No matching tasks. Start a new one.',
                        ),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: palette.textSecondary,
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                    itemCount: groupedTasks.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final group = groupedTasks[index];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _AssistantTaskGroupHeader(
                            executionTarget: group.executionTarget,
                            count: group.items.length,
                          ),
                          const SizedBox(height: 4),
                          for (
                            var itemIndex = 0;
                            itemIndex < group.items.length;
                            itemIndex++
                          ) ...[
                            if (itemIndex > 0) const SizedBox(height: 4),
                            _AssistantTaskTile(
                              entry: group.items[itemIndex],
                              archiveEnabled:
                                  _normalizedTaskStatus(
                                    group.items[itemIndex].status,
                                  ) !=
                                  'running',
                              onTap: () async {
                                await onSelectTask(
                                  group.items[itemIndex].sessionKey,
                                );
                              },
                              onRename: () async {
                                await onRenameTask(group.items[itemIndex]);
                              },
                              onArchive: () async {
                                await onArchiveTask(
                                  group.items[itemIndex].sessionKey,
                                );
                              },
                            ),
                          ],
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

List<_AssistantTaskGroup> _groupTasksForRail(List<_AssistantTaskEntry> tasks) {
  final grouped = <AssistantExecutionTarget, List<_AssistantTaskEntry>>{
    for (final target in AssistantExecutionTarget.values)
      target: <_AssistantTaskEntry>[],
  };
  for (final task in tasks) {
    grouped[task.executionTarget]!.add(task);
  }
  return AssistantExecutionTarget.values
      .map(
        (target) => _AssistantTaskGroup(
          executionTarget: target,
          items: grouped[target]!,
        ),
      )
      .where((group) => group.items.isNotEmpty)
      .toList(growable: false);
}

class _AssistantTaskTile extends StatelessWidget {
  const _AssistantTaskTile({
    required this.entry,
    required this.archiveEnabled,
    required this.onTap,
    required this.onRename,
    required this.onArchive,
  });

  final _AssistantTaskEntry entry;
  final bool archiveEnabled;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    final statusStyle = _pillStyleForStatus(context, entry.status);

    return Material(
      color: entry.isCurrent ? palette.surfacePrimary : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        key: ValueKey<String>('assistant-task-item-${entry.sessionKey}'),
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        onLongPress: onRename,
        onSecondaryTap: onRename,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          decoration: BoxDecoration(
            color: entry.isCurrent
                ? palette.surfaceSecondary
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: entry.isCurrent ? palette.strokeSoft : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: statusStyle.backgroundColor,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  entry.draft
                      ? Icons.edit_note_rounded
                      : _normalizedTaskStatus(entry.status) == 'running'
                      ? Icons.play_arrow_rounded
                      : Icons.task_alt_rounded,
                  size: 15,
                  color: statusStyle.foregroundColor,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  entry.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: entry.isCurrent
                        ? FontWeight.w600
                        : FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                entry.updatedAtLabel,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: palette.textMuted,
                ),
              ),
              const SizedBox(width: 2),
              IconButton(
                key: ValueKey<String>(
                  'assistant-task-archive-${entry.sessionKey}',
                ),
                tooltip: appText('归档任务', 'Archive task'),
                visualDensity: VisualDensity.compact,
                splashRadius: 12,
                onPressed: archiveEnabled ? onArchive : null,
                icon: Icon(
                  Icons.archive_outlined,
                  size: 18,
                  color: palette.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AssistantTaskGroupHeader extends StatelessWidget {
  const _AssistantTaskGroupHeader({
    required this.executionTarget,
    required this.count,
  });

  final AssistantExecutionTarget executionTarget;
  final int count;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    return Padding(
      key: ValueKey<String>('assistant-task-group-${executionTarget.name}'),
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
      child: Row(
        children: [
          Icon(executionTarget.icon, size: 14, color: palette.textMuted),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              executionTarget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: palette.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$count',
            style: theme.textTheme.bodySmall?.copyWith(
              color: palette.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _AssistantEmptyState extends StatelessWidget {
  const _AssistantEmptyState({
    required this.controller,
    required this.onFocusComposer,
    required this.onOpenGateway,
    required this.onOpenAiGatewaySettings,
    required this.onReconnectGateway,
  });

  final AppController controller;
  final VoidCallback onFocusComposer;
  final VoidCallback onOpenGateway;
  final VoidCallback onOpenAiGatewaySettings;
  final Future<void> Function() onReconnectGateway;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connectionState = controller.currentAssistantConnectionState;
    final aiGatewayOnly = connectionState.isAiGatewayOnly;
    final connected = connectionState.connected;
    final reconnectAvailable = controller.canQuickConnectGateway;
    final title = aiGatewayOnly
        ? connected
              ? appText('开始 AI 对话', 'Start an AI conversation')
              : appText('先配置 AI Gateway', 'Configure AI Gateway first')
        : connected
        ? appText('开始对话或运行任务', 'Start a chat or run a task')
        : connectionState.status == RuntimeConnectionStatus.error
        ? appText('Gateway 连接失败', 'Gateway connection failed')
        : appText('先连接 Gateway', 'Connect a gateway first');
    final description = aiGatewayOnly
        ? connected
              ? appText(
                  '当前模式只通过 AI Gateway 处理当前任务，不会建立 OpenClaw Gateway 会话。',
                  'This mode handles the current task through AI Gateway only and does not open an OpenClaw Gateway session.',
                )
              : appText(
                  '请先在 Settings -> AI Gateway 中配置地址、API Key 和默认模型，然后继续当前任务。',
                  'Set the AI Gateway URL, API key, and default model in Settings -> AI Gateway, then continue this task.',
                )
        : connected
        ? appText(
            '输入需求后即可开始执行，结果会回到当前会话并同步到任务页。',
            'Type a request to start execution. Results return to this session and the Tasks page.',
          )
        : connectionState.pairingRequired
        ? appText(
            '当前设备还没通过 Gateway 配对审批。请先在已授权设备上批准该 pairing request，再重新连接。',
            'This device has not been approved yet. Approve the pairing request from an authorized device, then reconnect.',
          )
        : connectionState.gatewayTokenMissing
        ? appText(
            '首次连接需要共享 Token；配对完成后可继续使用本机的 device token。',
            'The first connection requires a shared token; after pairing, this device can continue with its device token.',
          )
        : (connectionState.lastError?.trim().isNotEmpty == true
              ? connectionState.lastError!.trim()
              : appText(
                  '连接后可直接对话、创建任务，并在当前会话查看结果。',
                  'After connecting, you can chat, create tasks, and read results in this session.',
                ));

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.palette.surfacePrimary.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: context.palette.strokeSoft),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(description, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    FilledButton.icon(
                      onPressed: connected
                          ? onFocusComposer
                          : aiGatewayOnly
                          ? onOpenAiGatewaySettings
                          : reconnectAvailable
                          ? () async {
                              await onReconnectGateway();
                            }
                          : onOpenGateway,
                      icon: Icon(
                        connected
                            ? Icons.edit_rounded
                            : aiGatewayOnly
                            ? Icons.tune_rounded
                            : reconnectAvailable
                            ? Icons.refresh_rounded
                            : Icons.link_rounded,
                      ),
                      label: Text(
                        connected
                            ? appText('开始输入', 'Start typing')
                            : aiGatewayOnly
                            ? appText('配置 AI Gateway', 'Configure AI Gateway')
                            : reconnectAvailable
                            ? appText('重新连接', 'Reconnect')
                            : appText('连接 Gateway', 'Connect gateway'),
                      ),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 28),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    if (!connected)
                      OutlinedButton.icon(
                        onPressed: aiGatewayOnly
                            ? onOpenAiGatewaySettings
                            : onOpenGateway,
                        icon: Icon(
                          aiGatewayOnly
                              ? Icons.hub_outlined
                              : Icons.settings_rounded,
                        ),
                        label: Text(
                          aiGatewayOnly
                              ? appText('打开 AI Gateway', 'Open AI Gateway')
                              : appText('编辑连接', 'Edit connection'),
                        ),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 28),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ComposerBar extends StatefulWidget {
  const _ComposerBar({
    required this.controller,
    required this.inputController,
    required this.focusNode,
    required this.thinkingLabel,
    required this.modelLabel,
    required this.modelOptions,
    required this.attachments,
    required this.availableSkills,
    required this.discoveredSkills,
    required this.selectedSkillKeys,
    required this.onRemoveAttachment,
    required this.onToggleSkill,
    required this.onConfirmImportedSkills,
    required this.onDismissDiscoveredSkills,
    required this.onThinkingChanged,
    required this.onModelChanged,
    required this.onOpenGateway,
    required this.onOpenAiGatewaySettings,
    required this.onReconnectGateway,
    required this.onPickAttachments,
    required this.onSend,
  });

  final AppController controller;
  final TextEditingController inputController;
  final FocusNode focusNode;
  final String thinkingLabel;
  final String modelLabel;
  final List<String> modelOptions;
  final List<_ComposerAttachment> attachments;
  final List<_ComposerSkillOption> availableSkills;
  final List<_ComposerSkillOption> discoveredSkills;
  final List<String> selectedSkillKeys;
  final ValueChanged<_ComposerAttachment> onRemoveAttachment;
  final ValueChanged<String> onToggleSkill;
  final ValueChanged<List<String>> onConfirmImportedSkills;
  final Future<void> Function() onDismissDiscoveredSkills;
  final ValueChanged<String> onThinkingChanged;
  final Future<void> Function(String modelId) onModelChanged;
  final VoidCallback onOpenGateway;
  final VoidCallback onOpenAiGatewaySettings;
  final Future<void> Function() onReconnectGateway;
  final VoidCallback onPickAttachments;
  final Future<void> Function() onSend;

  @override
  State<_ComposerBar> createState() => _ComposerBarState();
}

class _ComposerBarState extends State<_ComposerBar> {
  static const double _minInputHeight = 68;
  static const double _defaultInputHeight = 78;
  static const double _maxInputHeight = 220;

  late double _inputHeight;

  @override
  void initState() {
    super.initState();
    _inputHeight = _defaultInputHeight;
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
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final controller = widget.controller;
    final uiFeatures = controller.featuresFor(
      resolveUiFeaturePlatformFromContext(context),
    );
    final connectionState = controller.currentAssistantConnectionState;
    final aiGatewayOnly = connectionState.isAiGatewayOnly;
    final connected = connectionState.connected;
    final reconnectAvailable = controller.canQuickConnectGateway;
    final connecting = connectionState.connecting;
    final executionTarget = controller.assistantExecutionTarget;
    final permissionLevel = controller.assistantPermissionLevel;
    final selectedSkills = widget.availableSkills
        .where((skill) => widget.selectedSkillKeys.contains(skill.key))
        .toList(growable: false);
    final discoveredCount = widget.discoveredSkills.length;
    final submitLabel = connected
        ? appText('提交', 'Submit')
        : aiGatewayOnly
        ? appText('配置 AI Gateway', 'Configure AI Gateway')
        : connecting
        ? appText('连接中…', 'Connecting…')
        : reconnectAvailable
        ? appText('重连', 'Reconnect')
        : appText('连接', 'Connect');

    return SurfaceCard(
      borderRadius: 10,
      tone: SurfaceCardTone.chrome,
      child: Column(
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
                  label: executionTarget.label,
                  showChevron: true,
                  maxLabelWidth: 96,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                ),
              ),
              const SizedBox(width: 4),
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
                        label: collab.config.usesAris
                            ? appText('ARIS', 'ARIS')
                            : appText('原生', 'Native'),
                        showChevron: false,
                        maxLabelWidth: 64,
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
                fillColor: palette.chromeSurface,
                contentPadding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: palette.chromeStroke),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: palette.accent.withValues(alpha: 0.18),
                  ),
                ),
                hintText: appText(
                  '输入需求、补充上下文、继续追问，XWorkmate 会沿用当前任务上下文持续处理。',
                  'Describe the task, add context, or continue the thread. XWorkmate keeps the current task context.',
                ),
              ),
              onSubmitted: (_) => widget.onSend(),
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
                      if (aiGatewayOnly && discoveredCount > 0) ...[
                        InkWell(
                          key: const Key('assistant-discovered-skills-button'),
                          borderRadius: BorderRadius.circular(AppRadius.chip),
                          onTap: () => _showDiscoveredSkillsDialog(context),
                          child: _ComposerToolbarChip(
                            icon: Icons.download_done_rounded,
                            label: appText(
                              '候选技能 $discoveredCount',
                              'Candidates $discoveredCount',
                            ),
                            showChevron: true,
                            maxLabelWidth: 148,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      InkWell(
                        key: const Key('assistant-skill-picker-button'),
                        borderRadius: BorderRadius.circular(AppRadius.chip),
                        onTap: () => _showSkillPickerDialog(context),
                        child: _ComposerToolbarChip(
                          icon: Icons.auto_awesome_rounded,
                          label: selectedSkills.isEmpty
                              ? appText('技能', 'Skills')
                              : appText(
                                  '已选技能 ${selectedSkills.length}',
                                  'Skills ${selectedSkills.length}',
                                ),
                          showChevron: true,
                          maxLabelWidth: 132,
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
                          label: permissionLevel.label,
                          showChevron: true,
                          maxLabelWidth: 120,
                        ),
                      ),
                      const SizedBox(width: 6),
                      widget.modelOptions.isEmpty
                          ? _ComposerToolbarChip(
                              key: const Key('assistant-model-button'),
                              icon: Icons.bolt_rounded,
                              label: widget.modelLabel,
                              showChevron: false,
                              maxLabelWidth: 140,
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
                                icon: Icons.bolt_rounded,
                                label: widget.modelLabel,
                                showChevron: true,
                                maxLabelWidth: 140,
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
                          label: _assistantThinkingLabel(widget.thinkingLabel),
                          showChevron: true,
                          maxLabelWidth: 96,
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
                  onPressed: connecting
                      ? null
                      : connected
                      ? widget.onSend
                      : aiGatewayOnly
                      ? widget.onOpenAiGatewaySettings
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
                            : aiGatewayOnly
                            ? Icons.hub_outlined
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

  Future<void> _showSkillPickerDialog(BuildContext context) async {
    final searchController = TextEditingController();
    String query = '';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filteredSkills = widget.availableSkills
                .where((skill) {
                  if (query.trim().isEmpty) {
                    return true;
                  }
                  final haystack =
                      '${skill.label}\n${skill.description}\n${skill.sourceLabel}'
                          .toLowerCase();
                  return haystack.contains(query.trim().toLowerCase());
                })
                .toList(growable: false);

            return Dialog(
              key: const Key('assistant-skill-picker-dialog'),
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 32,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 560,
                  maxHeight: 520,
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  child: Column(
                    children: [
                      TextField(
                        key: const Key('assistant-skill-picker-search'),
                        controller: searchController,
                        autofocus: true,
                        onChanged: (value) {
                          setDialogState(() {
                            query = value;
                          });
                        },
                        decoration: InputDecoration(
                          hintText: appText('搜索技能', 'Search skills'),
                          prefixIcon: const Icon(Icons.search_rounded),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: filteredSkills.isEmpty
                            ? Center(
                                child: Text(
                                  appText('没有匹配的技能。', 'No matching skills.'),
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: context.palette.textSecondary,
                                      ),
                                ),
                              )
                            : ListView.separated(
                                itemCount: filteredSkills.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final skill = filteredSkills[index];
                                  final selected = widget.selectedSkillKeys
                                      .contains(skill.key);
                                  return _SkillPickerTile(
                                    key: ValueKey<String>(
                                      'assistant-skill-option-${skill.key}',
                                    ),
                                    option: skill,
                                    selected: selected,
                                    onTap: () {
                                      widget.onToggleSkill(skill.key);
                                      Navigator.of(dialogContext).pop();
                                    },
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    searchController.dispose();
  }

  Future<void> _showDiscoveredSkillsDialog(BuildContext context) async {
    final searchController = TextEditingController();
    final selectedKeys = <String>{};
    String query = '';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filteredSkills = widget.discoveredSkills
                .where((skill) {
                  if (query.trim().isEmpty) {
                    return true;
                  }
                  final haystack =
                      '${skill.label}\n${skill.description}\n${skill.sourceLabel}'
                          .toLowerCase();
                  return haystack.contains(query.trim().toLowerCase());
                })
                .toList(growable: false);
            return Dialog(
              key: const Key('assistant-discovered-skills-dialog'),
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 32,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 620,
                  maxHeight: 560,
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        appText('确认导入技能', 'Confirm Skill Import'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const Key('assistant-discovered-skills-search'),
                        controller: searchController,
                        autofocus: true,
                        onChanged: (value) {
                          setDialogState(() {
                            query = value;
                          });
                        },
                        decoration: InputDecoration(
                          hintText: appText(
                            '搜索候选技能',
                            'Search discovered skills',
                          ),
                          prefixIcon: const Icon(Icons.search_rounded),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: filteredSkills.isEmpty
                            ? Center(
                                child: Text(
                                  appText(
                                    '没有匹配的候选技能。',
                                    'No matching discovered skills.',
                                  ),
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: context.palette.textSecondary,
                                      ),
                                ),
                              )
                            : ListView.separated(
                                itemCount: filteredSkills.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final skill = filteredSkills[index];
                                  final selected = selectedKeys.contains(
                                    skill.key,
                                  );
                                  return CheckboxListTile(
                                    key: ValueKey<String>(
                                      'assistant-discovered-skill-${skill.key}',
                                    ),
                                    value: selected,
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                    title: Text(skill.label),
                                    subtitle: Text(
                                      skill.description.trim().isEmpty
                                          ? skill.sourceLabel
                                          : '${skill.description}\n${skill.sourceLabel}',
                                    ),
                                    onChanged: (_) {
                                      setDialogState(() {
                                        if (selected) {
                                          selectedKeys.remove(skill.key);
                                        } else {
                                          selectedKeys.add(skill.key);
                                        }
                                      });
                                    },
                                  );
                                },
                              ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            key: const Key(
                              'assistant-discovered-skills-dismiss',
                            ),
                            onPressed: () async {
                              await widget.onDismissDiscoveredSkills();
                              if (dialogContext.mounted) {
                                Navigator.of(dialogContext).pop();
                              }
                            },
                            child: Text(appText('忽略本次', 'Dismiss')),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            child: Text(appText('取消', 'Cancel')),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            key: const Key(
                              'assistant-discovered-skills-confirm',
                            ),
                            onPressed: selectedKeys.isEmpty
                                ? null
                                : () {
                                    widget.onConfirmImportedSkills(
                                      selectedKeys.toList(growable: false),
                                    );
                                    Navigator.of(dialogContext).pop();
                                  },
                            child: Text(appText('导入所选', 'Import Selected')),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    searchController.dispose();
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
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              palette.chromeHighlight.withValues(alpha: _hovered ? 0.94 : 0.88),
              _hovered ? palette.chromeSurfacePressed : palette.chromeSurface,
            ],
          ),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: palette.chromeStroke),
          boxShadow: [
            _hovered ? palette.chromeShadowLift : palette.chromeShadowAmbient,
          ],
        ),
        child: Icon(widget.icon, size: 18, color: palette.textMuted),
      ),
    );
  }
}

class _ComposerToolbarChip extends StatefulWidget {
  const _ComposerToolbarChip({
    super.key,
    required this.icon,
    required this.label,
    required this.showChevron,
    this.maxLabelWidth = 220,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppSpacing.xs,
      vertical: 6,
    ),
  });

  final IconData icon;
  final String label;
  final bool showChevron;
  final double maxLabelWidth;
  final EdgeInsetsGeometry padding;

  @override
  State<_ComposerToolbarChip> createState() => _ComposerToolbarChipState();
}

class _ComposerToolbarChipState extends State<_ComposerToolbarChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        padding: widget.padding,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              palette.chromeHighlight.withValues(alpha: _hovered ? 0.94 : 0.88),
              _hovered ? palette.chromeSurfacePressed : palette.chromeSurface,
            ],
          ),
          borderRadius: BorderRadius.circular(AppRadius.chip),
          border: Border.all(color: palette.chromeStroke),
          boxShadow: [
            _hovered ? palette.chromeShadowLift : palette.chromeShadowAmbient,
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(widget.icon, size: 13, color: palette.textMuted),
            const SizedBox(width: 4),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: widget.maxLabelWidth),
              child: Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            if (widget.showChevron) ...[
              const SizedBox(width: 2),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 14,
                color: palette.textMuted,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

extension on AssistantExecutionTarget {
  IconData get icon => switch (this) {
    AssistantExecutionTarget.aiGatewayOnly => Icons.hub_outlined,
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
    final borderColor = switch (tone) {
      _BubbleTone.user => theme.colorScheme.primary.withValues(alpha: 0.10),
      _BubbleTone.agent => theme.colorScheme.tertiary.withValues(alpha: 0.10),
      _BubbleTone.assistant => palette.surfaceSecondary,
    };

    return Align(
      alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: alignRight ? palette.accentMuted : palette.surfacePrimary,
            borderRadius: BorderRadius.circular(AppRadius.card),
            boxShadow: [
              BoxShadow(
                color: borderColor.withValues(alpha: 0.24),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              _MessageBubbleBody(
                text: text.isEmpty ? appText('暂无内容。', 'No content yet.') : text,
                renderMarkdown:
                    messageViewMode == AssistantMessageViewMode.rendered &&
                    tone != _BubbleTone.user,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageBubbleBody extends StatelessWidget {
  const _MessageBubbleBody({required this.text, required this.renderMarkdown});

  final String text;
  final bool renderMarkdown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!renderMarkdown) {
      return SelectableText(
        text,
        style: theme.textTheme.bodyLarge?.copyWith(
          color: theme.colorScheme.onSurface,
          height: 1.45,
        ),
      );
    }

    final styleSheet = MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: theme.textTheme.bodyLarge?.copyWith(
        color: theme.colorScheme.onSurface,
        height: 1.45,
      ),
      code: theme.textTheme.bodyMedium?.copyWith(
        fontFamily: 'Menlo',
        height: 1.4,
      ),
      codeblockDecoration: BoxDecoration(
        color: context.palette.surfaceSecondary,
        borderRadius: BorderRadius.circular(10),
      ),
      blockquoteDecoration: BoxDecoration(
        color: context.palette.surfaceSecondary.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(10),
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
      data: text,
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

class _TaskStatusCard extends StatelessWidget {
  const _TaskStatusCard({
    required this.title,
    required this.status,
    required this.summary,
    required this.detail,
    required this.owner,
    required this.sessionKey,
    required this.isCurrentSession,
    required this.onContinueConversation,
    required this.onOpenTasks,
  });

  final String title;
  final String status;
  final String summary;
  final String detail;
  final String owner;
  final String sessionKey;
  final bool isCurrentSession;
  final VoidCallback onContinueConversation;
  final VoidCallback onOpenTasks;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    final normalizedStatus = _normalizedTaskStatus(status);
    final statusStyle = _pillStyleForStatus(context, normalizedStatus);
    final icon = switch (normalizedStatus) {
      'queued' => Icons.schedule_send_rounded,
      'running' => Icons.play_circle_outline_rounded,
      'failed' => Icons.error_outline_rounded,
      _ => Icons.task_alt_rounded,
    };
    final hint = switch (normalizedStatus) {
      'queued' => appText('排队等待执行', 'Waiting in queue'),
      'running' => appText('正在执行中', 'Working now'),
      'failed' => appText('需要处理', 'Needs attention'),
      _ => appText('可继续在当前会话处理', 'Continue in session'),
    };

    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Material(
          color: palette.surfacePrimary,
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.card),
              color: palette.surfacePrimary,
              boxShadow: [
                BoxShadow(
                  color: palette.shadow.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: statusStyle.backgroundColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        icon,
                        size: 14,
                        color: statusStyle.foregroundColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: theme.textTheme.titleMedium),
                          const SizedBox(height: 2),
                          Text(summary, style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    _StatusPill(
                      label: _taskStatusLabel(status),
                      backgroundColor: statusStyle.backgroundColor,
                      textColor: statusStyle.foregroundColor,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: palette.surfaceSecondary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 4,
                    children: [
                      Text(detail, style: theme.textTheme.bodySmall),
                      Text(
                        owner,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      Text(sessionKey, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      hint,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: palette.textMuted,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: onContinueConversation,
                      icon: Icon(
                        isCurrentSession
                            ? Icons.edit_outlined
                            : Icons.forum_outlined,
                        size: 16,
                      ),
                      label: Text(
                        isCurrentSession
                            ? appText('继续', 'Continue')
                            : appText('打开会话', 'Open Session'),
                      ),
                    ),
                    TextButton(
                      onPressed: onOpenTasks,
                      child: Text(appText('打开任务', 'Open Tasks')),
                    ),
                  ],
                ),
              ],
            ),
          ),
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
            color: palette.surfacePrimary,
            borderRadius: BorderRadius.circular(AppRadius.card),
            boxShadow: [
              BoxShadow(
                color: palette.shadow.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
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
        boxShadow: [
          BoxShadow(
            color: context.palette.shadow.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
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
    final color = connectionState.isAiGatewayOnly
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
        boxShadow: [
          BoxShadow(
            color: context.palette.shadow.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
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
          boxShadow: [
            BoxShadow(
              color: palette.shadow.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
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

enum _TimelineItemKind { user, assistant, agent, taskCard, toolCall }

class _TimelineItem {
  const _TimelineItem._({
    required this.kind,
    this.label,
    this.text,
    this.title,
    this.status,
    this.summary,
    this.detail,
    this.owner,
    this.sessionKey,
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

  const _TimelineItem.taskCard({
    required String title,
    required String status,
    required String summary,
    required String detail,
    required String owner,
    required String sessionKey,
  }) : this._(
         kind: _TimelineItemKind.taskCard,
         title: title,
         status: status,
         summary: summary,
         detail: detail,
         owner: owner,
         sessionKey: sessionKey,
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
  final String? status;
  final String? summary;
  final String? detail;
  final String? owner;
  final String? sessionKey;
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
            boxShadow: [
              BoxShadow(
                color: palette.shadow.withValues(alpha: 0.03),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
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

StatusInfo _statusInfoForTask(String status) => switch (status) {
  'running' ||
  'Running' => StatusInfo(appText('运行中', 'Running'), StatusTone.accent),
  'failed' ||
  'Failed' => StatusInfo(appText('失败', 'Failed'), StatusTone.danger),
  'queued' ||
  'Queued' => StatusInfo(appText('排队中', 'Queued'), StatusTone.neutral),
  _ => StatusInfo(appText('可继续', 'Open'), StatusTone.success),
};

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

String _taskStatusLabel(String status) => _statusInfoForTask(status).label;

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
        ? appText('已导入到当前线程的技能。', 'Skill imported into this thread.')
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
    return InputChip(
      avatar: Icon(option.icon, size: 16, color: context.palette.accent),
      label: Text(option.label),
      onDeleted: onDeleted,
      side: BorderSide.none,
      backgroundColor: context.palette.surfaceSecondary,
      deleteIconColor: context.palette.textMuted,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.chip),
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

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: selected ? palette.surfaceSecondary : palette.surfacePrimary,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: palette.shadow.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(option.icon, size: 20, color: palette.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.label,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      option.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: palette.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                option.sourceLabel,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: palette.textMuted,
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 8),
                Icon(Icons.check_rounded, size: 18, color: palette.accent),
              ],
            ],
          ),
        ),
      ),
    );
  }
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
