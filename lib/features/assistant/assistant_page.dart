import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/app_metadata.dart';
import '../../i18n/app_language.dart';
import '../../models/app_models.dart';
import '../../runtime/runtime_models.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../widgets/gateway_connect_dialog.dart';
import '../../widgets/pane_resize_handle.dart';
import '../../widgets/surface_card.dart';
import '../../widgets/top_bar.dart';

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
  static const List<String> _modes = ['craft', 'ask', 'plan'];
  static const List<String> _thinkingModes = ['low', 'medium', 'high', 'max'];

  late final TextEditingController _inputController;
  late final TextEditingController _threadSearchController;
  late final ScrollController _conversationController;
  late final FocusNode _composerFocusNode;
  String _mode = 'ask';
  String _thinkingLabel = 'high';
  double _conversationPaneRatio = 0.7;
  double _threadRailWidth = 304;
  String _threadQuery = '';
  bool _sidePaneCollapsed = false;
  bool _taskRailOverviewExpanded = false;
  _AssistantSidePane _activeSidePane = _AssistantSidePane.tasks;
  final Map<String, _AssistantTaskSeed> _taskSeeds =
      <String, _AssistantTaskSeed>{};
  final Set<String> _archivedTaskKeys = <String>{};
  List<_ComposerAttachment> _attachments = const <_ComposerAttachment>[];
  String? _lastSubmittedPrompt;
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

        return Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
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

              final maxThreadRailWidth = (constraints.maxWidth * 0.28)
                  .clamp(232.0, 340.0)
                  .toDouble();
              final threadRailWidth = _threadRailWidth
                  .clamp(232.0, maxThreadRailWidth)
                  .toDouble();

              if (showUnifiedSidePane) {
                const sideTabRailWidth = 58.0;
                final sidePanelContentWidth =
                    (threadRailWidth - sideTabRailWidth - 6)
                        .clamp(174.0, maxThreadRailWidth)
                        .toDouble();
                return Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      width: _sidePaneCollapsed
                          ? sideTabRailWidth
                          : threadRailWidth,
                      child: _AssistantUnifiedSidePane(
                        activePane: _activeSidePane,
                        collapsed: _sidePaneCollapsed,
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
                          onOpenTasks: () {
                            controller.navigateTo(WorkspaceDestination.tasks);
                          },
                          onOpenSkills: () {
                            controller.navigateTo(WorkspaceDestination.skills);
                          },
                          onSelectTask: (sessionKey) async {
                            await controller.switchSession(sessionKey);
                            _focusComposer();
                          },
                          onArchiveTask: _archiveTask,
                          overviewExpanded: _taskRailOverviewExpanded,
                          onToggleOverview: () {
                            setState(() {
                              _taskRailOverviewExpanded =
                                  !_taskRailOverviewExpanded;
                            });
                          },
                        ),
                        navigationPanel: widget.navigationPanelBuilder!(
                          sidePanelContentWidth,
                        ),
                        onSelectPane: (pane) {
                          setState(() {
                            if (_activeSidePane == pane) {
                              _sidePaneCollapsed = !_sidePaneCollapsed;
                              return;
                            }
                            _activeSidePane = pane;
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
                        width: 10,
                        child: PaneResizeHandle(
                          axis: Axis.horizontal,
                          onDelta: (delta) {
                            setState(() {
                              _threadRailWidth = (_threadRailWidth + delta)
                                  .clamp(232.0, maxThreadRailWidth)
                                  .toDouble();
                            });
                          },
                        ),
                      ),
                    const SizedBox(width: 6),
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
                      onOpenTasks: () {
                        controller.navigateTo(WorkspaceDestination.tasks);
                      },
                      onOpenSkills: () {
                        controller.navigateTo(WorkspaceDestination.skills);
                      },
                      onSelectTask: (sessionKey) async {
                        await controller.switchSession(sessionKey);
                        _focusComposer();
                      },
                      onArchiveTask: _archiveTask,
                      overviewExpanded: _taskRailOverviewExpanded,
                      onToggleOverview: () {
                        setState(() {
                          _taskRailOverviewExpanded =
                              !_taskRailOverviewExpanded;
                        });
                      },
                    ),
                  ),
                  SizedBox(
                    width: 10,
                    child: PaneResizeHandle(
                      axis: Axis.horizontal,
                      onDelta: (delta) {
                        setState(() {
                          _threadRailWidth = (_threadRailWidth + delta)
                              .clamp(232.0, maxThreadRailWidth)
                              .toDouble();
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 6),
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
        const handleHeight = 10.0;
        const paneGap = 6.0;
        final availablePaneHeight =
            (constraints.maxHeight - handleHeight - paneGap)
                .clamp(0.0, double.infinity)
                .toDouble();
        var minConversationHeight = availablePaneHeight >= 620
            ? 240.0
            : availablePaneHeight * 0.4;
        var minComposerHeight = availablePaneHeight >= 620
            ? 176.0
            : availablePaneHeight * 0.24;
        if (minConversationHeight + minComposerHeight > availablePaneHeight) {
          minConversationHeight = availablePaneHeight * 0.52;
          minComposerHeight = availablePaneHeight - minConversationHeight;
        }
        final maxConversationHeight = (availablePaneHeight - minComposerHeight)
            .clamp(minConversationHeight, availablePaneHeight)
            .toDouble();
        final conversationHeight = availablePaneHeight <= 0
            ? 0.0
            : (_conversationPaneRatio * availablePaneHeight)
                  .clamp(minConversationHeight, maxConversationHeight)
                  .toDouble();
        final composerHeight = (availablePaneHeight - conversationHeight)
            .clamp(minComposerHeight, availablePaneHeight)
            .toDouble();

        return Column(
          children: [
            SizedBox(
              height: conversationHeight,
              child: _ConversationArea(
                controller: controller,
                currentTask: currentTask,
                items: timelineItems,
                scrollController: _conversationController,
                onOpenDetail: widget.onOpenDetail,
                onFocusComposer: _focusComposer,
                onOpenGateway: _showConnectDialog,
                onReconnectGateway: _connectFromSavedSettingsOrShowDialog,
              ),
            ),
            SizedBox(
              height: handleHeight,
              child: PaneResizeHandle(
                axis: Axis.vertical,
                onDelta: (delta) {
                  if (availablePaneHeight <= 0) {
                    return;
                  }
                  final nextHeight = (conversationHeight + delta).clamp(
                    minConversationHeight,
                    maxConversationHeight,
                  );
                  setState(() {
                    _conversationPaneRatio = nextHeight / availablePaneHeight;
                  });
                },
              ),
            ),
            const SizedBox(height: paneGap),
            SizedBox(
              height: composerHeight,
              child: _AssistantLowerPane(
                inputController: _inputController,
                focusNode: _composerFocusNode,
                mode: _mode,
                thinkingLabel: _thinkingLabel,
                modelLabel: controller.resolvedDefaultModel.isEmpty
                    ? appText('未选择模型', 'No model selected')
                    : controller.resolvedDefaultModel,
                modelOptions: controller.aiGatewayModelChoices,
                attachments: _attachments,
                autoAgentLabel: _lastAutoAgentLabel,
                controller: controller,
                onModeChanged: (value) => setState(() => _mode = value),
                onThinkingChanged: (value) {
                  setState(() => _thinkingLabel = value);
                },
                onModelChanged: controller.selectDefaultModel,
                onRemoveAttachment: (attachment) {
                  setState(() {
                    _attachments = _attachments
                        .where((item) => item.path != attachment.path)
                        .toList(growable: false);
                  });
                },
                onOpenGateway: _showConnectDialog,
                onReconnectGateway: _connectFromSavedSettingsOrShowDialog,
                onPickAttachments: _pickAttachments,
                onFocusComposer: _focusComposer,
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
            label: _lastAutoAgentLabel ?? controller.activeAgentName,
            text: message.text,
            pending: message.pending,
            error: message.error,
          ),
        );
      }
    }

    final hasPendingTask =
        controller.chatController.hasPendingRun ||
        controller.activeRunId != null;
    final lastRole = messages.isEmpty ? null : messages.last.role.toLowerCase();
    if (_lastSubmittedPrompt != null) {
      final status = hasPendingTask
          ? 'running'
          : (lastRole == 'user' ? 'queued' : 'completed');
      items.add(
        _TimelineItem.taskCard(
          title: _lastSubmittedPrompt!,
          status: status,
          summary: switch (status) {
            'queued' => appText('已提交到任务队列', 'Submitted to the task queue'),
            'running' => appText(
              '正在由 ${_lastAutoAgentLabel ?? controller.activeAgentName} 执行',
              'Executing with ${_lastAutoAgentLabel ?? controller.activeAgentName}',
            ),
            _ => appText(
              '本次会话中的执行已结束',
              'Execution finished in this conversation',
            ),
          },
          detail: _lastSubmittedAttachments.isEmpty
              ? '${controller.currentSessionKey} · ${_lastAutoAgentLabel ?? controller.activeAgentName}'
              : appText(
                  '${controller.currentSessionKey} · ${_lastSubmittedAttachments.length} 个附件',
                  '${controller.currentSessionKey} · ${_lastSubmittedAttachments.length} attachment(s)',
                ),
          owner: _lastAutoAgentLabel ?? controller.activeAgentName,
          sessionKey: controller.currentSessionKey,
        ),
      );
    }

    return items;
  }

  Future<void> _pickAttachments() async {
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
    final settings = controller.settings;
    final rawPrompt = _inputController.text.trim();
    if (rawPrompt.isEmpty) {
      return;
    }

    final autoAgent = _pickAutoAgent(controller, rawPrompt);
    if (autoAgent != null) {
      await controller.selectAgent(autoAgent.id);
    }

    final attachmentNames = _attachments
        .map((item) => item.name)
        .toList(growable: false);
    final prompt = _composePrompt(
      mode: _mode,
      prompt: rawPrompt,
      attachmentNames: attachmentNames,
      executionTarget: settings.assistantExecutionTarget,
      permissionLevel: settings.assistantPermissionLevel,
      workspacePath: settings.workspacePath,
      remoteProjectRoot: settings.remoteProjectRoot,
    );

    setState(() {
      _lastSubmittedPrompt = rawPrompt;
      _lastAutoAgentLabel = autoAgent?.name ?? controller.activeAgentName;
      _lastSubmittedAttachments = attachmentNames;
      _touchTaskSeed(
        sessionKey: controller.currentSessionKey,
        title:
            _taskSeeds[controller.currentSessionKey]?.title ??
            _fallbackSessionTitle(controller.currentSessionKey),
        preview: rawPrompt,
        status:
            controller.connection.status == RuntimeConnectionStatus.connected
            ? 'running'
            : 'queued',
        owner: autoAgent?.name ?? controller.activeAgentName,
        surface: 'Assistant',
        draft: controller.currentSessionKey.trim().startsWith('draft:'),
      );
    });

    final attachmentPayloads = await _buildAttachmentPayloads(_attachments);
    await controller.sendChatMessage(
      prompt,
      thinking: _thinkingLabel,
      attachments: attachmentPayloads,
    );

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

  String _composePrompt({
    required String mode,
    required String prompt,
    required List<String> attachmentNames,
    required AssistantExecutionTarget executionTarget,
    required AssistantPermissionLevel permissionLevel,
    required String workspacePath,
    required String remoteProjectRoot,
  }) {
    final attachmentBlock = attachmentNames.isEmpty
        ? ''
        : 'Attached files:\n${attachmentNames.map((name) => '- $name').join('\n')}\n\n';
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
        '$attachmentBlock$executionContext'
            'Craft a polished result for this request:\n$prompt',
      'plan' =>
        '$attachmentBlock$executionContext'
            'Create a clear execution plan for this task:\n$prompt',
      _ => '$attachmentBlock$executionContext$prompt',
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

  void _focusComposer() {
    if (!mounted) {
      return;
    }
    _composerFocusNode.requestFocus();
  }

  Future<void> _createNewThread() async {
    final sessionKey = _buildDraftSessionKey(widget.controller);
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
        owner: widget.controller.activeAgentName,
        surface: 'Assistant',
        draft: true,
      );
    });
    await widget.controller.switchSession(sessionKey);
    _focusComposer();
  }

  List<_AssistantTaskEntry> _buildTaskEntries(AppController controller) {
    _synchronizeTaskSeeds(controller);
    final entries =
        _taskSeeds.values
            .where((item) => !_isArchivedTask(item.sessionKey))
            .map(
              (item) => item.toEntry(
                isCurrent: _sessionKeysMatch(
                  item.sessionKey,
                  controller.currentSessionKey,
                ),
              ),
            )
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
      title: _fallbackSessionTitle(sessionKey),
      preview: '',
      status: 'queued',
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
      owner: widget.controller.activeAgentName,
      surface: 'Assistant',
      isCurrent: true,
      draft: true,
    );
  }

  void _synchronizeTaskSeeds(AppController controller) {
    for (final session in controller.sessions) {
      if (_isArchivedTask(session.key)) {
        continue;
      }
      _taskSeeds[session.key] = _AssistantTaskSeed(
        sessionKey: session.key,
        title: _sessionDisplayTitle(session),
        preview:
            _sessionPreview(session) ??
            appText('等待继续执行这个任务', 'Waiting to continue this task'),
        status: _sessionStatus(
          session,
          currentSessionKey: controller.currentSessionKey,
          hasPendingRun: controller.chatController.hasPendingRun,
        ),
        updatedAtMs:
            session.updatedAtMs ??
            DateTime.now().millisecondsSinceEpoch.toDouble(),
        owner: controller.activeAgentName,
        surface: session.surface ?? session.kind ?? 'Assistant',
        draft: session.key.trim().startsWith('draft:'),
      );
    }

    if (_isArchivedTask(controller.currentSessionKey)) {
      return;
    }
    _taskSeeds.putIfAbsent(
      controller.currentSessionKey,
      () => _AssistantTaskSeed(
        sessionKey: controller.currentSessionKey,
        title: _fallbackSessionTitle(controller.currentSessionKey),
        preview: appText(
          '等待描述这个任务的第一条消息',
          'Waiting for the first message of this task',
        ),
        status: 'queued',
        updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
        owner: controller.activeAgentName,
        surface: 'Assistant',
        draft: controller.currentSessionKey.trim().startsWith('draft:'),
      ),
    );
  }

  void _touchTaskSeed({
    required String sessionKey,
    required String title,
    required String preview,
    required String status,
    required String owner,
    required String surface,
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
    setState(() {
      _archivedTaskKeys.add(sessionKey);
      _taskSeeds.removeWhere((key, _) => _sessionKeysMatch(key, sessionKey));
    });

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

  String _buildDraftSessionKey(AppController controller) {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final selectedAgentId = controller.selectedAgentId.trim();
    if (selectedAgentId.isEmpty) {
      return 'draft:$stamp';
    }
    return 'draft:$selectedAgentId:$stamp';
  }
}

enum _AssistantSidePane { tasks, navigation }

class _AssistantUnifiedSidePane extends StatelessWidget {
  const _AssistantUnifiedSidePane({
    required this.activePane,
    required this.collapsed,
    required this.taskPanel,
    required this.navigationPanel,
    required this.onSelectPane,
    required this.onToggleCollapsed,
  });

  final _AssistantSidePane activePane;
  final bool collapsed;
  final Widget taskPanel;
  final Widget navigationPanel;
  final ValueChanged<_AssistantSidePane> onSelectPane;
  final VoidCallback onToggleCollapsed;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _AssistantSideTabRail(
          activePane: activePane,
          collapsed: collapsed,
          onSelectPane: onSelectPane,
          onToggleCollapsed: onToggleCollapsed,
        ),
        if (!collapsed) ...[
          const SizedBox(width: 6),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: activePane == _AssistantSidePane.tasks
                  ? KeyedSubtree(
                      key: const ValueKey<String>('assistant-side-pane-tasks'),
                      child: taskPanel,
                    )
                  : KeyedSubtree(
                      key: const ValueKey<String>(
                        'assistant-side-pane-navigation',
                      ),
                      child: navigationPanel,
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
    required this.collapsed,
    required this.onSelectPane,
    required this.onToggleCollapsed,
  });

  final _AssistantSidePane activePane;
  final bool collapsed;
  final ValueChanged<_AssistantSidePane> onSelectPane;
  final VoidCallback onToggleCollapsed;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      key: const Key('assistant-side-pane'),
      width: 58,
      decoration: BoxDecoration(
        color: palette.sidebar,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: palette.sidebarBorder.withValues(alpha: 0.72),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 8),
          _AssistantSideTabButton(
            key: const Key('assistant-side-pane-tab-tasks'),
            icon: Icons.checklist_rtl_rounded,
            selected: activePane == _AssistantSidePane.tasks,
            tooltip: appText('任务', 'Tasks'),
            onTap: () => onSelectPane(_AssistantSidePane.tasks),
          ),
          const SizedBox(height: 6),
          _AssistantSideTabButton(
            key: const Key('assistant-side-pane-tab-navigation'),
            icon: Icons.dashboard_customize_outlined,
            selected: activePane == _AssistantSidePane.navigation,
            tooltip: appText('导航', 'Navigation'),
            onTap: () => onSelectPane(_AssistantSidePane.navigation),
          ),
          const Spacer(),
          IconButton(
            key: const Key('assistant-side-pane-toggle'),
            tooltip: collapsed
                ? appText('展开侧板', 'Expand side pane')
                : appText('收起侧板', 'Collapse side pane'),
            onPressed: onToggleCollapsed,
            icon: Icon(
              collapsed
                  ? Icons.keyboard_double_arrow_right_rounded
                  : Icons.keyboard_double_arrow_left_rounded,
              size: 18,
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _AssistantSideTabButton extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: selected ? palette.accentMuted : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              icon,
              size: 20,
              color: selected ? palette.accent : palette.textSecondary,
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
    required this.mode,
    required this.thinkingLabel,
    required this.modelLabel,
    required this.modelOptions,
    required this.attachments,
    required this.autoAgentLabel,
    required this.onModeChanged,
    required this.onThinkingChanged,
    required this.onModelChanged,
    required this.onRemoveAttachment,
    required this.onOpenGateway,
    required this.onReconnectGateway,
    required this.onPickAttachments,
    required this.onFocusComposer,
    required this.onSend,
  });

  final AppController controller;
  final TextEditingController inputController;
  final FocusNode focusNode;
  final String mode;
  final String thinkingLabel;
  final String modelLabel;
  final List<String> modelOptions;
  final List<_ComposerAttachment> attachments;
  final String? autoAgentLabel;
  final ValueChanged<String> onModeChanged;
  final ValueChanged<String> onThinkingChanged;
  final Future<void> Function(String modelId) onModelChanged;
  final ValueChanged<_ComposerAttachment> onRemoveAttachment;
  final VoidCallback onOpenGateway;
  final Future<void> Function() onReconnectGateway;
  final VoidCallback onPickAttachments;
  final VoidCallback onFocusComposer;
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
          mode: mode,
          thinkingLabel: thinkingLabel,
          modelLabel: modelLabel,
          modelOptions: modelOptions,
          attachments: attachments,
          autoAgentLabel: autoAgentLabel,
          onModeChanged: onModeChanged,
          onThinkingChanged: onThinkingChanged,
          onModelChanged: onModelChanged,
          onRemoveAttachment: onRemoveAttachment,
          onOpenGateway: onOpenGateway,
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
    required this.scrollController,
    required this.onOpenDetail,
    required this.onFocusComposer,
    required this.onOpenGateway,
    required this.onReconnectGateway,
  });

  final AppController controller;
  final _AssistantTaskEntry currentTask;
  final List<_TimelineItem> items;
  final ScrollController scrollController;
  final ValueChanged<DetailPanelData> onOpenDetail;
  final VoidCallback onFocusComposer;
  final VoidCallback onOpenGateway;
  final Future<void> Function() onReconnectGateway;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    final statusStyle = _pillStyleForStatus(context, currentTask.status);
    final taskHint =
        controller.connection.status == RuntimeConnectionStatus.connected
        ? appText(
            '当前对话会作为任务上下文持续执行，切换左侧任务即可回到对应会话。',
            'This conversation stays attached to the selected task. Pick another task on the left to jump back into it.',
          )
        : appText(
            '连接 Gateway 后，当前对话会自动作为默认任务开始执行。',
            'After connecting a gateway, this conversation starts as the default task.',
          );

    return SurfaceCard(
      borderRadius: 12,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppBreadcrumbs(
                        items: [
                          AppBreadcrumbItem(
                            label: appText('主页', 'Home'),
                            icon: Icons.home_rounded,
                            onTap: controller.navigateHome,
                          ),
                          AppBreadcrumbItem(label: currentTask.title),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        currentTask.title,
                        key: const Key('assistant-conversation-title'),
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(taskHint, style: theme.textTheme.bodySmall),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
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
                        ],
                      ),
                    ],
                  ),
                ),
                _ConnectionChip(controller: controller),
              ],
            ),
          ),
          Divider(height: 1, color: palette.strokeSoft),
          Expanded(
            child: Container(
              color: palette.surfaceSecondary,
              child: items.isEmpty
                  ? _AssistantEmptyState(
                      controller: controller,
                      onFocusComposer: onFocusComposer,
                      onOpenGateway: onOpenGateway,
                      onReconnectGateway: onReconnectGateway,
                    )
                  : ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      physics: const BouncingScrollPhysics(),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return switch (item.kind) {
                          _TimelineItemKind.user => _MessageBubble(
                            label: item.label!,
                            text: item.text!,
                            alignRight: true,
                            tone: _BubbleTone.user,
                          ),
                          _TimelineItemKind.assistant => _MessageBubble(
                            label: item.label!,
                            text: item.text!,
                            alignRight: false,
                            tone: _BubbleTone.assistant,
                          ),
                          _TimelineItemKind.agent => _MessageBubble(
                            label: item.label!,
                            text: item.text!,
                            alignRight: false,
                            tone: _BubbleTone.agent,
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
                              onOpenDetail(_buildTaskDetail(item));
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

  DetailPanelData _buildTaskDetail(_TimelineItem item) {
    return DetailPanelData(
      title: item.title!,
      subtitle: appText('会话任务', 'Conversation Task'),
      icon: Icons.task_alt_rounded,
      status: _statusInfoForTask(item.status ?? 'completed'),
      description: item.summary ?? '',
      meta: [
        item.owner ?? appText('自动路由', 'Auto route'),
        item.sessionKey ?? controller.currentSessionKey,
      ],
      actions: [appText('继续', 'Continue'), appText('打开任务', 'Open Tasks')],
      sections: [
        DetailSection(
          title: appText('执行', 'Execution'),
          items: [
            DetailItem(
              label: appText('状态', 'Status'),
              value: _taskStatusLabel(item.status ?? 'completed'),
            ),
            DetailItem(
              label: appText('代理', 'Agent'),
              value: item.owner ?? controller.activeAgentName,
            ),
            DetailItem(
              label: appText('会话', 'Session'),
              value: item.sessionKey ?? controller.currentSessionKey,
            ),
            DetailItem(
              label: appText('详情', 'Detail'),
              value: item.detail ?? appText('暂无详情', 'No detail'),
            ),
          ],
        ),
      ],
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
    required this.onOpenTasks,
    required this.onOpenSkills,
    required this.onSelectTask,
    required this.onArchiveTask,
    required this.overviewExpanded,
    required this.onToggleOverview,
  });

  final AppController controller;
  final List<_AssistantTaskEntry> tasks;
  final String query;
  final TextEditingController searchController;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onClearQuery;
  final Future<void> Function() onRefreshTasks;
  final Future<void> Function() onCreateTask;
  final VoidCallback onOpenTasks;
  final VoidCallback onOpenSkills;
  final Future<void> Function(String sessionKey) onSelectTask;
  final Future<void> Function(String sessionKey) onArchiveTask;
  final bool overviewExpanded;
  final VoidCallback onToggleOverview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    final runningCount = tasks
        .where((task) => _normalizedTaskStatus(task.status) == 'running')
        .length;
    final completedCount = tasks
        .where((task) => _normalizedTaskStatus(task.status) == 'completed')
        .length;

    return SurfaceCard(
      borderRadius: 16,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
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
                    const SizedBox(width: 8),
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
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    key: const Key('assistant-new-task-button'),
                    onPressed: () async {
                      await onCreateTask();
                    },
                    icon: const Icon(Icons.edit_note_rounded),
                    label: Text(appText('新对话', 'New conversation')),
                  ),
                ),
                const SizedBox(height: 12),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: palette.surfaceSecondary,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: palette.strokeSoft),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InkWell(
                        key: const Key('assistant-task-overview-toggle'),
                        borderRadius: BorderRadius.circular(12),
                        onTap: onToggleOverview,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      appText(
                                        '当前对话就是默认任务',
                                        'This chat is the default task',
                                      ),
                                      style: theme.textTheme.titleSmall
                                          ?.copyWith(
                                            color: theme.colorScheme.onSurface,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      appText(
                                        '点击展开任务说明与快捷入口',
                                        'Tap to expand task guidance and shortcuts',
                                      ),
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: palette.textSecondary,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                overviewExpanded
                                    ? Icons.keyboard_arrow_up_rounded
                                    : Icons.keyboard_arrow_down_rounded,
                                color: palette.textMuted,
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (overviewExpanded) ...[
                        const SizedBox(height: 10),
                        Text(
                          appText(
                            '左侧选择任一任务，会直接切到这个任务对应的会话上下文。',
                            'Selecting a task on the left jumps straight into that task conversation.',
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: palette.textSecondary,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _MetaPill(
                              label:
                                  '${appText('运行中', 'Running')} $runningCount',
                              icon: Icons.play_circle_outline_rounded,
                            ),
                            _MetaPill(
                              label:
                                  '${appText('已完成', 'Completed')} $completedCount',
                              icon: Icons.check_circle_outline_rounded,
                            ),
                            _MetaPill(
                              label:
                                  '${appText('技能', 'Skills')} ${controller.skills.length}',
                              icon: Icons.auto_awesome_rounded,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            TextButton.icon(
                              onPressed: onOpenTasks,
                              icon: const Icon(Icons.layers_outlined, size: 18),
                              label: Text(appText('打开任务页', 'Open tasks')),
                            ),
                            TextButton.icon(
                              onPressed: onOpenSkills,
                              icon: const Icon(Icons.hub_outlined, size: 18),
                              label: Text(appText('查看技能', 'Open skills')),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: palette.strokeSoft),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Row(
              children: [
                Text(
                  appText('任务列表', 'Task list'),
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(width: 8),
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
                      padding: const EdgeInsets.all(16),
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
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    itemCount: tasks.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final task = tasks[index];
                      return _AssistantTaskTile(
                        entry: task,
                        onTap: () async {
                          await onSelectTask(task.sessionKey);
                        },
                        onArchive: () async {
                          await onArchiveTask(task.sessionKey);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _AssistantTaskTile extends StatelessWidget {
  const _AssistantTaskTile({
    required this.entry,
    required this.onTap,
    required this.onArchive,
  });

  final _AssistantTaskEntry entry;
  final VoidCallback onTap;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    final statusStyle = _pillStyleForStatus(context, entry.status);

    return Material(
      color: entry.isCurrent
          ? palette.accentMuted.withValues(alpha: 0.55)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        key: ValueKey<String>('assistant-task-item-${entry.sessionKey}'),
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: entry.isCurrent ? palette.accent : palette.strokeSoft,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: statusStyle.backgroundColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      entry.draft
                          ? Icons.edit_note_rounded
                          : _normalizedTaskStatus(entry.status) == 'running'
                          ? Icons.play_arrow_rounded
                          : Icons.task_alt_rounded,
                      size: 18,
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
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
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
                        splashRadius: 16,
                        onPressed: onArchive,
                        icon: Icon(
                          Icons.archive_outlined,
                          size: 18,
                          color: palette.textMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                entry.preview,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: palette.textSecondary,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _StatusPill(
                    label: entry.draft
                        ? appText('草稿任务', 'Draft task')
                        : _taskStatusLabel(entry.status),
                    backgroundColor: statusStyle.backgroundColor,
                    textColor: statusStyle.foregroundColor,
                  ),
                  _MetaPill(label: entry.owner, icon: Icons.smart_toy_outlined),
                  _MetaPill(label: entry.surface, icon: Icons.forum_outlined),
                  if (entry.isCurrent)
                    Text(
                      appText('当前', 'Current'),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: palette.textMuted,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AssistantEmptyState extends StatelessWidget {
  const _AssistantEmptyState({
    required this.controller,
    required this.onFocusComposer,
    required this.onOpenGateway,
    required this.onReconnectGateway,
  });

  final AppController controller;
  final VoidCallback onFocusComposer;
  final VoidCallback onOpenGateway;
  final Future<void> Function() onReconnectGateway;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connection = controller.connection;
    final connected = connection.status == RuntimeConnectionStatus.connected;
    final reconnectAvailable = controller.canQuickConnectGateway;
    final title = connected
        ? appText('开始对话或运行任务', 'Start a chat or run a task')
        : connection.status == RuntimeConnectionStatus.error
        ? appText('Gateway 连接失败', 'Gateway connection failed')
        : appText('先连接 Gateway', 'Connect a gateway first');
    final description = connected
        ? appText(
            '输入需求后即可开始执行，结果会回到当前会话并同步到任务页。',
            'Type a request to start execution. Results return to this session and the Tasks page.',
          )
        : connection.pairingRequired
        ? appText(
            '当前设备还没通过 Gateway 配对审批。请先在已授权设备上批准该 pairing request，再重新连接。',
            'This device has not been approved yet. Approve the pairing request from an authorized device, then reconnect.',
          )
        : connection.gatewayTokenMissing
        ? appText(
            '首次连接需要共享 Token；配对完成后可继续使用本机的 device token。',
            'The first connection requires a shared token; after pairing, this device can continue with its device token.',
          )
        : (connection.lastError?.trim().isNotEmpty == true
              ? connection.lastError!.trim()
              : appText(
                  '连接后可直接对话、创建任务，并在当前会话查看结果。',
                  'After connecting, you can chat, create tasks, and read results in this session.',
                ));

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SurfaceCard(
            borderRadius: 12,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(description, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: connected
                          ? onFocusComposer
                          : reconnectAvailable
                          ? () async {
                              await onReconnectGateway();
                            }
                          : onOpenGateway,
                      icon: Icon(
                        connected
                            ? Icons.edit_rounded
                            : reconnectAvailable
                            ? Icons.refresh_rounded
                            : Icons.link_rounded,
                      ),
                      label: Text(
                        connected
                            ? appText('开始输入', 'Start typing')
                            : reconnectAvailable
                            ? appText('重新连接', 'Reconnect')
                            : appText('连接 Gateway', 'Connect gateway'),
                      ),
                    ),
                    if (!connected)
                      OutlinedButton.icon(
                        onPressed: onOpenGateway,
                        icon: const Icon(Icons.settings_rounded),
                        label: Text(appText('编辑连接', 'Edit connection')),
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

class _ComposerBar extends StatelessWidget {
  const _ComposerBar({
    required this.controller,
    required this.inputController,
    required this.focusNode,
    required this.mode,
    required this.thinkingLabel,
    required this.modelLabel,
    required this.modelOptions,
    required this.attachments,
    required this.autoAgentLabel,
    required this.onModeChanged,
    required this.onThinkingChanged,
    required this.onModelChanged,
    required this.onRemoveAttachment,
    required this.onOpenGateway,
    required this.onReconnectGateway,
    required this.onPickAttachments,
    required this.onSend,
  });

  final AppController controller;
  final TextEditingController inputController;
  final FocusNode focusNode;
  final String mode;
  final String thinkingLabel;
  final String modelLabel;
  final List<String> modelOptions;
  final List<_ComposerAttachment> attachments;
  final String? autoAgentLabel;
  final ValueChanged<String> onModeChanged;
  final ValueChanged<String> onThinkingChanged;
  final Future<void> Function(String modelId) onModelChanged;
  final ValueChanged<_ComposerAttachment> onRemoveAttachment;
  final VoidCallback onOpenGateway;
  final Future<void> Function() onReconnectGateway;
  final VoidCallback onPickAttachments;
  final Future<void> Function() onSend;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final connected =
        controller.connection.status == RuntimeConnectionStatus.connected;
    final reconnectAvailable = controller.canQuickConnectGateway;
    final connecting =
        controller.connection.status == RuntimeConnectionStatus.connecting;
    final executionTarget = controller.assistantExecutionTarget;
    final permissionLevel = controller.assistantPermissionLevel;
    final permissionForegroundColor =
        permissionLevel == AssistantPermissionLevel.fullAccess
        ? const Color(0xFFE16A12)
        : palette.textSecondary;
    final permissionBackgroundColor =
        permissionLevel == AssistantPermissionLevel.fullAccess
        ? const Color(0xFFFFF1E7)
        : palette.surfaceSecondary;
    final permissionBorderColor =
        permissionLevel == AssistantPermissionLevel.fullAccess
        ? const Color(0xFFFFD5B5)
        : palette.strokeSoft;
    final submitLabel = connected
        ? (mode == 'ask'
              ? appText('提交', 'Submit')
              : appText('运行任务', 'Run Task'))
        : connecting
        ? appText('连接中…', 'Connecting…')
        : reconnectAvailable
        ? appText('重连', 'Reconnect')
        : appText('连接', 'Connect');

    return SurfaceCard(
      borderRadius: 12,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (attachments.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: attachments
                  .map(
                    (attachment) => InputChip(
                      avatar: Icon(attachment.icon, size: 16),
                      label: Text(attachment.name),
                      onDeleted: () => onRemoveAttachment(attachment),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 8),
          ],
          TextField(
            controller: inputController,
            focusNode: focusNode,
            autofocus: true,
            minLines: 2,
            maxLines: 6,
            decoration: InputDecoration(
              border: InputBorder.none,
              isCollapsed: true,
              hintText: appText(
                '直接描述需求：运行任务、分析日志、部署节点……',
                'Type naturally: run job autopilot, analyze logs, deploy node…',
              ),
            ),
            onSubmitted: (_) => onSend(),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PopupMenuButton<String>(
                        tooltip: appText('输入区操作', 'Composer actions'),
                        offset: const Offset(0, -180),
                        onSelected: (value) {
                          switch (value) {
                            case 'attach':
                              onPickAttachments();
                              break;
                            case 'plan':
                              onModeChanged(mode == 'plan' ? 'ask' : 'plan');
                              break;
                            case 'gateway':
                              onOpenGateway();
                              break;
                            case 'route':
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
                          PopupMenuItem<String>(
                            value: 'plan',
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                mode == 'plan'
                                    ? Icons.task_alt_rounded
                                    : Icons.alt_route_rounded,
                              ),
                              title: Text(
                                mode == 'plan'
                                    ? appText('退出计划模式', 'Exit plan mode')
                                    : appText('计划模式', 'Plan mode'),
                              ),
                            ),
                          ),
                          PopupMenuItem<String>(
                            value: 'gateway',
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                connected
                                    ? Icons.lan_rounded
                                    : Icons.link_rounded,
                              ),
                              title: Text(appText('连接网关', 'Connect gateway')),
                            ),
                          ),
                          PopupMenuItem<String>(
                            value: 'route',
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.hub_rounded),
                              title: Text(
                                autoAgentLabel ??
                                    appText(
                                      '浏览器 / 编码 / 研究',
                                      'Browser / Coding / Research',
                                    ),
                              ),
                            ),
                          ),
                        ],
                        child: const _ComposerIconButton(
                          icon: Icons.add_rounded,
                        ),
                      ),
                      const SizedBox(width: 8),
                      PopupMenuButton<AssistantExecutionTarget>(
                        tooltip: appText('执行目标', 'Execution target'),
                        onSelected: (value) {
                          controller.setAssistantExecutionTarget(value);
                        },
                        itemBuilder: (context) => AssistantExecutionTarget
                            .values
                            .map(
                              (value) =>
                                  PopupMenuItem<AssistantExecutionTarget>(
                                    value: value,
                                    child: Row(
                                      children: [
                                        Icon(value.icon, size: 18),
                                        const SizedBox(width: 10),
                                        Expanded(child: Text(value.label)),
                                        if (value == executionTarget)
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
                          icon: executionTarget.icon,
                          label: executionTarget.label,
                          showChevron: true,
                          maxLabelWidth: 72,
                        ),
                      ),
                      const SizedBox(width: 8),
                      PopupMenuButton<AssistantPermissionLevel>(
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
                                        Icon(
                                          value.icon,
                                          size: 18,
                                          color:
                                              value ==
                                                  AssistantPermissionLevel
                                                      .fullAccess
                                              ? const Color(0xFFE16A12)
                                              : null,
                                        ),
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
                          maxLabelWidth: 112,
                          backgroundColor: permissionBackgroundColor,
                          borderColor: permissionBorderColor,
                          foregroundColor: permissionForegroundColor,
                        ),
                      ),
                      const SizedBox(width: 8),
                      modelOptions.isEmpty
                          ? _ComposerToolbarChip(
                              icon: Icons.bolt_rounded,
                              label: modelLabel,
                              showChevron: false,
                            )
                          : PopupMenuButton<String>(
                              tooltip: appText('模型', 'Model'),
                              onSelected: (value) {
                                onModelChanged(value);
                              },
                              itemBuilder: (context) => modelOptions
                                  .map(
                                    (value) => PopupMenuItem<String>(
                                      value: value,
                                      child: Row(
                                        children: [
                                          Expanded(child: Text(value)),
                                          if (value == modelLabel)
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
                                label: modelLabel,
                                showChevron: true,
                              ),
                            ),
                      const SizedBox(width: 8),
                      PopupMenuButton<String>(
                        tooltip: appText('模式', 'Mode'),
                        onSelected: onModeChanged,
                        itemBuilder: (context) => _AssistantPageState._modes
                            .map(
                              (value) => PopupMenuItem<String>(
                                value: value,
                                child: Text(_assistantModeLabel(value)),
                              ),
                            )
                            .toList(),
                        child: _ComposerToolbarChip(
                          icon: Icons.tune_rounded,
                          label: _assistantModeLabel(mode),
                          showChevron: true,
                        ),
                      ),
                      const SizedBox(width: 8),
                      PopupMenuButton<String>(
                        tooltip: appText('推理强度', 'Reasoning'),
                        onSelected: onThinkingChanged,
                        itemBuilder: (context) => _AssistantPageState
                            ._thinkingModes
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
                                    if (value == thinkingLabel)
                                      const Icon(Icons.check_rounded, size: 18),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                        child: _ComposerToolbarChip(
                          icon: Icons.psychology_alt_outlined,
                          label: _assistantThinkingLabel(thinkingLabel),
                          showChevron: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Tooltip(
                message: submitLabel,
                child: FilledButton(
                  onPressed: connecting
                      ? null
                      : connected
                      ? onSend
                      : reconnectAvailable
                      ? () async {
                          await onReconnectGateway();
                        }
                      : onOpenGateway,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    minimumSize: const Size(80, 34),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        connected
                            ? (mode == 'ask'
                                  ? Icons.arrow_upward_rounded
                                  : Icons.play_arrow_rounded)
                            : reconnectAvailable
                            ? Icons.refresh_rounded
                            : Icons.link_rounded,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
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

class _ComposerIconButton extends StatelessWidget {
  const _ComposerIconButton({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: context.palette.surfaceSecondary,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.palette.strokeSoft),
      ),
      child: Icon(icon, size: 16, color: context.palette.textMuted),
    );
  }
}

class _ComposerToolbarChip extends StatelessWidget {
  const _ComposerToolbarChip({
    required this.icon,
    required this.label,
    required this.showChevron,
    this.backgroundColor,
    this.borderColor,
    this.foregroundColor,
    this.maxLabelWidth = 220,
  });

  final IconData icon;
  final String label;
  final bool showChevron;
  final Color? backgroundColor;
  final Color? borderColor;
  final Color? foregroundColor;
  final double maxLabelWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: backgroundColor ?? palette.surfaceSecondary,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(color: borderColor ?? palette.strokeSoft),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: foregroundColor ?? palette.textMuted),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxLabelWidth),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                color: foregroundColor ?? theme.colorScheme.onSurface,
              ),
            ),
          ),
          if (showChevron) ...[
            const SizedBox(width: 2),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 14,
              color: foregroundColor ?? palette.textMuted,
            ),
          ],
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.label,
    required this.text,
    required this.alignRight,
    required this.tone,
  });

  final String label;
  final String text;
  final bool alignRight;
  final _BubbleTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    final borderColor = switch (tone) {
      _BubbleTone.user => theme.colorScheme.primary.withValues(alpha: 0.18),
      _BubbleTone.agent => theme.colorScheme.tertiary.withValues(alpha: 0.18),
      _BubbleTone.assistant => palette.strokeSoft,
    };

    return Align(
      alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              SelectableText(
                text.isEmpty ? appText('暂无内容。', 'No content yet.') : text,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurface,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: palette.strokeSoft),
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
            color: Colors.white,
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
                      const SizedBox(width: 8),
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
    final connection = controller.connection;
    final color = switch (connection.status) {
      RuntimeConnectionStatus.connected => theme.colorScheme.primaryContainer,
      RuntimeConnectionStatus.connecting =>
        theme.colorScheme.secondaryContainer,
      RuntimeConnectionStatus.error => theme.colorScheme.errorContainer,
      RuntimeConnectionStatus.offline =>
        theme.colorScheme.surfaceContainerHighest,
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Text(
        '${connection.status.label} · ${connection.remoteAddress ?? appText('未连接目标', 'No target')}',
        style: theme.textTheme.labelMedium,
      ),
    );
  }
}

extension on AssistantExecutionTarget {
  IconData get icon => switch (this) {
    AssistantExecutionTarget.local => Icons.computer_outlined,
    AssistantExecutionTarget.remote => Icons.cloud_outlined,
  };
}

extension on AssistantPermissionLevel {
  IconData get icon => switch (this) {
    AssistantPermissionLevel.defaultAccess => Icons.shield_outlined,
    AssistantPermissionLevel.fullAccess => Icons.admin_panel_settings_outlined,
  };
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
    required this.draft,
  });

  final String sessionKey;
  final String title;
  final String preview;
  final String status;
  final double updatedAtMs;
  final String owner;
  final String surface;
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
  final bool isCurrent;
  final bool draft;

  String get updatedAtLabel => _sessionUpdatedAtLabel(updatedAtMs);
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
      backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.10),
      foregroundColor: theme.colorScheme.primary,
    ),
    'queued' => _PillStyle(
      backgroundColor: theme.colorScheme.secondary.withValues(alpha: 0.10),
      foregroundColor: theme.colorScheme.secondary,
    ),
    'failed' || 'error' => _PillStyle(
      backgroundColor: theme.colorScheme.error.withValues(alpha: 0.10),
      foregroundColor: theme.colorScheme.error,
    ),
    _ => _PillStyle(
      backgroundColor: theme.colorScheme.tertiary.withValues(alpha: 0.12),
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
  _ => StatusInfo(appText('已完成', 'Completed'), StatusTone.success),
};

String _normalizedTaskStatus(String status) {
  final value = status.trim().toLowerCase();
  return switch (value) {
    'running' => 'running',
    'queued' => 'queued',
    'failed' => 'failed',
    'error' => 'error',
    _ => 'completed',
  };
}

String _taskStatusLabel(String status) => _statusInfoForTask(status).label;

String _toolCallStatusLabel(String status) =>
    switch (_normalizedTaskStatus(status)) {
      'running' => appText('运行中', 'Running'),
      'failed' || 'error' => appText('错误', 'Error'),
      _ => appText('已完成', 'Completed'),
    };

String _assistantModeLabel(String mode) => switch (mode) {
  'craft' => appText('创作', 'Craft'),
  'plan' => appText('计划', 'Plan'),
  _ => appText('问答', 'Ask'),
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
  required String currentSessionKey,
  required bool hasPendingRun,
}) {
  if (session.abortedLastRun == true) {
    return 'failed';
  }
  if (hasPendingRun && _sessionKeysMatch(session.key, currentSessionKey)) {
    return 'running';
  }
  if ((session.lastMessagePreview ?? '').trim().isEmpty) {
    return 'queued';
  }
  return 'completed';
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
