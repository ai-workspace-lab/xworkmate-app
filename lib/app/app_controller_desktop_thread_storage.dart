// ignore_for_file: unused_import, unnecessary_import

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'app_metadata.dart';
import 'app_capabilities.dart';
import 'app_store_policy.dart';
import 'ui_feature_manifest.dart';
import '../i18n/app_language.dart';
import '../models/app_models.dart';
import '../runtime/device_identity_store.dart';

import '../runtime/runtime_bootstrap.dart';
import '../runtime/desktop_platform_service.dart';
import '../runtime/gateway_runtime.dart';
import '../runtime/runtime_controllers.dart';
import '../runtime/runtime_models.dart';
import '../runtime/secure_config_store.dart';
import '../runtime/embedded_agent_launch_policy.dart';
import '../runtime/runtime_coordinator.dart';
import '../runtime/gateway_acp_client.dart';
import '../runtime/codex_runtime.dart';
import '../runtime/codex_config_bridge.dart';
import '../runtime/code_agent_node_orchestrator.dart';
import '../runtime/assistant_artifacts.dart';
import '../runtime/desktop_thread_artifact_service.dart';
import '../runtime/mode_switcher.dart';
import '../runtime/agent_registry.dart';
import '../runtime/platform_environment.dart';
import 'app_controller_desktop_core.dart';
import 'app_controller_desktop_navigation.dart';
import 'app_controller_desktop_gateway.dart';
import 'app_controller_desktop_settings.dart';
import 'app_controller_desktop_thread_sessions.dart';
import 'app_controller_desktop_thread_actions.dart';
import 'app_controller_desktop_thread_binding.dart';
import 'app_controller_desktop_workspace_execution.dart';
import 'app_controller_desktop_settings_runtime.dart';
import 'app_controller_desktop_skill_permissions.dart';
import 'app_controller_desktop_runtime_helpers.dart';

// ignore_for_file: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
extension AppControllerDesktopThreadStorage on AppController {
  Set<String> knownPollutedTestTaskSessionKeysInternal() => <String>{
    'draft'
        ':unit-task-a',
    'draft'
        ':test-task-a',
    'test-fixture:unit-task-a',
    'test-fixture:test-task-a',
  };

  bool isKnownPollutedTestTaskSessionKeyInternal(String sessionKey) {
    final normalized = normalizedAssistantSessionKeyInternal(sessionKey);
    return knownPollutedTestTaskSessionKeysInternal().contains(normalized);
  }

  List<TaskThread> discardKnownPollutedTestTaskThreadsInternal(
    List<TaskThread> records,
  ) {
    return records
        .where(
          (record) =>
              !isKnownPollutedTestTaskSessionKeyInternal(record.sessionKey),
        )
        .toList(growable: false);
  }

  Future<void> applyPersistedAiGatewaySettingsInternal(
    SettingsSnapshot snapshot,
  ) async {
    final apiKey = await settingsControllerInternal
        .loadEffectiveAiGatewayApiKey();
    if (snapshot.aiGateway.baseUrl.trim().isEmpty) {
      return;
    }
    try {
      await syncAiGatewayCatalog(snapshot.aiGateway, apiKeyOverride: apiKey);
    } catch (e, stackTrace) {
      debugPrint('Error: $e\n$stackTrace');
      // Keep the saved draft applied even if model sync fails immediately.
    }
  }

  Future<void> ensureActiveAssistantThreadInternal() async {
    final currentKey = normalizedAssistantSessionKeyInternal(
      sessionsControllerInternal.currentSessionKey,
    );
    if (isAppOwnedAssistantSessionKeyInternal(currentKey) &&
        !isAssistantTaskArchived(currentKey)) {
      return;
    }
    final fallback = assistantSessionSummariesInternal().firstWhere(
      (item) =>
          isAppOwnedAssistantSessionKeyInternal(item.key) &&
          !isAssistantTaskArchived(item.key),
      orElse: () => GatewaySessionSummary(
        key: createAssistantDraftSessionKeyInternal(),
        kind: 'assistant',
        displayName: appText('新对话', 'New conversation'),
        surface: 'Assistant',
        subject: null,
        room: null,
        space: null,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
        sessionId: null,
        systemSent: false,
        abortedLastRun: false,
        thinkingLevel: null,
        verboseLevel: null,
        inputTokens: null,
        outputTokens: null,
        totalTokens: null,
        model: null,
        contextTokens: null,
        derivedTitle: appText('新对话', 'New conversation'),
        lastMessagePreview: null,
      ),
    );
    if (!hasAssistantTaskStateInternal(fallback.key)) {
      initializeAssistantThreadContext(
        fallback.key,
        title: appText('新对话', 'New conversation'),
        executionTarget: currentAssistantExecutionTarget,
        messageViewMode: currentAssistantMessageViewMode,
      );
    }
    await setCurrentAssistantSessionKeyInternal(fallback.key);
  }

