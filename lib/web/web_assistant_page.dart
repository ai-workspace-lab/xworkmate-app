import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../app/app_controller_web.dart';
import '../app/ui_feature_manifest.dart';
import '../i18n/app_language.dart';
import '../models/app_models.dart';
import '../runtime/runtime_models.dart';
import '../theme/app_palette.dart';
import '../widgets/desktop_workspace_scaffold.dart';
import '../widgets/status_badge.dart';
import '../widgets/surface_card.dart';
import '../widgets/top_bar.dart';

class WebAssistantPage extends StatefulWidget {
  const WebAssistantPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<WebAssistantPage> createState() => _WebAssistantPageState();
}

class _WebAssistantPageState extends State<WebAssistantPage> {
  final TextEditingController _inputController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  String _query = '';
  String _thinkingLevel = 'medium';
  AssistantPermissionLevel _permissionLevel =
      AssistantPermissionLevel.defaultAccess;
  bool _useMultiAgent = false;
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
        final uiFeatures = controller.featuresFor(UiFeaturePlatform.web);
        final allSingle = controller.conversationsForTarget(
          AssistantExecutionTarget.singleAgent,
        );
        final allLocal = controller.conversationsForTarget(
          AssistantExecutionTarget.local,
        );
        final allRemote = controller.conversationsForTarget(
          AssistantExecutionTarget.remote,
        );
        final single = _filterConversations(allSingle);
        final local = _filterConversations(allLocal);
        final remote = _filterConversations(allRemote);

        final availableTargets = uiFeatures.availableExecutionTargets;
        final currentTarget = controller.assistantExecutionTarget;
        final connectionState = controller.currentAssistantConnectionState;
        final connected = connectionState.ready;

