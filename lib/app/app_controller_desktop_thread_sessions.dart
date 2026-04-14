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
import '../runtime/aris_bundle.dart';
import '../runtime/go_core.dart';
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
import '../runtime/multi_agent_orchestrator.dart';
import '../runtime/platform_environment.dart';
import '../runtime/skill_directory_access.dart';
import 'app_controller_desktop_core.dart';
import 'app_controller_desktop_navigation.dart';
import 'app_controller_desktop_gateway.dart';
import 'app_controller_desktop_settings.dart';
import 'app_controller_desktop_single_agent.dart';
import 'app_controller_desktop_thread_binding.dart';
import 'app_controller_desktop_thread_actions.dart';
import 'app_controller_desktop_workspace_execution.dart';
import 'app_controller_desktop_settings_runtime.dart';
import 'app_controller_desktop_thread_storage.dart';
import 'app_controller_desktop_skill_permissions.dart';
import 'app_controller_desktop_runtime_helpers.dart';
import 'app_controller_desktop_thread_sessions_collaboration_impl.dart';

// ignore_for_file: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member

AssistantThreadConnectionState resolveGatewayThreadConnectionStateInternal({
  required AssistantExecutionTarget target,
  required bool bridgeReady,
  required String bridgeLabel,
  required AccountSyncState? accountSyncState,
}) {
  if (bridgeReady) {
    return AssistantThreadConnectionState(
      executionTarget: target,
      status: RuntimeConnectionStatus.connected,
      primaryLabel: RuntimeConnectionStatus.connected.label,
      detailLabel: bridgeLabel,
      ready: true,
      gatewayTokenMissing: false,
      lastError: null,
    );
  }

  final syncState = accountSyncState?.syncState.trim().toLowerCase() ?? '';
  final syncMessage = accountSyncState?.syncMessage.trim() ?? '';
  final tokenMissing = syncMessage == 'Bridge authorization is unavailable';
  final endpointMissing = syncMessage == 'Bridge endpoint is unavailable';
  final blocked = syncState == 'blocked';
  final failed = blocked && !tokenMissing && !endpointMissing;
  final status = tokenMissing || failed
      ? RuntimeConnectionStatus.error
      : RuntimeConnectionStatus.offline;
  final primaryLabel = tokenMissing
      ? appText('缺少令牌', 'Missing Token')
      : failed
      ? appText('连接失败', 'Connection Failed')
      : status.label;
  final detailLabel = tokenMissing
      ? appText('xworkmate-bridge 授权不可用', 'xworkmate-bridge authorization unavailable')
      : failed
      ? appText('xworkmate-bridge 连接失败', 'xworkmate-bridge connection failed')
      : appText('xworkmate-bridge 未连接', 'xworkmate-bridge is not connected');
  return AssistantThreadConnectionState(
    executionTarget: target,
    status: status,
    primaryLabel: primaryLabel,
    detailLabel: detailLabel,
    ready: false,
    gatewayTokenMissing: tokenMissing,
    lastError: failed ? syncMessage : null,
  );
}

extension AppControllerDesktopThreadSessions on AppController {
  AssistantExecutionTarget resolveAssistantExecutionTargetFromRecordsInternal(
    TaskThread? primaryRecord, {
    TaskThread? fallbackRecord,
  }) {
    return resolveAssistantExecutionTargetFromRecordsForTest(
      primaryRecord,
      fallbackRecord: fallbackRecord,
    );
  }

  TaskThread? taskThreadForSessionInternal(String sessionKey) {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    return taskThreadRepositoryInternal.taskThreadForSession(
      normalizedSessionKey,
    );
  }

  TaskThread requireTaskThreadForSessionInternal(String sessionKey) {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    return taskThreadRepositoryInternal.requireTaskThreadForSession(
      normalizedSessionKey,
    );
  }

  int assistantSkillCountForSession(String sessionKey) {
    return skills.length;
  }

