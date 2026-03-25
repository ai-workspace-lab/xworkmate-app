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
                top: math.max(12.0, (constraints.maxHeight - 56) / 2),
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

class _AssistantWorkspaceChrome extends StatelessWidget {
  const _AssistantWorkspaceChrome({
    required this.controller,
    required this.collapsed,
    required this.onToggleCollapsed,
  });

  final AppController controller;
  final bool collapsed;
  final VoidCallback onToggleCollapsed;

  @override
  Widget build(BuildContext context) {
    final connectionState = controller.currentAssistantConnectionState;
    return SurfaceCard(
      tone: SurfaceCardTone.chrome,
      borderRadius: 10,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        child: collapsed
            ? Row(
                children: [
                  const Expanded(child: _ChromeNavigationPills(compact: true)),
                  _ChromeConnectionChip(state: connectionState, compact: true),
                  const SizedBox(width: 8),
                  IconButton(
                    key: const Key('assistant-workspace-chrome-toggle'),
                    tooltip: appText('展开顶部导航', 'Expand top navigation'),
                    onPressed: onToggleCollapsed,
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(child: _ChromeNavigationPills()),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _ChromeConnectionChip(state: connectionState),
                          const SizedBox(width: 8),
                          IconButton(
                            key: const Key('assistant-workspace-chrome-toggle'),
                            tooltip: appText(
                              '折叠顶部导航',
                              'Collapse top navigation',
                            ),
                            onPressed: onToggleCollapsed,
                            icon: const Icon(Icons.keyboard_arrow_up_rounded),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}

class _ChromeNavigationPills extends StatelessWidget {
  const _ChromeNavigationPills({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _ChromePill(
          icon: Icons.home_rounded,
          label: appText('主页', 'Home'),
          compact: compact,
        ),
        _ChromePill(
          label: WorkspaceDestination.assistant.label,
          emphasized: true,
          compact: compact,
        ),
      ],
    );
  }
}

class _ChromeConnectionChip extends StatelessWidget {
  const _ChromeConnectionChip({required this.state, this.compact = false});

  final AssistantThreadConnectionState state;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    final tone = switch (state.status) {
      RuntimeConnectionStatus.connected => (
        palette.success.withValues(alpha: 0.14),
        palette.success.withValues(alpha: 0.22),
        palette.success,
      ),
      RuntimeConnectionStatus.connecting => (
        palette.accentMuted.withValues(alpha: 0.86),
        palette.accent.withValues(alpha: 0.18),
        palette.accent,
      ),
      RuntimeConnectionStatus.error => (
        palette.danger.withValues(alpha: 0.12),
        palette.danger.withValues(alpha: 0.18),
        palette.textSecondary,
      ),
      RuntimeConnectionStatus.offline => (
        palette.warning.withValues(alpha: 0.12),
        palette.warning.withValues(alpha: 0.18),
        palette.textSecondary,
      ),
    };
    final text = [
      state.primaryLabel.trim(),
      state.detailLabel.trim(),
    ].where((item) => item.isNotEmpty).join(' · ');

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: compact ? 280 : 360),
      child: Container(
        key: const Key('assistant-workspace-status-chip'),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 12,
          vertical: compact ? 6 : 7,
        ),
        decoration: BoxDecoration(
          color: tone.$1,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: tone.$2),
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelLarge?.copyWith(
            color: tone.$3,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.02,
          ),
        ),
      ),
    );
  }
}

class _AssistantSidePane extends StatelessWidget {
  const _AssistantSidePane({
    required this.collapsed,
    required this.activePane,
    required this.controller,
    required this.query,
    required this.searchController,
    required this.permissionLevel,
    required this.onQueryChanged,
    required this.onClearQuery,
    required this.onToggleCollapsed,
    required this.onPaneChanged,
    required this.onPermissionChanged,
    required this.onRename,
    required this.onArchive,
    required this.onOpenActions,
  });

