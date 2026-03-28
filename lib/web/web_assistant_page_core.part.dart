part of 'web_assistant_page.dart';

const double _webAssistantSideTabRailWidth = 46;
const double _webAssistantSidePaneMinWidth = 304;
const double _webAssistantSidePaneMaxWidth = 420;
const double _webAssistantMainWorkspaceMinWidth = 700;
const double _webAssistantComposerMinHeight = 164;
const double _webAssistantConversationMinHeight = 200;
const double _webAssistantResizeHandleSize = 10;
const double _webAssistantArtifactPaneMinWidth = 280;
const double _webAssistantArtifactPaneDefaultWidth = 360;

class WebAssistantPage extends StatefulWidget {
  const WebAssistantPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<WebAssistantPage> createState() => _WebAssistantPageState();
}

enum _WebAssistantPane { tasks, quick }

class _WebAssistantPageState extends State<WebAssistantPage> {
  final TextEditingController _inputController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  String _query = '';
  String _thinkingLevel = 'medium';
  AssistantPermissionLevel _permissionLevel =
      AssistantPermissionLevel.defaultAccess;
  bool _useMultiAgent = false;
  bool _workspaceChromeCollapsed = false;
  bool _sidePaneCollapsed = false;
  double _sidePaneWidth = 344;
  bool _artifactPaneCollapsed = true;
  double _artifactPaneWidth = _webAssistantArtifactPaneDefaultWidth;
  double _composerHeight = 196;
  _WebAssistantPane _activePane = _WebAssistantPane.tasks;
  final List<_WebComposerAttachment> _attachments = <_WebComposerAttachment>[];