  int get currentAssistantSkillCount =>
      assistantSkillCountForSession(currentSessionKey);

  List<String> assistantSelectedSkillKeysForSession(String sessionKey) {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    final importedKeys = assistantImportedSkillsForSession(
      normalizedSessionKey,
    ).map((item) => item.key).toSet();
    final selected =
        assistantThreadRecordsInternal[normalizedSessionKey]
            ?.selectedSkillKeys ??
        const <String>[];
    return selected
        .where((item) => importedKeys.contains(item))
        .toList(growable: false);
  }

  List<AssistantThreadSkillEntry> assistantSelectedSkillsForSession(
    String sessionKey,
  ) {
    final selectedKeys = assistantSelectedSkillKeysForSession(
      sessionKey,
    ).toSet();
    return assistantImportedSkillsForSession(
      sessionKey,
    ).where((item) => selectedKeys.contains(item.key)).toList(growable: false);
  }

  String assistantModelForSession(String sessionKey) {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    final recordModel =
        assistantThreadRecordsInternal[normalizedSessionKey]?.assistantModelId
            .trim() ??
        '';
    final availableChoices = assistantModelChoicesForSessionInternal(
      normalizedSessionKey,
    );
    if (recordModel.isNotEmpty &&
        (availableChoices.isEmpty || availableChoices.contains(recordModel))) {
      return recordModel;
    }
    return resolvedAssistantModelForTargetInternal(
      AssistantExecutionTarget.gateway,
    );
  }

  String assistantDisplayModelForSession(String sessionKey) {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    final availableChoices = assistantModelChoicesForSessionInternal(
      normalizedSessionKey,
    );
    if (availableChoices.isEmpty) {
      return '';
    }
    final thread = taskThreadForSessionInternal(normalizedSessionKey);
    final latestResolvedModel = thread?.latestResolvedRuntimeModel.trim() ?? '';
    if (availableChoices.contains(latestResolvedModel)) {
      return latestResolvedModel;
    }
    final selectedModel = thread?.assistantModelId.trim() ?? '';
    if (availableChoices.contains(selectedModel)) {
      return selectedModel;
    }
    final target = assistantExecutionTargetForSession(normalizedSessionKey);
    final defaultModel = resolvedAssistantModelForTargetInternal(target).trim();
    if (availableChoices.contains(defaultModel)) {
      return defaultModel;
    }
    return availableChoices.length == 1 ? availableChoices.first : '';
  }

  String assistantWorkspacePathForSession(String sessionKey) {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    return taskThreadForSessionInternal(
          normalizedSessionKey,
        )?.workspaceBinding.workspacePath.trim() ??
        '';
  }

  WorkspaceRefKind assistantWorkspaceKindForSession(String sessionKey) {
    final record = taskThreadForSessionInternal(
      normalizedAssistantSessionKeyInternal(sessionKey),
    );
    if (record == null) {
      return WorkspaceRefKind.remotePath;
    }
    return record.workspaceBinding.workspaceKind == WorkspaceKind.localFs
        ? WorkspaceRefKind.localPath
        : WorkspaceRefKind.remotePath;
  }

  String assistantWorkspaceDisplayPathForSession(String sessionKey) {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    return taskThreadForSessionInternal(
          normalizedSessionKey,
        )?.workspaceBinding.displayPath.trim() ??
        '';
  }