  Future<void> restoreInitialAssistantSessionSelectionInternal() async {
    final normalized = normalizedAssistantSessionKeyInternal(
      appUiState.assistantLastSessionKey,
    );
    final known =
        isAppOwnedAssistantSessionKeyInternal(normalized) &&
        (assistantThreadRecordsInternal.containsKey(normalized) ||
            assistantThreadMessagesInternal.containsKey(normalized));
    if (normalized.isEmpty || !known || isAssistantTaskArchived(normalized)) {
      return;
    }
    await setCurrentAssistantSessionKeyInternal(
      normalized,
      persistSelection: false,
    );
    resumeOpenClawTaskAssociationsInternal(onlySessionKey: normalized);
  }

  void handleRuntimeEventInternal(GatewayPushEvent event) {
    chatControllerInternal.handleEvent(event);
    if (event.event == 'chat') {
      final payload = asMap(event.payload);
      final state = stringValue(payload['state']);
      if (state == 'final' || state == 'aborted' || state == 'error') {
        unawaited(refreshSessions());
      }
    }
    if (event.event == 'seqGap') {
      unawaited(refreshSessions());
    }
    if (event.event == 'device.pair.requested' ||
        event.event == 'device.pair.resolved') {
      unawaited(refreshDevices(quiet: true));
    }
  }

  SettingsSnapshot sanitizeFeatureFlagSettingsInternal(
    SettingsSnapshot snapshot,
  ) {
    final features = featuresFor(hostUiFeaturePlatformInternal);
    final sanitizedExecutionTarget = sanitizeExecutionTargetInternal(
      features.sanitizeExecutionTarget(snapshot.assistantExecutionTarget),
    );
    final experimentalCanvas =
        features.allowsExperimentalSetting(
          UiFeatureKeys.settingsExperimentalCanvas,
        )
        ? snapshot.experimentalCanvas
        : false;
    final experimentalBridge =
        features.allowsExperimentalSetting(
          UiFeatureKeys.settingsExperimentalBridge,
        )
        ? snapshot.experimentalBridge
        : false;
    final experimentalDebug =
        features.allowsExperimentalSetting(
          UiFeatureKeys.settingsExperimentalDebug,
        )
        ? snapshot.experimentalDebug
        : false;
    return snapshot.copyWith(
      assistantExecutionTarget: sanitizedExecutionTarget,
      experimentalCanvas: experimentalCanvas,
      experimentalBridge: experimentalBridge,
      experimentalDebug: experimentalDebug,
    );
  }

  AppUiState sanitizeAppUiStateInternal(AppUiState state) {
    final features = featuresFor(hostUiFeaturePlatformInternal);
    final allowedNavigation =
        normalizeAssistantNavigationDestinations(
              state.assistantNavigationDestinations,
            )
            .where((entry) {
              final destination = entry.destination;
              if (destination != null) {
                return features.allowedDestinations.contains(destination);
              }
              return features.allowedDestinations.contains(
                WorkspaceDestination.settings,
              );
            })
            .toList(growable: false);
    final assistantLastSessionKey =
        isKnownPollutedTestTaskSessionKeyInternal(state.assistantLastSessionKey)
        ? ''
        : state.assistantLastSessionKey;
    return state.copyWith(
      assistantLastSessionKey: assistantLastSessionKey,
      assistantNavigationDestinations: allowedNavigation,
    );
  }