        final currentMessages = controller.chatMessages;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(
              _scrollController.position.maxScrollExtent,
            );
          }
        });

        final selectedSkillKeys = controller.assistantSelectedSkillKeysForSession(
          controller.currentSessionKey,
        );
        final importedSkills = controller.assistantImportedSkillsForSession(
          controller.currentSessionKey,
        );

        return DesktopWorkspaceScaffold(
          breadcrumbs: <AppBreadcrumbItem>[
            AppBreadcrumbItem(
              label: appText('主页', 'Home'),
              icon: Icons.home_rounded,
              onTap: controller.navigateHome,
            ),
            AppBreadcrumbItem(label: WorkspaceDestination.assistant.label),
          ],
          eyebrow: appText('Web Workspace', 'Web Workspace'),
          title: appText('助手', 'Assistant'),
          subtitle: appText(
            'Web 助手保持任务线程会话隔离，支持 Single Agent / Local / Remote 三种模式。',
            'Web Assistant keeps per-thread session isolation with Single Agent / Local / Remote modes.',
          ),
          toolbar: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: () => controller.createConversation(
                  target: controller.assistantExecutionTarget,
                ),
                icon: const Icon(Icons.edit_square),
                label: Text(appText('新对话', 'New conversation')),
              ),
              OutlinedButton.icon(
                onPressed: () => controller.openSettings(tab: SettingsTab.gateway),
                icon: const Icon(Icons.tune_rounded),
                label: Text(appText('连接设置', 'Connection settings')),
              ),
              _TargetChip(
                targets: availableTargets,
                value: currentTarget,
                onChanged: (value) {
                  if (value != null) {
                    controller.setAssistantExecutionTarget(value);
                  }
                },
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final vertical = constraints.maxWidth < 1080;
              final rail = _ConversationRail(
                controller: controller,
                query: _query,
                searchController: _searchController,
                onQueryChanged: (value) {
                  setState(() => _query = value.trim().toLowerCase());
                },
                onClearQuery: () {
                  _searchController.clear();
                  setState(() => _query = '');
                },
                showSingle: uiFeatures.supportsDirectAi,
                showLocal: uiFeatures.supportsLocalGateway,
                showRemote: uiFeatures.supportsRelayGateway,
                single: single,
                local: local,
                remote: remote,
                onRename: (sessionKey) => _renameConversation(sessionKey),
                onArchive: (sessionKey) =>
                    controller.saveAssistantTaskArchived(sessionKey, true),
              );

              final panel = _ConversationPanel(
                controller: controller,
                inputController: _inputController,
                scrollController: _scrollController,
                connected: connected,
                currentMessages: currentMessages,
                connectionState: connectionState,
                thinkingLevel: _thinkingLevel,
                permissionLevel: _permissionLevel,
                useMultiAgent: _useMultiAgent,
                importedSkills: importedSkills,
                selectedSkillKeys: selectedSkillKeys,
                attachments: _attachments,
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
                  setState(() {
                    _attachments.removeAt(index);
                  });
                },
                onSubmit: _submitPrompt,
              );

              if (vertical) {
                return Column(
                  children: [
                    SizedBox(height: 320, child: rail),
                    const SizedBox(height: 8),
                    Expanded(child: panel),
                  ],
                );
              }

              return Row(
                children: [
                  SizedBox(width: 340, child: rail),
                  const SizedBox(width: 8),
                  Expanded(child: panel),
                ],
              );
            },
          ),
        );
      },
    );
  }

  List<WebConversationSummary> _filterConversations(
    List<WebConversationSummary> items,
  ) {
    if (_query.isEmpty) {
      return items;
    }
    return items
        .where((item) {
          final haystack = '${item.title}\n${item.preview}'.toLowerCase();
          return haystack.contains(_query);
        })
        .toList(growable: false);
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
    final value = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(appText('重命名任务线程', 'Rename task thread')),
          content: TextField(
            controller: renameController,
            autofocus: true,
            decoration: InputDecoration(
              hintText: appText('输入标题', 'Enter a title'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(appText('取消', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(renameController.text),
              child: Text(appText('保存', 'Save')),
            ),
          ],
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
          extensions: <String>['txt', 'md', 'json', 'csv', 'pdf', 'yaml', 'yml'],
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
              .assistantSelectedSkillKeysForSession(controller.currentSessionKey)
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
    setState(() {
      _attachments.clear();
    });
  }
}

class _ConversationRail extends StatelessWidget {
  const _ConversationRail({
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

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      borderRadius: 10,
      tone: SurfaceCardTone.chrome,
      child: Column(
        key: const Key('assistant-task-rail'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: searchController,
            onChanged: onQueryChanged,
            decoration: InputDecoration(
              hintText: appText('搜索任务线程', 'Search task threads'),
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      onPressed: onClearQuery,
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              children: [
                if (showSingle)
                  _ConversationGroup(
                    title: appText('Single Agent', 'Single Agent'),
                    icon: Icons.hub_rounded,
                    items: single,
                    emptyLabel: appText(
                      '还没有 Single Agent 任务线程',
                      'No Single Agent task threads yet',
                    ),
                    onSelect: controller.switchConversation,
                    onRename: onRename,
                    onArchive: onArchive,
                  ),
                if (showLocal) ...[
                  const SizedBox(height: 12),
                  _ConversationGroup(
                    title: appText('Local Gateway', 'Local Gateway'),
                    icon: Icons.lan_rounded,
                    items: local,
                    emptyLabel: appText(
                      '还没有 Local Gateway 任务线程',
                      'No Local Gateway task threads yet',
                    ),
                    onSelect: controller.switchConversation,
                    onRename: onRename,
                    onArchive: onArchive,
                  ),
                ],
                if (showRemote) ...[
                  const SizedBox(height: 12),
                  _ConversationGroup(
                    title: appText('Remote Gateway', 'Remote Gateway'),
                    icon: Icons.cloud_outlined,
                    items: remote,
                    emptyLabel: appText(
                      '还没有 Remote Gateway 任务线程',
                      'No Remote Gateway task threads yet',
                    ),
                    onSelect: controller.switchConversation,
                    onRename: onRename,
                    onArchive: onArchive,
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

class _ConversationGroup extends StatelessWidget {
  const _ConversationGroup({
    required this.title,
    required this.icon,
    required this.items,
    required this.emptyLabel,
    required this.onSelect,
    required this.onRename,
    required this.onArchive,
  });

  final String title;
  final IconData icon;
  final List<WebConversationSummary> items;
  final String emptyLabel;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onRename;
  final ValueChanged<String> onArchive;

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
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      IconButton(
                        tooltip: appText('重命名', 'Rename'),
                        onPressed: () => onRename(item.sessionKey),
                        icon: const Icon(Icons.drive_file_rename_outline_rounded),
                      ),
                      IconButton(
                        tooltip: appText('归档', 'Archive'),
                        onPressed: () => onArchive(item.sessionKey),
                        icon: const Icon(Icons.archive_outlined),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          item.preview,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: palette.textSecondary),
                        ),
                      ),
                      if (item.pending)
                        const Padding(
                          padding: EdgeInsets.only(left: 8, top: 2),
                          child: SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
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

class _ConversationPanel extends StatelessWidget {
  const _ConversationPanel({
    required this.controller,
    required this.inputController,
    required this.scrollController,
    required this.connected,
    required this.currentMessages,
    required this.connectionState,
    required this.thinkingLevel,
    required this.permissionLevel,
    required this.useMultiAgent,
    required this.importedSkills,
    required this.selectedSkillKeys,
    required this.attachments,
    required this.onThinkingChanged,
    required this.onPermissionChanged,
    required this.onToggleMultiAgent,
    required this.onAddAttachment,
    required this.onRemoveAttachment,
    required this.onSubmit,
  });

  final AppController controller;
  final TextEditingController inputController;
  final ScrollController scrollController;
  final bool connected;
  final List<GatewayChatMessage> currentMessages;
  final AssistantThreadConnectionState connectionState;
  final String thinkingLevel;
  final AssistantPermissionLevel permissionLevel;
  final bool useMultiAgent;
  final List<AssistantThreadSkillEntry> importedSkills;
  final List<String> selectedSkillKeys;
  final List<_WebComposerAttachment> attachments;
  final ValueChanged<String> onThinkingChanged;
  final ValueChanged<AssistantPermissionLevel> onPermissionChanged;
  final ValueChanged<bool> onToggleMultiAgent;
  final Future<void> Function() onAddAttachment;
  final ValueChanged<int> onRemoveAttachment;
  final Future<void> Function() onSubmit;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final currentTarget = controller.assistantExecutionTarget;
    final modelChoices = controller.assistantModelChoices;

    return Column(
      children: [
        SurfaceCard(
          borderRadius: 10,
          tone: SurfaceCardTone.chrome,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          controller.currentConversationTitle,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          controller.assistantConnectionTargetLabel,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: palette.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  StatusBadge(
                    status: StatusInfo(
                      controller.assistantConnectionStatusLabel,
                      connected ? StatusTone.success : StatusTone.warning,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _CompactDropdown<AssistantExecutionTarget>(
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
                  if (currentTarget == AssistantExecutionTarget.singleAgent)
                    _CompactDropdown<SingleAgentProvider>(
                      key: const Key('assistant-single-agent-provider-button'),
                      value: controller.currentSingleAgentProvider,
                      items: controller.singleAgentProviderOptions,
                      labelBuilder: (item) => item.label,
                      onChanged: (value) {
                        if (value != null) {
                          controller.setSingleAgentProvider(value);
                        }
                      },
                    ),
                  if (modelChoices.isNotEmpty)
                    _CompactDropdown<String>(
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
                  _CompactDropdown<AssistantMessageViewMode>(
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
                  _CompactDropdown<String>(
                    key: const Key('assistant-thinking-button'),
                    value: thinkingLevel,
                    items: const <String>['low', 'medium', 'high'],
                    labelBuilder: _thinkingLabel,
                    onChanged: (value) {
                      if (value != null) {
                        onThinkingChanged(value);
                      }
                    },
                  ),
                  _CompactDropdown<AssistantPermissionLevel>(
                    key: const Key('assistant-permission-button'),
                    value: permissionLevel,
                    items: AssistantPermissionLevel.values,
                    labelBuilder: (item) => item.label,
                    onChanged: (value) {
                      if (value != null) {
                        onPermissionChanged(value);
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
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
                const SizedBox(width: 12),
                FilledButton.tonal(
                  onPressed: () => controller.openSettings(tab: SettingsTab.gateway),
                  child: Text(appText('打开设置', 'Open settings')),
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
                if (importedSkills.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: importedSkills.map((skill) {
                          final selected = selectedSkillKeys.contains(skill.key);
                          return FilterChip(
                            label: Text(skill.label),
                            selected: selected,
                            onSelected: (_) => controller.toggleAssistantSkillForSession(
                              controller.currentSessionKey,
                              skill.key,
                            ),
                          );
                        }).toList(growable: false),
                      ),
                    ),
                  ),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: currentMessages.length,
                    itemBuilder: (context, index) {
                      final message = currentMessages[index];
                      return _MessageBubble(message: message);
                    },
                  ),
                ),
                Container(height: 1, color: palette.strokeSoft),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      if (attachments.isNotEmpty)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (var index = 0; index < attachments.length; index++)
                                InputChip(
                                  avatar: Icon(attachments[index].icon, size: 16),
                                  label: Text(attachments[index].name),
                                  onDeleted: () => onRemoveAttachment(index),
                                ),
                            ],
                          ),
                        ),
                      if (attachments.isNotEmpty) const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: inputController,
                              minLines: 3,
                              maxLines: 8,
                              decoration: InputDecoration(
                                hintText: appText(
                                  '输入任务说明、上下文和期望输出',
                                  'Describe the task, context, and expected output',
                                ),
                              ),
                              onSubmitted: (_) {
                                if (connected) {
                                  onSubmit();
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Row(
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
                          const SizedBox(width: 8),
                          IconButton(
                            key: const Key('assistant-attachment-menu-button'),
                            tooltip: appText('添加附件', 'Add attachment'),
                            onPressed: onAddAttachment,
                            icon: const Icon(Icons.attach_file_rounded),
                          ),
                          Expanded(
                            child: Text(
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
                          ),
                          const SizedBox(width: 12),
                          FilledButton.icon(
                            onPressed: connected ? onSubmit : null,
                            icon: controller.relayBusy || controller.acpBusy
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.arrow_upward_rounded),
                            label: Text(appText('发送', 'Send')),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
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

class _TargetChip extends StatelessWidget {
  const _TargetChip({
    required this.targets,
    required this.value,
    required this.onChanged,
  });

  final List<AssistantExecutionTarget> targets;
  final AssistantExecutionTarget value;
  final ValueChanged<AssistantExecutionTarget?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<AssistantExecutionTarget>(
        value: value,
        onChanged: onChanged,
        items: targets
            .map(
              (target) => DropdownMenuItem<AssistantExecutionTarget>(
                value: target,
                child: Text(_targetLabel(target)),
              ),
            )
            .toList(growable: false),
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
    AssistantExecutionTarget.singleAgent => appText(
      'Single Agent',
      'Single Agent',
    ),
    AssistantExecutionTarget.local => appText(
      'Local Gateway',
      'Local Gateway',
    ),
    AssistantExecutionTarget.remote => appText(
      'Remote Gateway',
      'Remote Gateway',
    ),
  };
}