  Future<AssistantArtifactSnapshot> loadAssistantArtifactSnapshot({
    String? sessionKey,
  }) {
    final resolvedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey ?? currentSessionKey,
    );
    return threadArtifactServiceInternal.loadSnapshot(
      workspacePath: assistantWorkspacePathForSession(resolvedSessionKey),
      workspaceKind: assistantWorkspaceKindForSession(resolvedSessionKey),
    );
  }

  Future<AssistantArtifactPreview> loadAssistantArtifactPreview(
    AssistantArtifactEntry entry, {
    String? sessionKey,
  }) {
    final resolvedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey ?? currentSessionKey,
    );
    return threadArtifactServiceInternal.loadPreview(
      entry: entry,
      workspacePath: assistantWorkspacePathForSession(resolvedSessionKey),
      workspaceKind: assistantWorkspaceKindForSession(resolvedSessionKey),
    );
  }

  String get assistantConversationOwnerLabel {
    return activeAgentName;
  }

  AssistantThreadConnectionState get currentAssistantConnectionState =>
      assistantConnectionStateForSession(currentSessionKey);

  AssistantThreadConnectionState assistantConnectionStateForSession(
    String sessionKey,
  ) {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    final target = assistantExecutionTargetForSession(normalizedSessionKey);
    final providers = providerCatalogForExecutionTarget(target);
    final availableTargets = bridgeAvailableExecutionTargets;
    final bridgeReady =
        providers.isNotEmpty &&
        (availableTargets.isEmpty || availableTargets.contains(target));
    final bridgeEndpoint = resolveBridgeAcpEndpointInternal();
    final bridgeLabel = bridgeEndpoint?.host.trim().isNotEmpty == true
        ? bridgeEndpoint!.host.trim()
        : 'xworkmate-bridge';
    return resolveGatewayThreadConnectionStateInternal(
      target: target,
      bridgeReady: bridgeReady,
      bridgeLabel: bridgeLabel,
      accountSyncState: settingsControllerInternal.accountSyncState,
    );
  }

  String get assistantConnectionStatusLabel =>
      currentAssistantConnectionState.primaryLabel;
  String get assistantConnectionTargetLabel =>
      currentAssistantConnectionState.detailLabel;

  Future<String> loadAiGatewayApiKey() =>
      loadAiGatewayApiKeyThreadSessionInternal(this);
  Future<void> saveMultiAgentConfig(MultiAgentConfig config) =>
      saveMultiAgentConfigThreadSessionInternal(this, config);
  Future<void> refreshMultiAgentMounts({bool sync = false}) =>
      refreshMultiAgentMountsThreadSessionInternal(this, sync: sync);
  Future<void> runMultiAgentCollaboration({
    required String rawPrompt,
    required String composedPrompt,
    required List<CollaborationAttachment> attachments,
    required List<String> selectedSkillLabels,
  }) => runMultiAgentCollaborationThreadSessionInternal(
    this,
    rawPrompt: rawPrompt,
    composedPrompt: composedPrompt,
    attachments: attachments,
    selectedSkillLabels: selectedSkillLabels,
  );
  Future<void> openOnlineWorkspace() =>
      openOnlineWorkspaceThreadSessionInternal(this);
  List<String> get aiGatewayModelChoices =>
      aiGatewayModelChoicesThreadSessionInternal(this);
  List<String> get connectedGatewayModelChoices =>
      connectedGatewayModelChoicesThreadSessionInternal(this);
  List<String> get assistantModelChoices =>
      assistantModelChoicesThreadSessionInternal(this);
  List<String> assistantModelChoicesForSessionInternal(String sessionKey) =>
      assistantModelChoicesForSessionThreadSessionInternal(this, sessionKey);
  String get resolvedDefaultModel =>
      resolvedDefaultModelThreadSessionInternal(this);
  bool get canQuickConnectGateway =>
      canQuickConnectGatewayThreadSessionInternal(this);
  String joinConnectionPartsInternal(List<String> parts) =>
      joinConnectionPartsThreadSessionInternal(parts);
  String gatewayAddressLabelInternal(GatewayConnectionProfile profile) =>
      gatewayAddressLabelThreadSessionInternal(profile);

  List<AssistantFocusEntry> get assistantNavigationDestinations =>
      normalizeAssistantNavigationDestinations(
        appUiState.assistantNavigationDestinations,
      ).where(supportsAssistantFocusEntry).toList(growable: false);

  bool supportsAssistantFocusEntry(AssistantFocusEntry entry) {
    final destination = entry.destination;
    if (destination != null) {
      return capabilities.supportsDestination(destination);
    }
    return capabilities.supportsDestination(WorkspaceDestination.settings);
  }

  List<GatewayChatMessage> get chatMessages {
    final sessionKey = normalizedAssistantSessionKeyInternal(
      sessionsControllerInternal.currentSessionKey,
    );
    final items = List<GatewayChatMessage>.from(
      chatControllerInternal.messages,
    );
    final threadItems = assistantThreadMessagesInternal[sessionKey];
    if (threadItems != null && threadItems.isNotEmpty) {
      items.addAll(threadItems);
    }
    final localItems = localSessionMessagesInternal[sessionKey];
    if (localItems != null && localItems.isNotEmpty) {
      items.addAll(localItems);
    }
    final streaming =
        chatControllerInternal.streamingAssistantText?.trim() ?? '';
    if (streaming.isNotEmpty) {
      items.add(
        GatewayChatMessage(
          id: 'streaming',
          role: 'assistant',
          text: streaming,
          timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
          toolCallId: null,
          toolName: null,
          stopReason: null,
          pending: true,
          error: false,
        ),
      );
    }
    return items;
  }

  String normalizedAssistantSessionKeyInternal(String sessionKey) {
    final trimmed = sessionKey.trim();
    return trimmed.isEmpty ? 'main' : trimmed;
  }

  AssistantExecutionTarget assistantExecutionTargetForSession(
    String sessionKey,
  ) {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    final record = taskThreadForSessionInternal(normalizedSessionKey);
    final mainRecord = matchesSessionKey(normalizedSessionKey, 'main')
        ? null
        : taskThreadForSessionInternal('main');
    return resolveAssistantExecutionTargetFromRecordsInternal(
      record,
      fallbackRecord: mainRecord,
    );
  }

  AssistantMessageViewMode assistantMessageViewModeForSession(
    String sessionKey,
  ) {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    return assistantThreadRecordsInternal[normalizedSessionKey]
            ?.messageViewMode ??
        AssistantMessageViewMode.rendered;
  }

  WorkspaceRefKind defaultWorkspaceRefKindForTargetInternal(
    AssistantExecutionTarget target,
  ) => WorkspaceRefKind.remotePath;

  List<GatewaySessionSummary> assistantSessionsInternal() {
    final byKey = <String, GatewaySessionSummary>{};

    for (final session in sessionsControllerInternal.sessions) {
      final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
        session.key,
      );
      if (isAssistantTaskArchived(normalizedSessionKey)) {
        continue;
      }
      byKey[normalizedSessionKey] = session;
    }

    for (final record in assistantThreadRecordsInternal.values) {
      final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
        record.sessionKey,
      );
      if (normalizedSessionKey.isEmpty ||
          isAssistantTaskArchived(normalizedSessionKey) ||
          record.archived) {
        continue;
      }
      byKey.putIfAbsent(
        normalizedSessionKey,
        () => assistantSessionSummaryForInternal(
          normalizedSessionKey,
          record: record,
        ),
      );
    }

    final currentKey = normalizedAssistantSessionKeyInternal(currentSessionKey);
    if (!isAssistantTaskArchived(currentKey) &&
        !byKey.containsKey(currentKey)) {
      byKey[currentKey] = assistantSessionSummaryForInternal(currentKey);
    }

    final items = byKey.values.toList(growable: true)
      ..sort(
        (left, right) =>
            (right.updatedAtMs ?? 0).compareTo(left.updatedAtMs ?? 0),
      );
    return items;
  }
}

AssistantExecutionTarget resolveAssistantExecutionTargetFromRecordsForTest(
  TaskThread? primaryRecord, {
  TaskThread? fallbackRecord,
}) {
  final record = primaryRecord ?? fallbackRecord;
  return record == null
      ? AssistantExecutionTarget.agent
      : assistantExecutionTargetFromExecutionMode(
          record.executionBinding.executionMode,
        );
}
