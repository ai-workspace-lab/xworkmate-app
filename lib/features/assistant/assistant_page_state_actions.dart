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
import '../../runtime/runtime_models.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../widgets/assistant_focus_panel.dart';
import '../../widgets/assistant_artifact_sidebar.dart';
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

extension AssistantPageStateActionsInternal on AssistantPageStateInternal {
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
      workspacePath: controller.assistantWorkspacePathForSession(
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
        AssistantPageStateInternal.mainWorkspaceMinWidthInternal -
        AssistantPageStateInternal.sidePaneViewportPaddingInternal -
        assistantHorizontalResizeHandleWidthInternal -
        assistantHorizontalPaneGapInternal;
    return maxWidthByViewport
        .clamp(
          AssistantPageStateInternal.sidePaneMinWidthInternal,
          viewportWidth -
              AssistantPageStateInternal.sidePaneViewportPaddingInternal,
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