  final bool collapsed;
  final _WebAssistantPane activePane;
  final AppController controller;
  final String query;
  final TextEditingController searchController;
  final AssistantPermissionLevel permissionLevel;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onClearQuery;
  final VoidCallback onToggleCollapsed;
  final ValueChanged<_WebAssistantPane> onPaneChanged;
  final ValueChanged<AssistantPermissionLevel> onPermissionChanged;
  final ValueChanged<String> onRename;
  final ValueChanged<String> onArchive;
  final ValueChanged<String> onOpenActions;

  @override
  Widget build(BuildContext context) {
    final single = controller.conversationsForTarget(
      AssistantExecutionTarget.singleAgent,
    );
    final local = controller.conversationsForTarget(
      AssistantExecutionTarget.local,
    );
    final remote = controller.conversationsForTarget(
      AssistantExecutionTarget.remote,
    );
    final filteredSingle = _filterConversations(single, query);
    final filteredLocal = _filterConversations(local, query);
    final filteredRemote = _filterConversations(remote, query);
    final palette = context.palette;

    return Row(
      children: [
        Container(
          key: const Key('assistant-side-pane'),
          width: _webAssistantSideTabRailWidth,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                palette.chromeHighlight.withValues(alpha: 0.96),
                palette.chromeSurface,
              ],
            ),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: palette.chromeStroke),
            boxShadow: [palette.chromeShadowAmbient],
          ),
          child: Column(
            children: [
              const SizedBox(height: 4),
              _AssistantSideTabButton(
                key: const Key('assistant-side-pane-tab-tasks'),
                icon: Icons.checklist_rtl_rounded,
                selected: activePane == _WebAssistantPane.tasks,
                tooltip: appText('任务', 'Tasks'),
                onTap: () => onPaneChanged(_WebAssistantPane.tasks),
              ),
              const SizedBox(height: 4),
              _AssistantSideTabButton(
                key: const Key('assistant-side-pane-tab-quick'),
                icon: Icons.dashboard_customize_outlined,
                selected: activePane == _WebAssistantPane.quick,
                tooltip: appText('快捷面板', 'Quick panel'),
                onTap: () => onPaneChanged(_WebAssistantPane.quick),
              ),
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
        ),
        if (!collapsed) ...[
          const SizedBox(width: 6),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: KeyedSubtree(
                key: ValueKey<String>('assistant-side-pane-${activePane.name}'),
                child: activePane == _WebAssistantPane.tasks
                    ? _AssistantTaskPane(
                        controller: controller,
                        query: query,
                        searchController: searchController,
                        onQueryChanged: onQueryChanged,
                        onClearQuery: onClearQuery,
                        showSingle: controller
                            .featuresFor(UiFeaturePlatform.web)
                            .supportsDirectAi,
                        showLocal: controller
                            .featuresFor(UiFeaturePlatform.web)
                            .supportsLocalGateway,
                        showRemote: controller
                            .featuresFor(UiFeaturePlatform.web)
                            .supportsRelayGateway,
                        single: filteredSingle,
                        local: filteredLocal,
                        remote: filteredRemote,
                        onRename: onRename,
                        onArchive: onArchive,
                        onOpenActions: onOpenActions,
                      )
                    : _AssistantQuickPane(
                        controller: controller,
                        permissionLevel: permissionLevel,
                        onPermissionChanged: onPermissionChanged,
                      ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _AssistantTaskPane extends StatelessWidget {
  const _AssistantTaskPane({
    required this.controller,
    required this.query,
    required this.searchController,
    required this.onQueryChanged,
    required this.onClearQuery,
    required this.showSingle,
    required this.showLocal,
    required this.showRemote,
    required this.single,
    required this.local,
    required this.remote,
    required this.onRename,
    required this.onArchive,
    required this.onOpenActions,
  });

  final AppController controller;
  final String query;
  final TextEditingController searchController;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onClearQuery;
  final bool showSingle;
  final bool showLocal;
  final bool showRemote;
  final List<WebConversationSummary> single;
  final List<WebConversationSummary> local;
  final List<WebConversationSummary> remote;
  final ValueChanged<String> onRename;
  final ValueChanged<String> onArchive;
  final ValueChanged<String> onOpenActions;

  @override
  Widget build(BuildContext context) {
    final runningCount = controller.conversations
        .where((item) => item.pending)
        .length;
    final threadCount = controller.conversations.length;
    final skillCount = controller.currentAssistantSkillCount;

    return SurfaceCard(
      key: const Key('assistant-task-rail'),
      borderRadius: 10,
      tone: SurfaceCardTone.chrome,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: searchController,
            onChanged: onQueryChanged,
            decoration: InputDecoration(
              hintText: appText('搜索任务', 'Search tasks'),
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      onPressed: onClearQuery,
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: () => controller.createConversation(
              target: controller.assistantExecutionTarget,
            ),
            icon: const Icon(Icons.edit_square),
            label: Text(appText('新对话', 'New conversation')),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(42),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetaChip(
                icon: Icons.play_circle_outline_rounded,
                label: '${appText('运行中', 'Running')} $runningCount',
              ),
              _MetaChip(
                icon: Icons.chat_bubble_outline_rounded,
                label: '${appText('当前', 'Current')} $threadCount',
              ),
              _MetaChip(
                icon: Icons.auto_awesome_rounded,
                label: '${appText('技能', 'Skills')} $skillCount',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              children: [
                if (showSingle)
                  _ConversationGroup(
                    title: appText('单机智能体', 'Single Agent'),
                    icon: Icons.hub_rounded,
                    items: single,
                    emptyLabel: appText(
                      '还没有 Single Agent 任务线程',
                      'No Single Agent task threads yet',
                    ),
                    onSelect: controller.switchConversation,
                    onRename: onRename,
                    onArchive: onArchive,
                    onOpenActions: onOpenActions,
                  ),
                if (showLocal) ...[
                  const SizedBox(height: 12),
                  _ConversationGroup(
                    title: appText('本地 OpenClaw Gateway', 'Local Gateway'),
                    icon: Icons.laptop_mac_rounded,
                    items: local,
                    emptyLabel: appText(
                      '还没有 Local Gateway 任务线程',
                      'No Local Gateway task threads yet',
                    ),
                    onSelect: controller.switchConversation,
                    onRename: onRename,
                    onArchive: onArchive,
                    onOpenActions: onOpenActions,
                  ),
                ],
                if (showRemote) ...[
                  const SizedBox(height: 12),
                  _ConversationGroup(
                    title: appText('远程 OpenClaw Gateway', 'Remote Gateway'),
                    icon: Icons.cloud_outlined,
                    items: remote,
                    emptyLabel: appText(
                      '还没有 Remote Gateway 任务线程',
                      'No Remote Gateway task threads yet',
                    ),
                    onSelect: controller.switchConversation,
                    onRename: onRename,
                    onArchive: onArchive,
                    onOpenActions: onOpenActions,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AssistantQuickPane extends StatelessWidget {
  const _AssistantQuickPane({
    required this.controller,
    required this.permissionLevel,
    required this.onPermissionChanged,
  });

  final AppController controller;
  final AssistantPermissionLevel permissionLevel;
  final ValueChanged<AssistantPermissionLevel> onPermissionChanged;

  @override
  Widget build(BuildContext context) {
    return WebAssistantFocusPanel(controller: controller);
  }
}

class _ConversationGroup extends StatelessWidget {
  const _ConversationGroup({
    required this.title,
    required this.icon,
    required this.items,
    required this.emptyLabel,
    required this.onSelect,
    required this.onRename,
    required this.onArchive,
    required this.onOpenActions,
  });

  final String title;
  final IconData icon;
  final List<WebConversationSummary> items;
  final String emptyLabel;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onRename;
  final ValueChanged<String> onArchive;
  final ValueChanged<String> onOpenActions;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: palette.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$title ${items.length}',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (items.isEmpty)
          Text(
            emptyLabel,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: palette.textSecondary),
          ),
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SurfaceCard(
              onTap: () => onSelect(item.sessionKey),
              borderRadius: 10,
              padding: const EdgeInsets.all(12),
              color: item.current ? palette.accentMuted : null,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      item.pending
                          ? Icons.play_circle_outline_rounded
                          : Icons.check_circle_outline_rounded,
                      size: 18,
                      color: item.pending
                          ? palette.accent
                          : palette.success.withValues(alpha: 0.92),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.preview,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: palette.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _relativeTimeLabel(item.updatedAtMs),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                      const SizedBox(height: 6),
                      IconButton(
                        tooltip: appText('更多操作', 'More actions'),
                        onPressed: () => onOpenActions(item.sessionKey),
                        icon: const Icon(Icons.more_horiz_rounded),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ConversationWorkspace extends StatelessWidget {
  const _ConversationWorkspace({
    required this.controller,
    required this.scrollController,
    required this.inputController,
    required this.currentMessages,
    required this.connectionState,
    required this.thinkingLevel,
    required this.permissionLevel,
    required this.useMultiAgent,
    required this.attachments,
    required this.composerHeight,
    required this.onComposerHeightChanged,
    required this.onThinkingChanged,
    required this.onPermissionChanged,
    required this.onToggleMultiAgent,
    required this.onAddAttachment,
    required this.onRemoveAttachment,
    required this.onOpenSessionSettings,
    required this.onSubmit,
  });

  final AppController controller;
  final ScrollController scrollController;
  final TextEditingController inputController;
  final List<GatewayChatMessage> currentMessages;
  final AssistantThreadConnectionState connectionState;
  final String thinkingLevel;
  final AssistantPermissionLevel permissionLevel;
  final bool useMultiAgent;
  final List<_WebComposerAttachment> attachments;
  final double composerHeight;
  final ValueChanged<double> onComposerHeightChanged;
  final ValueChanged<String> onThinkingChanged;
  final ValueChanged<AssistantPermissionLevel> onPermissionChanged;
  final ValueChanged<bool> onToggleMultiAgent;
  final Future<void> Function() onAddAttachment;
  final ValueChanged<int> onRemoveAttachment;
  final Future<void> Function() onOpenSessionSettings;
  final Future<void> Function() onSubmit;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final palette = context.palette;
        final currentTarget = controller.assistantExecutionTarget;
        final connected = connectionState.ready;
        final maxComposerHeight = math.max(
          _webAssistantComposerMinHeight,
          constraints.maxHeight -
              _webAssistantConversationMinHeight -
              _webAssistantResizeHandleSize,
        );
        final resolvedComposerHeight = composerHeight.clamp(
          _webAssistantComposerMinHeight,
          maxComposerHeight,
        );

        return Column(
          children: [
            if (!connected)
              SurfaceCard(
                borderRadius: 10,
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        currentTarget == AssistantExecutionTarget.singleAgent
                            ? appText(
                                '当前线程未就绪。请检查 Single Agent 配置，或切换到可连接的 Gateway 目标。',
                                'This thread is not ready. Check Single Agent configuration, or switch to a connected gateway target.',
                              )
                            : appText(
                                '当前线程目标网关未连接。请先在 Settings 中 Test / Save / Apply。',
                                'The gateway target for this thread is offline. Use Test / Save / Apply in Settings first.',
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            if (!connected) const SizedBox(height: 8),
            Expanded(
              child: SurfaceCard(
                borderRadius: 10,
                padding: EdgeInsets.zero,
                tone: SurfaceCardTone.chrome,
                child: Column(
                  children: [
                    if (controller
                        .assistantImportedSkillsForSession(
                          controller.currentSessionKey,
                        )
                        .isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: controller
                                .assistantImportedSkillsForSession(
                                  controller.currentSessionKey,
                                )
                                .map((skill) {
                                  final selected = controller
                                      .assistantSelectedSkillKeysForSession(
                                        controller.currentSessionKey,
                                      )
                                      .contains(skill.key);
                                  return FilterChip(
                                    label: Text(skill.label),
                                    selected: selected,
                                    onSelected: (_) => controller
                                        .toggleAssistantSkillForSession(
                                          controller.currentSessionKey,
                                          skill.key,
                                        ),
                                  );
                                })
                                .toList(growable: false),
                          ),
                        ),
                      ),
                    Expanded(
                      child: currentMessages.isEmpty
                          ? _ConversationEmptyState(controller: controller)
                          : ListView.builder(
                              controller: scrollController,
                              padding: const EdgeInsets.all(16),
                              itemCount: currentMessages.length,
                              itemBuilder: (context, index) {
                                return _MessageBubble(
                                  message: currentMessages[index],
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(
              height: _webAssistantResizeHandleSize,
              child: PaneResizeHandle(
                axis: Axis.vertical,
                onDelta: (delta) {
                  onComposerHeightChanged(
                    (resolvedComposerHeight - delta)
                        .clamp(
                          _webAssistantComposerMinHeight,
                          maxComposerHeight,
                        )
                        .toDouble(),
                  );
                },
              ),
            ),
            SizedBox(
              height: resolvedComposerHeight,
              child: SurfaceCard(
                borderRadius: 10,
                tone: SurfaceCardTone.chrome,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (attachments.isNotEmpty) ...[
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (
                            var index = 0;
                            index < attachments.length;
                            index++
                          )
                            InputChip(
                              avatar: Icon(attachments[index].icon, size: 16),
                              label: Text(attachments[index].name),
                              onDeleted: () => onRemoveAttachment(index),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                    ],
                    Expanded(
                      child: TextField(
                        controller: inputController,
                        minLines: null,
                        maxLines: null,
                        expands: true,
                        decoration: InputDecoration(
                          hintText: appText(
                            '输入任务说明、补充上下文，XWorkmate 会沿用当前任务上下文持续处理。',
                            'Describe the task and add context. XWorkmate keeps working in the current task context.',
                          ),
                          alignLabelWithHint: true,
                        ),
                        textAlignVertical: TextAlignVertical.top,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        OutlinedButton.icon(
                          key: const Key('assistant-session-settings-button'),
                          onPressed: onOpenSessionSettings,
                          icon: const Icon(Icons.tune_rounded),
                          label: Text(appText('会话设置', 'Session settings')),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Checkbox(
                              value: useMultiAgent,
                              onChanged: (value) {
                                onToggleMultiAgent(value ?? false);
                              },
                            ),
                            Text(appText('Multi-Agent', 'Multi-Agent')),
                          ],
                        ),
                        Container(
                          decoration: BoxDecoration(
                            color: palette.surfacePrimary,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: palette.strokeSoft),
                          ),
                          child: IconButton(
                            key: const Key('assistant-attachment-menu-button'),
                            tooltip: appText('添加附件', 'Add attachment'),
                            onPressed: onAddAttachment,
                            icon: const Icon(Icons.attach_file_rounded),
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: connected ? onSubmit : null,
                          icon: controller.relayBusy || controller.acpBusy
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.arrow_upward_rounded),
                          label: Text(appText('发送', 'Send')),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      controller.lastAssistantError?.trim().isNotEmpty == true
                          ? controller.lastAssistantError!.trim()
                          : appText(
                              '附件仅支持手动选择，单次总量上限 10MB。',
                              'Attachments are explicit user picks only, with a 10MB total limit per send.',
                            ),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _AssistantSessionSettingsSheet extends StatefulWidget {
  const _AssistantSessionSettingsSheet({
    required this.controller,
    required this.thinkingLevel,
    required this.permissionLevel,
    required this.onThinkingChanged,
    required this.onPermissionChanged,
  });

  final AppController controller;
  final String thinkingLevel;
  final AssistantPermissionLevel permissionLevel;
  final ValueChanged<String> onThinkingChanged;
  final ValueChanged<AssistantPermissionLevel> onPermissionChanged;

  @override
  State<_AssistantSessionSettingsSheet> createState() =>
      _AssistantSessionSettingsSheetState();
}

class _AssistantSessionSettingsSheetState
    extends State<_AssistantSessionSettingsSheet> {
  late String _thinkingLevel = widget.thinkingLevel;
  late AssistantPermissionLevel _permissionLevel = widget.permissionLevel;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        final currentTarget = controller.assistantExecutionTarget;
        final modelChoices = controller.assistantModelChoices;
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              0,
              16,
              MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    appText('会话设置', 'Session settings'),
                    key: const Key('assistant-session-settings-sheet-title'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    appText(
                      '线程模式、渲染方式和执行参数统一放到底部对话框管理。',
                      'Manage thread mode, rendering, and execution parameters from this bottom sheet.',
                    ),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SessionSettingField(
                    label: appText('执行目标', 'Execution target'),
                    child: _HeaderDropdownShell(
                      child: _CompactDropdown<AssistantExecutionTarget>(
                        key: const Key('assistant-target-button'),
                        value: currentTarget,
                        items: controller
                            .featuresFor(UiFeaturePlatform.web)
                            .availableExecutionTargets,
                        labelBuilder: _targetLabel,
                        onChanged: (value) {
                          if (value != null) {
                            controller.setAssistantExecutionTarget(value);
                          }
                        },
                      ),
                    ),
                  ),
                  if (currentTarget == AssistantExecutionTarget.singleAgent)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: _SessionSettingField(
                        label: appText('Provider', 'Provider'),
                        child: _HeaderDropdownShell(
                          child: _CompactDropdown<SingleAgentProvider>(
                            key: const Key(
                              'assistant-single-agent-provider-button',
                            ),
                            value: controller.currentSingleAgentProvider,
                            items: controller.singleAgentProviderOptions,
                            labelBuilder: (item) => item.label,
                            onChanged: (value) {
                              if (value != null) {
                                controller.setSingleAgentProvider(value);
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                  if (modelChoices.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: _SessionSettingField(
                        label: appText('模型', 'Model'),
                        child: _HeaderDropdownShell(
                          child: _CompactDropdown<String>(
                            key: const Key('assistant-model-button'),
                            value: controller.resolvedAssistantModel,
                            items: modelChoices,
                            labelBuilder: (item) => item,
                            onChanged: (value) {
                              if (value != null) {
                                controller.selectAssistantModel(value);
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _SessionSettingField(
                      label: appText('消息视图', 'Message view'),
                      child: _HeaderDropdownShell(
                        child: _CompactDropdown<AssistantMessageViewMode>(
                          key: const Key('assistant-message-view-mode-button'),
                          value: controller.currentAssistantMessageViewMode,
                          items: AssistantMessageViewMode.values,
                          labelBuilder: (item) => item.label,
                          onChanged: (value) {
                            if (value != null) {
                              controller.setAssistantMessageViewMode(value);
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _SessionSettingField(
                      label: appText('思考强度', 'Thinking level'),
                      child: _HeaderDropdownShell(
                        child: _CompactDropdown<String>(
                          key: const Key('assistant-thinking-button'),
                          value: _thinkingLevel,
                          items: const <String>['low', 'medium', 'high'],
                          labelBuilder: _thinkingLabel,
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _thinkingLevel = value);
                              widget.onThinkingChanged(value);
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _SessionSettingField(
                      label: appText('权限', 'Permissions'),
                      child: _HeaderDropdownShell(
                        child: _CompactDropdown<AssistantPermissionLevel>(
                          key: const Key('assistant-permission-button'),
                          value: _permissionLevel,
                          items: AssistantPermissionLevel.values,
                          labelBuilder: (item) => item.label,
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _permissionLevel = value);
                              widget.onPermissionChanged(value);
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ConversationEmptyState extends StatelessWidget {
  const _ConversationEmptyState({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: palette.surfaceSecondary,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  Icons.chat_bubble_outline_rounded,
                  color: palette.accent,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                appText('开始这个任务线程', 'Start this task thread'),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                appText(
                  '保持当前线程模式与上下文，在底部 composer 中直接输入需求即可。',
                  'Keep the current thread mode and context, then start from the composer below.',
                ),
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: palette.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final GatewayChatMessage message;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final assistant = message.role.trim().toLowerCase() == 'assistant';
    final color = message.error
        ? palette.danger.withValues(alpha: 0.14)
        : assistant
        ? palette.surfacePrimary
        : palette.accentMuted;

    return Align(
      alignment: assistant ? Alignment.centerLeft : Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: palette.strokeSoft),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    assistant ? 'Assistant' : 'You',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(message.text),
                ],
              ),
            ),
          ),
        ),
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
                          palette.chromeSurfacePressed,
                        ],
                      )
                    : null,
                color: widget.selected || _hovered ? null : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: widget.selected
                      ? palette.accent.withValues(alpha: 0.28)
                      : Colors.transparent,
                ),
              ),
              child: Icon(
                widget.icon,
                size: 18,
                color: widget.selected ? palette.accent : palette.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChromePill extends StatelessWidget {
  const _ChromePill({
    this.icon,
    required this.label,
    this.emphasized = false,
    this.compact = false,
  });

  final IconData? icon;
  final String label;
  final bool emphasized;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 14,
        vertical: compact ? 8 : 10,
      ),
      decoration: BoxDecoration(
        color: emphasized ? palette.surfacePrimary : palette.surfaceSecondary,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.strokeSoft),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 16), const SizedBox(width: 8)],
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: emphasized ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderDropdownShell extends StatelessWidget {
  const _HeaderDropdownShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: context.palette.surfacePrimary,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: context.palette.strokeSoft),
      ),
      child: child,
    );
  }
}

class _SessionSettingField extends StatelessWidget {
  const _SessionSettingField({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: context.palette.surfacePrimary,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: context.palette.strokeSoft),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: context.palette.textSecondary),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _CompactDropdown<T> extends StatelessWidget {
  const _CompactDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.labelBuilder,
    required this.onChanged,
  });

  final T value;
  final List<T> items;
  final String Function(T item) labelBuilder;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }
    return DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        value: items.contains(value) ? value : items.first,
        onChanged: onChanged,
        items: items
            .map(
              (item) => DropdownMenuItem<T>(
                value: item,
                child: Text(labelBuilder(item)),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _WebComposerAttachment {
  const _WebComposerAttachment({
    required this.file,
    required this.name,
    required this.mimeType,
    required this.icon,
  });

  final XFile file;
  final String name;
  final String mimeType;
  final IconData icon;

  factory _WebComposerAttachment.fromXFile(XFile file) {
    final extension = file.name.split('.').last.toLowerCase();
    final mimeType = file.mimeType?.trim().isNotEmpty == true
        ? file.mimeType!.trim()
        : switch (extension) {
            'png' => 'image/png',
            'jpg' || 'jpeg' => 'image/jpeg',
            'gif' => 'image/gif',
            'webp' => 'image/webp',
            'json' => 'application/json',
            'csv' => 'text/csv',
            'txt' || 'log' || 'md' || 'yaml' || 'yml' => 'text/plain',
            'pdf' => 'application/pdf',
            _ => 'application/octet-stream',
          };
    final icon = mimeType.startsWith('image/')
        ? Icons.image_outlined
        : mimeType == 'application/pdf'
        ? Icons.picture_as_pdf_outlined
        : Icons.insert_drive_file_outlined;
    return _WebComposerAttachment(
      file: file,
      name: file.name,
      mimeType: mimeType,
      icon: icon,
    );
  }
}

List<WebConversationSummary> _filterConversations(
  List<WebConversationSummary> items,
  String query,
) {
  if (query.trim().isEmpty) {
    return items;
  }
  final normalized = query.trim().toLowerCase();
  return items
      .where((item) {
        final haystack = '${item.title}\n${item.preview}'.toLowerCase();
        return haystack.contains(normalized);
      })
      .toList(growable: false);
}

String _relativeTimeLabel(double updatedAtMs) {
  final delta = DateTime.now().difference(
    DateTime.fromMillisecondsSinceEpoch(updatedAtMs.round()),
  );
  if (delta.inMinutes < 1) {
    return appText('刚刚', 'now');
  }
  if (delta.inHours < 1) {
    return '${delta.inMinutes}m';
  }
  if (delta.inDays < 1) {
    return '${delta.inHours}h';
  }
  return '${delta.inDays}d';
}

String _thinkingLabel(String level) {
  return switch (level) {
    'low' => appText('低', 'Low'),
    'medium' => appText('中', 'Medium'),
    'high' => appText('高', 'High'),
    _ => level,
  };
}

String _targetLabel(AssistantExecutionTarget target) {
  return switch (target) {
    AssistantExecutionTarget.singleAgent => appText('单机智能体', 'Single Agent'),
    AssistantExecutionTarget.local => appText(
      '本地 OpenClaw Gateway',
      'Local Gateway',
    ),
    AssistantExecutionTarget.remote => appText(
      '远程 OpenClaw Gateway',
      'Remote Gateway',
    ),
  };
}