  @override
  void dispose() {
    _inputController.dispose();
    _searchController.dispose();
    _scrollController.dispose();
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
          if (!mounted || !_scrollController.hasClients) {
            return;
          }
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
          );
        });

        return DesktopWorkspaceScaffold(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxSidePaneWidth = math.min(
                _webAssistantSidePaneMaxWidth,
                math.max(
                  _webAssistantSidePaneMinWidth,
                  constraints.maxWidth - _webAssistantMainWorkspaceMinWidth,
                ),
              );
              final sidePaneWidth = _sidePaneWidth.clamp(
                _webAssistantSidePaneMinWidth,
                maxSidePaneWidth,
              );
              final collapsedWidth = _webAssistantSideTabRailWidth;

              return Column(
                children: [
                  _AssistantWorkspaceChrome(
                    controller: controller,
                    collapsed: _workspaceChromeCollapsed,
                    onToggleCollapsed: () {
                      setState(() {
                        _workspaceChromeCollapsed = !_workspaceChromeCollapsed;
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
                          width: _sidePaneCollapsed
                              ? collapsedWidth
                              : sidePaneWidth,
                          child: _AssistantSidePane(
                            collapsed: _sidePaneCollapsed,
                            activePane: _activePane,
                            controller: controller,
                            query: _query,
                            searchController: _searchController,
                            permissionLevel: _permissionLevel,
                            onQueryChanged: (value) {
                              setState(
                                () => _query = value.trim().toLowerCase(),
                              );
                            },
                            onClearQuery: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                            onToggleCollapsed: () {
                              setState(() {
                                _sidePaneCollapsed = !_sidePaneCollapsed;
                              });
                            },
                            onPaneChanged: (pane) {
                              setState(() {
                                _activePane = pane;
                                _sidePaneCollapsed = false;
                              });
                            },
                            onPermissionChanged: (value) {
                              setState(() => _permissionLevel = value);
                            },
                            onRename: _renameConversation,
                            onArchive: (sessionKey) => controller
                                .saveAssistantTaskArchived(sessionKey, true),
                            onOpenActions: _openConversationActions,
                          ),
                        ),
                        if (!_sidePaneCollapsed)
                          SizedBox(
                            width: 8,
                            child: PaneResizeHandle(
                              axis: Axis.horizontal,
                              onDelta: (delta) {
                                setState(() {
                                  _sidePaneWidth = (_sidePaneWidth + delta)
                                      .clamp(
                                        _webAssistantSidePaneMinWidth,
                                        maxSidePaneWidth,
                                      )
                                      .toDouble();
                                });
                              },
                            ),
                          ),
                        Expanded(
                          child: _buildWorkspaceWithArtifacts(
                            controller: controller,
                            child: _ConversationWorkspace(
                              controller: controller,
                              scrollController: _scrollController,
                              inputController: _inputController,
                              currentMessages: currentMessages,
                              connectionState: connectionState,
                              thinkingLevel: _thinkingLevel,
                              permissionLevel: _permissionLevel,
                              useMultiAgent: _useMultiAgent,
                              attachments: _attachments,
                              composerHeight: _composerHeight,
                              onComposerHeightChanged: (value) {
                                setState(() => _composerHeight = value);
                              },
                              onThinkingChanged: (value) {
                                setState(() => _thinkingLevel = value);
                              },
                              onPermissionChanged: (value) {
                                setState(() => _permissionLevel = value);
                              },
                              onToggleMultiAgent: (value) {
                                setState(() => _useMultiAgent = value);
                              },
                              onAddAttachment: _pickAttachments,
                              onRemoveAttachment: (index) {
                                setState(() => _attachments.removeAt(index));
                              },
                              onOpenSessionSettings: _openSessionSettings,
                              onSubmit: _submitPrompt,
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

  Future<void> _openSessionSettings() async {
    if (!mounted) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return _AssistantSessionSettingsSheet(
          controller: widget.controller,
          thinkingLevel: _thinkingLevel,
          permissionLevel: _permissionLevel,
          onThinkingChanged: (value) {
            setState(() => _thinkingLevel = value);
          },
          onPermissionChanged: (value) {
            setState(() => _permissionLevel = value);
          },
        );
      },
    );
  }

  Future<void> _openConversationActions(String sessionKey) async {
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
                  _renameConversation(sessionKey);
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

  Future<void> _renameConversation(String sessionKey) async {
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

  Future<void> _pickAttachments() async {
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
      _attachments.addAll(files.map(_WebComposerAttachment.fromXFile));
    });
  }

  Future<void> _submitPrompt() async {
    final controller = widget.controller;
    final value = _inputController.text.trim();
    if (value.isEmpty) {
      return;
    }

    final payloads = <GatewayChatAttachmentPayload>[];
    for (final attachment in _attachments) {
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
      thinking: _thinkingLevel,
      attachments: payloads,
      selectedSkillLabels: selectedSkillLabels,
      useMultiAgent: _useMultiAgent,
    );

    if (!mounted) {
      return;
    }
    _inputController.clear();
    setState(() => _attachments.clear());
  }

  Widget _buildWorkspaceWithArtifacts({
    required AppController controller,
    required Widget child,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxPaneWidth = math.min(
          520.0,
          math.max(
            _webAssistantArtifactPaneMinWidth,
            constraints.maxWidth * 0.48,
          ),
        );
        final paneWidth = _artifactPaneWidth
            .clamp(_webAssistantArtifactPaneMinWidth, maxPaneWidth)
            .toDouble();
        final workspace = Row(
          children: [
            Expanded(child: child),
            if (!_artifactPaneCollapsed) ...[
              SizedBox(
                key: const Key('assistant-artifact-pane-resize-handle'),
                width: 8,
                child: PaneResizeHandle(
                  axis: Axis.horizontal,
                  onDelta: (delta) {
                    setState(() {
                      _artifactPaneWidth = (_artifactPaneWidth - delta)
                          .clamp(
                            _webAssistantArtifactPaneMinWidth,
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
                  workspaceRef: controller.assistantWorkspaceRefForSession(
                    controller.currentSessionKey,
                  ),
                  workspaceRefKind: controller
                      .assistantWorkspaceRefKindForSession(
                        controller.currentSessionKey,
                      ),
                  onCollapse: () {
                    setState(() {
                      _artifactPaneCollapsed = true;
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
            Positioned.fill(child: workspace),
            if (_artifactPaneCollapsed)
              Positioned(
                right: 8,
                top: 12,
                child: AssistantArtifactSidebarRevealButton(
                  onTap: () {
                    setState(() {
                      _artifactPaneCollapsed = false;
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