  SettingsSnapshot sanitizeOllamaCloudSettingsInternal(
    SettingsSnapshot snapshot,
  ) {
    final rawBaseUrl = snapshot.ollamaCloud.baseUrl.trim();
    final normalized = rawBaseUrl.endsWith('/')
        ? rawBaseUrl.substring(0, rawBaseUrl.length - 1)
        : rawBaseUrl;
    if (normalized != 'https://ollama.svc.plus') {
      return snapshot;
    }
    return snapshot.copyWith(
      ollamaCloud: snapshot.ollamaCloud.copyWith(baseUrl: 'https://ollama.com'),
    );
  }

  SettingsTab sanitizeSettingsTabInternal(SettingsTab tab) {
    return featuresFor(hostUiFeaturePlatformInternal).sanitizeSettingsTab(tab);
  }

  AssistantExecutionTarget sanitizeExecutionTargetInternal(
    AssistantExecutionTarget? target,
  ) => featuresFor(
    hostUiFeaturePlatformInternal,
  ).sanitizeExecutionTarget(target);

  AssistantExecutionTarget sanitizePersistedExecutionTargetInternal(
    AssistantExecutionTarget? target,
  ) {
    return sanitizeExecutionTargetInternal(target);
  }

  void appendAssistantThreadMessageInternal(
    String sessionKey,
    GatewayChatMessage message,
  ) {
    final key = normalizedAssistantSessionKeyInternal(sessionKey);
    final existingTitle =
        assistantThreadRecordsInternal[key]?.title.trim() ?? '';
    final next = List<GatewayChatMessage>.from(
      assistantThreadMessagesInternal[key] ?? const <GatewayChatMessage>[],
    )..add(message);
    assistantThreadMessagesInternal[key] = next;
    upsertTaskThreadInternal(
      key,
      title: derivePersistedTaskTitle(
        existingTitle,
        next,
        fallback: key,
        hasCustomTitle: existingTitle.isNotEmpty,
      ),
      messages: next,
      updatedAtMs:
          message.timestampMs ??
          DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    notifyIfActiveInternal();
  }

  Future<void> flushAssistantThreadPersistenceInternal() async {
    await taskThreadRepositoryInternal.flush();
  }

  Future<void> persistAssistantHistory() async {
    await flushAssistantThreadPersistenceInternal();
  }

  void clearPendingToolCallsForGatewaySessionInternal(
    String sessionKey, {
    bool hasError = false,
  }) {
    final key = normalizedAssistantSessionKeyInternal(sessionKey);
    var modified = false;

    final localMessages = localSessionMessagesInternal[key];
    if (localMessages != null && localMessages.isNotEmpty) {
      var changed = false;
      final next = localMessages
          .map((msg) {
            if (msg.pending && msg.toolCallId != null) {
              changed = true;
              return msg.copyWith(pending: false, error: hasError || msg.error);
            }
            return msg;
          })
          .toList(growable: false);
      if (changed) {
        localSessionMessagesInternal[key] = next;
        modified = true;
      }
    }

    final threadMessages = assistantThreadMessagesInternal[key];
    if (threadMessages != null && threadMessages.isNotEmpty) {
      var changed = false;
      final next = threadMessages
          .map((msg) {
            if (msg.pending && msg.toolCallId != null) {
              changed = true;
              return msg.copyWith(pending: false, error: hasError || msg.error);
            }
            return msg;
          })
          .toList(growable: false);
      if (changed) {
        assistantThreadMessagesInternal[key] = next;
        modified = true;
      }
    }

    final record = assistantThreadRecordsInternal[key];
    if (record != null && record.messages.isNotEmpty) {
      var changed = false;
      final next = record.messages
          .map((msg) {
            if (msg.pending && msg.toolCallId != null) {
              changed = true;
              return msg.copyWith(pending: false, error: hasError || msg.error);
            }
            return msg;
          })
          .toList(growable: false);
      if (changed) {
        upsertTaskThreadInternal(key, messages: next);
        modified = true;
      }
    }

    if (modified) {
      notifyIfActiveInternal();
    }
  }

  void appendLocalSessionMessageInternal(
    String sessionKey,
    GatewayChatMessage message, {
    bool persistInThreadContext = false,
  }) {
    final key = normalizedAssistantSessionKeyInternal(sessionKey);
    final next = List<GatewayChatMessage>.from(
      localSessionMessagesInternal[key] ?? const <GatewayChatMessage>[],
    )..add(message);
    localSessionMessagesInternal[key] = next;
    if (persistInThreadContext) {
      final threadMessages = List<GatewayChatMessage>.from(
        assistantThreadRecordsInternal[key]?.messages ??
            const <GatewayChatMessage>[],
      )..add(message);
      upsertTaskThreadInternal(
        key,
        messages: threadMessages,
        updatedAtMs:
            message.timestampMs ??
            DateTime.now().millisecondsSinceEpoch.toDouble(),
      );
    }
    notifyIfActiveInternal();
  }

  Future<bool> removeAssistantUserMessageInternal(
    String sessionKey,
    String messageId,
  ) async {
    return mutateAssistantUserMessageInternal(
      sessionKey: sessionKey,
      messageId: messageId,
      mutate: (_) => null,
    );
  }

  Future<bool> updateAssistantUserMessageInternal(
    String sessionKey,
    String messageId,
    String text,
  ) async {
    final normalizedText = text.trim();
    if (normalizedText.isEmpty) {
      return false;
    }
    return mutateAssistantUserMessageInternal(
      sessionKey: sessionKey,
      messageId: messageId,
      mutate: (message) => message.copyWith(text: normalizedText),
    );
  }

  Future<bool> mutateAssistantUserMessageInternal({
    required String sessionKey,
    required String messageId,
    required GatewayChatMessage? Function(GatewayChatMessage message) mutate,
  }) async {
    final key = normalizedAssistantSessionKeyInternal(sessionKey);
    final id = messageId.trim();
    if (key.isEmpty || id.isEmpty) {
      return false;
    }

    var changed = false;
    List<GatewayChatMessage> mutateList(List<GatewayChatMessage> messages) {
      final next = <GatewayChatMessage>[];
      for (final message in messages) {
        final isTarget =
            message.id == id &&
            message.role.trim().toLowerCase() == 'user' &&
            !message.pending;
        if (!isTarget) {
          next.add(message);
          continue;
        }
        final replacement = mutate(message);
        if (replacement != null) {
          next.add(replacement);
        }
        changed = true;
      }
      return next;
    }

    final localMessages = localSessionMessagesInternal[key];
    if (localMessages != null) {
      localSessionMessagesInternal[key] = mutateList(localMessages);
    }

    final threadMessages = assistantThreadMessagesInternal[key];
    if (threadMessages != null) {
      assistantThreadMessagesInternal[key] = mutateList(threadMessages);
    }

    final record = assistantThreadRecordsInternal[key];
    if (record != null) {
      upsertTaskThreadInternal(
        key,
        messages: mutateList(record.messages),
        updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
      );
    }

    if (!changed) {
      return false;
    }
    await flushAssistantThreadPersistenceInternal();
    recomputeTasksInternal();
    notifyIfActiveInternal();
    return true;
  }

  List<GatewaySessionSummary> assistantSessionSummariesInternal() {
    final items = <GatewaySessionSummary>[];

    for (final record in assistantThreadRecordsInternal.values) {
      final sessionKey = normalizedAssistantSessionKeyInternal(
        record.sessionKey,
      );
      if (!isAppOwnedAssistantSessionKeyInternal(sessionKey) ||
          record.archived) {
        continue;
      }
      items.add(assistantSessionSummaryForInternal(sessionKey, record: record));
    }

    final currentSessionKey = normalizedAssistantSessionKeyInternal(
      sessionsControllerInternal.currentSessionKey,
    );
    final hasCurrent = items.any(
      (item) => matchesSessionKey(item.key, currentSessionKey),
    );
    if (isAppOwnedAssistantSessionKeyInternal(currentSessionKey) &&
        !hasCurrent &&
        !isAssistantTaskArchived(currentSessionKey)) {
      items.add(assistantSessionSummaryForInternal(currentSessionKey));
    }

    return items;
  }

  GatewaySessionSummary assistantSessionSummaryForInternal(
    String sessionKey, {
    TaskThread? record,
  }) {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    final resolvedRecord =
        record ?? assistantThreadRecordsInternal[normalizedSessionKey];
    final messages =
        resolvedRecord?.messages ??
        assistantThreadMessagesInternal[normalizedSessionKey] ??
        const <GatewayChatMessage>[];
    final preview = assistantThreadPreviewInternal(messages);
    final customTitle = assistantCustomTaskTitle(normalizedSessionKey);
    final derivedTitle = customTitle.isEmpty
        ? assistantThreadTitleFromMessagesInternal(messages)
        : customTitle;
    final lastMessage = messages.isNotEmpty ? messages.last : null;
    final updatedAtMs =
        resolvedRecord?.updatedAtMs ??
        lastMessage?.timestampMs ??
        DateTime.now().millisecondsSinceEpoch.toDouble();
    return GatewaySessionSummary(
      key: normalizedSessionKey,
      kind: 'assistant',
      displayName: derivedTitle.isEmpty ? null : derivedTitle,
      surface: 'Assistant',
      subject: preview,
      room: null,
      space: null,
      updatedAtMs: updatedAtMs,
      sessionId: normalizedSessionKey,
      systemSent: false,
      abortedLastRun: lastMessage?.error == true,
      thinkingLevel: null,
      verboseLevel: null,
      inputTokens: null,
      outputTokens: null,
      totalTokens: null,
      model: assistantModelForSession(normalizedSessionKey),
      contextTokens: null,
      derivedTitle: derivedTitle.isEmpty ? null : derivedTitle,
      lastMessagePreview: preview,
    );
  }

  String assistantThreadTitleFromMessagesInternal(
    List<GatewayChatMessage> messages,
  ) {
    for (final message in messages) {
      final role = message.role.trim().toLowerCase();
      if (role != 'user') {
        continue;
      }
      final text = _compactAssistantThreadTitleTextInternal(message.text);
      if (text.isNotEmpty) {
        return text;
      }
    }
    return '';
  }

  String _compactAssistantThreadTitleTextInternal(String text) {
    final firstLine = text
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => '');
    if (firstLine.isEmpty) {
      return '';
    }
    final compact = firstLine.replaceAll(RegExp(r'\s+'), ' ').trim();
    const maxTitleLength = 34;
    if (compact.length <= maxTitleLength) {
      return compact;
    }
    return '${compact.substring(0, maxTitleLength).trimRight()}...';
  }

  String? assistantThreadPreviewInternal(List<GatewayChatMessage> messages) {
    for (final message in messages.reversed) {
      final role = message.role.trim().toLowerCase();
      if (role != 'user' && role != 'assistant') {
        continue;
      }
      final text = message.text.trim();
      if (text.isNotEmpty) {
        return text;
      }
    }
    return null;
  }

  String gatewayEntryStateForTargetInternal(AssistantExecutionTarget target) {
    return target.promptValue;
  }

  /// 返回工作区路径被重定位的记录数，调用方据此决定是否立刻落盘。
  int restoreAssistantThreadsInternal(List<TaskThread> records) {
    taskThreadRepositoryInternal.clear();
    assistantThreadMessagesInternal.clear();
    var rebasedThreadWorkspaceCount = 0;
    for (final record in records) {
      final sessionKey = normalizedAssistantSessionKeyInternal(
        record.sessionKey,
      );
      if (sessionKey.isEmpty) {
        continue;
      }
      if (isKnownPollutedTestTaskSessionKeyInternal(sessionKey)) {
        continue;
      }
      if (!record.workspaceBinding.isComplete) {
        continue;
      }
      final recordExecutionTarget = sanitizeExecutionTargetInternal(
        assistantExecutionTargetFromExecutionMode(
          record.executionBinding.executionMode,
        ),
      );
      final recordProviderId = normalizeSingleAgentProviderId(
        record.executionBinding.providerId,
      );
      final normalizedExecutionTarget = recordExecutionTarget;
      final recordProvider = resolveProviderForExecutionTarget(
        recordProviderId,
        executionTarget: normalizedExecutionTarget,
      );
      var workspaceBinding = record.workspaceBinding.copyWith(
        workspaceId: sessionKey,
        displayPath: record.workspaceKind == WorkspaceKind.localFs
            ? record.workspacePath.trim()
            : (record.displayPath.trim().isEmpty
                  ? record.workspacePath.trim()
                  : record.displayPath.trim()),
      );
      // 迁移：owner-scoped remoteFs 只是「本地工作区不可用」时的兜底绑定
      // （历史上 iOS 以 $HOME 建线程目录失败即落入此分支）。一旦本地路径
      // 恢复可用，必须迁回 localFs，否则制品同步永远跳过该线程。
      if (record.workspaceKind == WorkspaceKind.remoteFs &&
          isOwnerScopedRemoteWorkspacePathInternal(record.workspacePath) &&
          isAppOwnedAssistantSessionKeyInternal(sessionKey)) {
        final migratedLocalPath = localThreadWorkspacePathInternal(sessionKey);
        debugPrint(
          '[thread-migrate] $sessionKey remoteFs->localFs '
          'candidate="$migratedLocalPath"',
        );
        if (migratedLocalPath.isNotEmpty) {
          workspaceBinding = WorkspaceBinding(
            workspaceId: sessionKey,
            workspaceKind: WorkspaceKind.localFs,
            workspacePath: migratedLocalPath,
            displayPath: migratedLocalPath,
            writable: record.workspaceBinding.writable,
          );
        }
      }
      // 迁移：iOS 容器 UUID 随每次升级/重装变化，持久化下来的 localFs 绝对
      // 路径会指向已不存在的旧容器。托管线程工作区完全可由 sessionKey 推导，
      // 因此只要存量路径仍是托管形态（…/.xworkmate/threads/<name>）而基准
      // 已漂移，就重定位到当前基准。非托管形态的自定义路径不属于容器产物，
      // 保持原样。激活中的会话另有 ensureDesktopTaskThreadBindingInternal
      // 自愈，这里补齐的是从不被 ensure 的历史线程（制品同步直接读记录）。
      if (workspaceBinding.workspaceKind == WorkspaceKind.localFs &&
          isAppOwnedAssistantSessionKeyInternal(sessionKey) &&
          isManagedLocalThreadWorkspacePathInternal(
            workspaceBinding.workspacePath,
            sessionKey,
          )) {
        final canonicalLocalPath = localThreadWorkspacePathInternal(sessionKey);
        if (canonicalLocalPath.isNotEmpty &&
            canonicalLocalPath !=
                trimTrailingPathSeparatorInternal(
                  workspaceBinding.workspacePath.trim(),
                )) {
          debugPrint(
            '[thread-migrate] $sessionKey localFs rebase '
            '"${workspaceBinding.workspacePath}" -> "$canonicalLocalPath"',
          );
          workspaceBinding = WorkspaceBinding(
            workspaceId: sessionKey,
            workspaceKind: WorkspaceKind.localFs,
            workspacePath: canonicalLocalPath,
            displayPath: canonicalLocalPath,
            writable: workspaceBinding.writable,
          );
          rebasedThreadWorkspaceCount += 1;
        }
      }
      final normalizedRecord = record.copyWith(
        threadId: sessionKey,
        title: record.title.trim(),
        archived: record.archived,
        messageViewMode: record.messageViewMode,
        selectedSkillKeys: record.selectedSkillKeys
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList(growable: false),
        assistantModelId: record.assistantModelId.trim().isEmpty
            ? resolvedAssistantModelForTargetInternal(normalizedExecutionTarget)
            : record.assistantModelId.trim(),
        gatewayEntryState: (record.gatewayEntryState ?? '').trim().isEmpty
            ? gatewayEntryStateForTargetInternal(normalizedExecutionTarget)
            : record.gatewayEntryState,
        workspaceBinding: workspaceBinding,
        executionBinding: record.executionBinding.copyWith(
          executionMode: threadExecutionModeFromAssistantExecutionTarget(
            normalizedExecutionTarget,
          ),
          executorId: recordProvider.providerId,
          providerId: recordProvider.providerId,
          providerSource: record.executionBinding.providerSource,
        ),
        lifecycleState: record.lifecycleState.copyWith(status: 'ready'),
      );
      if (normalizedRecord.workspaceKind == WorkspaceKind.localFs &&
          normalizedRecord.workspacePath.trim().isNotEmpty) {
        try {
          Directory(normalizedRecord.workspacePath).createSync(recursive: true);
        } catch (e, stackTrace) {
          debugPrint('Error: $e\n$stackTrace');
          // Best effort only. The thread should still restore even when the
          // directory cannot be recreated immediately.
        }
      }
      taskThreadRepositoryInternal.replace(normalizedRecord, persist: false);
      if (normalizedRecord.messages.isNotEmpty) {
        assistantThreadMessagesInternal[sessionKey] =
            List<GatewayChatMessage>.from(normalizedRecord.messages);
      }
    }
    return rebasedThreadWorkspaceCount;
  }
}
