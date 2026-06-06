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
import '../runtime/go_task_service_client.dart';
import '../runtime/mode_switcher.dart';
import '../runtime/agent_registry.dart';
import '../runtime/platform_environment.dart';
import 'app_controller_desktop_core.dart';
import 'app_controller_desktop_navigation.dart';
import 'app_controller_desktop_gateway.dart';
import 'app_controller_desktop_settings.dart';
import 'app_controller_desktop_thread_binding.dart';
import 'app_controller_desktop_thread_actions.dart';
import 'app_controller_desktop_workspace_execution.dart';
import 'app_controller_desktop_settings_runtime.dart';
import 'app_controller_desktop_thread_storage.dart';
import 'app_controller_desktop_skill_permissions.dart';
import 'app_controller_desktop_runtime_helpers.dart';
import 'app_controller_desktop_thread_sessions_collaboration_impl.dart';

// ignore_for_file: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member

final RegExp _runtimeSessionKeyPatternInternal = RegExp(
  r'^session-\d+$',
  caseSensitive: false,
);

AssistantThreadConnectionState resolveGatewayThreadConnectionStateInternal({
  required AssistantExecutionTarget target,
  required bool bridgeReady,
  required String bridgeLabel,
  required AccountSyncState? accountSyncState,
  required bool accountSignedIn,
  required bool bridgeConfigured,
  bool bridgeDiscoveryAttempted = false,
  String bridgeDiscoveryError = '',
  bool providerCatalogEmpty = false,
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

  if (!accountSignedIn) {
    return AssistantThreadConnectionState(
      executionTarget: target,
      status: RuntimeConnectionStatus.offline,
      primaryLabel: appText('已退出登录', 'Signed out'),
      detailLabel: appText('请先登录 svc.plus', 'Please sign in to svc.plus first'),
      ready: false,
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

  // SyncBlocked logic
  if (tokenMissing || failed || blocked) {
    final status = RuntimeConnectionStatus.error;
    final primaryLabel = tokenMissing
        ? appText('缺少令牌', 'Missing Token')
        : failed
        ? appText('连接失败', 'Connection Failed')
        : status.label;
    final detailLabel = tokenMissing
        ? appText(
            'xworkmate-bridge 授权不可用',
            'xworkmate-bridge authorization unavailable',
          )
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

  final discoveryError = bridgeDiscoveryError.trim();
  if (bridgeConfigured && bridgeDiscoveryAttempted) {
    final status = RuntimeConnectionStatus.error;
    final detailLabel = discoveryError.isNotEmpty
        ? discoveryError
        : providerCatalogEmpty
        ? appText(
            'Gateway ACP 未报告可用的 provider',
            'Gateway ACP did not report a usable provider',
          )
        : appText(
            'xworkmate-bridge 连接失败',
            'xworkmate-bridge connection failed',
          );
    return AssistantThreadConnectionState(
      executionTarget: target,
      status: status,
      primaryLabel: appText('连接失败', 'Connection Failed'),
      detailLabel: detailLabel,
      ready: false,
      gatewayTokenMissing: false,
      lastError: detailLabel,
    );
  }

  // BridgeDiscovering logic (Signed in, not blocked, but not ready yet)
  if (bridgeConfigured) {
    return AssistantThreadConnectionState(
      executionTarget: target,
      status: RuntimeConnectionStatus.offline,
      primaryLabel: appText('正在发现', 'Discovering'),
      detailLabel: appText(
        '正在加载 Bridge 能力...',
        'Loading Bridge capabilities...',
      ),
      ready: false,
      gatewayTokenMissing: false,
      lastError: null,
    );
  }

  // Default Offline/Unconnected
  return AssistantThreadConnectionState(
    executionTarget: target,
    status: RuntimeConnectionStatus.offline,
    primaryLabel: RuntimeConnectionStatus.offline.label,
    detailLabel: appText(
      'xworkmate-bridge 未连接',
      'xworkmate-bridge is not connected',
    ),
    ready: false,
    gatewayTokenMissing: false,
    lastError: null,
  );
}

bool bridgeCapabilityReadyForExecutionTargetInternal({
  required AssistantExecutionTarget target,
  required bool bridgeConfigured,
  required List<SingleAgentProvider> providers,
  required List<AssistantExecutionTarget> availableTargets,
}) {
  if (!bridgeConfigured || providers.isEmpty) {
    return false;
  }
  return availableTargets.isEmpty || availableTargets.contains(target);
}

extension AppControllerDesktopThreadSessions on AppController {
  bool isRuntimeOwnedAssistantSessionKeyInternal(String sessionKey) {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    ).toLowerCase();
    if (normalizedSessionKey.isEmpty) {
      return true;
    }
    if (normalizedSessionKey == 'main') {
      return true;
    }
    return _runtimeSessionKeyPatternInternal.hasMatch(normalizedSessionKey);
  }

  bool isAppOwnedAssistantSessionKeyInternal(String sessionKey) {
    return !isRuntimeOwnedAssistantSessionKeyInternal(sessionKey);
  }

  AssistantExecutionTarget resolveAssistantExecutionTargetFromRecordsInternal(
    TaskThread? record,
  ) {
    return resolveAssistantExecutionTargetFromRecordForTest(
      record,
      defaultExecutionTarget: pickDraftThreadExecutionTargetInternal(
        currentTarget: sanitizePersistedExecutionTargetInternal(
          settings.assistantExecutionTarget,
        ),
        visibleTargets: visibleAssistantExecutionTargets(
          AssistantExecutionTarget.values,
        ),
      ),
    );
  }

  TaskThread? taskThreadForSessionInternal(String sessionKey) {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    if (!isAppOwnedAssistantSessionKeyInternal(normalizedSessionKey)) {
      return null;
    }
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

  bool hasAssistantTaskStateInternal(String sessionKey) {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    if (!isAppOwnedAssistantSessionKeyInternal(normalizedSessionKey)) {
      return false;
    }
    return taskThreadRepositoryInternal.containsKey(normalizedSessionKey) ||
        assistantThreadMessagesInternal.containsKey(normalizedSessionKey) ||
        localSessionMessagesInternal.containsKey(normalizedSessionKey);
  }

  String createAssistantDraftSessionKeyInternal() {
    final selectedAgentId = agentsControllerInternal.selectedAgentId.trim();
    for (var attempt = 0; attempt < 32; attempt += 1) {
      assistantDraftSessionCounterInternal += 1;
      final stamp = DateTime.now().microsecondsSinceEpoch;
      final suffix = '$stamp-$assistantDraftSessionCounterInternal';
      final candidate = selectedAgentId.isEmpty
          ? 'draft:$suffix'
          : 'draft:$selectedAgentId:$suffix';
      if (!hasAssistantTaskStateInternal(candidate)) {
        return candidate;
      }
    }
    throw StateError('Unable to allocate a unique draft task session key.');
  }

  List<String> assistantSelectedSkillKeysForSession(String sessionKey) {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    final selected =
        assistantThreadRecordsInternal[normalizedSessionKey]
            ?.selectedSkillKeys ??
        const <String>[];
    final availableKeys = skills.map((item) => item.skillKey).toSet();
    return selected.where(availableKeys.contains).toList(growable: false);
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

  double? assistantArtifactSyncAtMsForSession(String sessionKey) {
    return taskThreadForSessionInternal(
      normalizedAssistantSessionKeyInternal(sessionKey),
    )?.lastArtifactSyncAtMs;
  }

  String assistantArtifactSyncStatusForSession(String sessionKey) {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    final thread = taskThreadForSessionInternal(normalizedSessionKey);
    return thread?.lastArtifactSyncStatus?.trim() ?? '';
  }

  Future<AssistantArtifactSnapshot> loadAssistantArtifactSnapshot({
    String? sessionKey,
  }) async {
    final resolvedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey ?? currentSessionKey,
    );
    final thread = taskThreadForSessionInternal(resolvedSessionKey);
    final snapshot = await threadArtifactServiceInternal.loadSnapshot(
      workspacePath: assistantWorkspacePathForSession(resolvedSessionKey),
      workspaceKind: assistantWorkspaceKindForSession(resolvedSessionKey),
      artifactRelativePaths:
          thread?.lastTaskArtifactRelativePaths ?? const <String>[],
    );
    if (snapshot.fileEntries.isNotEmpty || thread == null) {
      return snapshot;
    }
    final synced = await syncRemoteTaskArtifactsForSessionInternal(
      resolvedSessionKey,
    );
    if (!synced) {
      return snapshot;
    }
    final refreshedThread = taskThreadForSessionInternal(resolvedSessionKey);
    return threadArtifactServiceInternal.loadSnapshot(
      workspacePath: assistantWorkspacePathForSession(resolvedSessionKey),
      workspaceKind: assistantWorkspaceKindForSession(resolvedSessionKey),
      artifactRelativePaths:
          refreshedThread?.lastTaskArtifactRelativePaths ?? const <String>[],
    );
  }

  Future<bool> syncRemoteTaskArtifactsForSessionInternal(
    String sessionKey,
  ) async {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    final thread = taskThreadForSessionInternal(normalizedSessionKey);
    if (thread == null ||
        thread.workspaceBinding.workspaceKind != WorkspaceKind.localFs) {
      return false;
    }
    final association =
        thread.openClawTaskAssociation ??
        _inferOpenClawTaskAssociationFromThreadInternal(thread);
    if (association == null) {
      return false;
    }
    try {
      final result = await goTaskServiceClientInternal.getTask(
        route: GoTaskServiceRoute.externalAcpSingle,
        target: assistantExecutionTargetFromExecutionMode(
          thread.executionBinding.executionMode,
        ),
        association: association,
      );
      if (result.artifacts.isEmpty) {
        return false;
      }
      final status = result.status.trim();
      final nextAssociation =
          result.openClawTaskAssociation ??
          association.copyWith(status: status.isEmpty ? 'completed' : status);
      upsertTaskThreadInternal(
        normalizedSessionKey,
        openClawTaskAssociation: nextAssociation,
        lastRemoteWorkingDirectory: result.remoteWorkingDirectory.trim().isEmpty
            ? thread.lastRemoteWorkingDirectory
            : result.remoteWorkingDirectory.trim(),
        lastRemoteWorkspaceRefKind:
            result.remoteWorkspaceRefKind ?? thread.lastRemoteWorkspaceRefKind,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
      );
      await persistGoTaskArtifactsForSessionInternal(
        normalizedSessionKey,
        result,
      );
      final refreshed = taskThreadForSessionInternal(normalizedSessionKey);
      return refreshed?.lastTaskArtifactRelativePaths.isNotEmpty == true;
    } catch (error) {
      debugPrint(
        'Remote artifact sync failed for $normalizedSessionKey: $error',
      );
      return false;
    }
  }

  Future<AssistantArtifactPreview> loadAssistantArtifactPreview(
    AssistantArtifactEntry entry, {
    String? sessionKey,
  }) {
    final resolvedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey ?? currentSessionKey,
    );
    final thread = taskThreadForSessionInternal(resolvedSessionKey);
    return threadArtifactServiceInternal.loadPreview(
      entry: entry,
      workspacePath: assistantWorkspacePathForSession(resolvedSessionKey),
      workspaceKind: assistantWorkspaceKindForSession(resolvedSessionKey),
      artifactRelativePaths:
          thread?.lastTaskArtifactRelativePaths ?? const <String>[],
    );
  }

  String get assistantConversationOwnerLabel {
    return activeAgentName;
  }

  String get resolvedAssistantModel =>
      resolvedAssistantModelForTargetInternal(currentAssistantExecutionTarget);

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
    final bridgeConfigured = isBridgeAcpRuntimeConfiguredInternal();
    final bridgeReady = bridgeCapabilityReadyForExecutionTargetInternal(
      target: target,
      bridgeConfigured: bridgeConfigured,
      providers: providers,
      availableTargets: availableTargets,
    );
    final bridgeEndpoint = resolveBridgeAcpEndpointInternal();
    final bridgeLabel = bridgeEndpoint?.host.trim().isNotEmpty == true
        ? bridgeEndpoint!.host.trim()
        : 'xworkmate-bridge';
    return resolveGatewayThreadConnectionStateInternal(
      target: target,
      bridgeReady: bridgeReady,
      bridgeLabel: bridgeLabel,
      accountSyncState: settingsControllerInternal.accountSyncState,
      accountSignedIn: settingsControllerInternal.accountSignedIn,
      bridgeConfigured: bridgeConfigured,
      bridgeDiscoveryAttempted: bridgeCapabilitiesRefreshAttemptedInternal,
      bridgeDiscoveryError: bridgeCapabilitiesRefreshErrorInternal,
      providerCatalogEmpty: providers.isEmpty,
    );
  }

  bool bridgeCapabilityReadyForAssistantTargetInternal(
    AssistantExecutionTarget target,
  ) {
    return bridgeCapabilityReadyForExecutionTargetInternal(
      target: target,
      bridgeConfigured: isBridgeAcpRuntimeConfiguredInternal(),
      providers: providerCatalogForExecutionTarget(target),
      availableTargets: bridgeAvailableExecutionTargets,
    );
  }

  bool bridgeCapabilityRefreshNeededForAssistantTargetInternal(
    AssistantExecutionTarget target,
  ) {
    if (!isBridgeAcpRuntimeConfiguredInternal()) {
      return false;
    }
    return !bridgeCapabilityReadyForAssistantTargetInternal(target);
  }

  String get assistantConnectionStatusLabel =>
      currentAssistantConnectionState.primaryLabel;
  String get assistantConnectionTargetLabel =>
      currentAssistantConnectionState.detailLabel;

  Future<String> loadAiGatewayApiKey() =>
      loadAiGatewayApiKeyThreadSessionInternal(this);
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
    final chatSessionKey = normalizedAssistantSessionKeyInternal(
      chatControllerInternal.sessionKey,
    );
    final items = matchesSessionKey(chatSessionKey, sessionKey)
        ? List<GatewayChatMessage>.from(chatControllerInternal.messages)
        : <GatewayChatMessage>[];
    final threadItems = assistantThreadMessagesInternal[sessionKey];
    if (threadItems != null && threadItems.isNotEmpty) {
      items.addAll(threadItems);
    }
    final localItems = localSessionMessagesInternal[sessionKey];
    if (localItems != null && localItems.isNotEmpty) {
      items.addAll(localItems);
    }
    final streaming = matchesSessionKey(chatSessionKey, sessionKey)
        ? chatControllerInternal.streamingAssistantText?.trim() ?? ''
        : '';
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
    return dedupeGatewayChatMessagesByIdThreadSessionInternal(items);
  }

  List<GatewayChatMessage> dedupeGatewayChatMessagesByIdThreadSessionInternal(
    List<GatewayChatMessage> messages,
  ) {
    final seenIds = <String>{};
    final deduped = <GatewayChatMessage>[];
    for (final message in messages) {
      final id = message.id.trim();
      if (id.isNotEmpty && !seenIds.add(id)) {
        continue;
      }
      deduped.add(message);
    }
    return deduped;
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
    return resolveAssistantExecutionTargetFromRecordsInternal(record);
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

    for (final record in assistantThreadRecordsInternal.values) {
      final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
        record.sessionKey,
      );
      if (normalizedSessionKey.isEmpty ||
          !isAppOwnedAssistantSessionKeyInternal(normalizedSessionKey) ||
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
    if (isAppOwnedAssistantSessionKeyInternal(currentKey) &&
        !isAssistantTaskArchived(currentKey) &&
        !byKey.containsKey(currentKey)) {
      byKey[currentKey] = assistantSessionSummaryForInternal(currentKey);
    }

    return byKey.values.toList(growable: false);
  }

  List<GatewaySessionSummary> archivedAssistantSessionsInternal() {
    final items = <GatewaySessionSummary>[];
    for (final record in assistantThreadRecordsInternal.values) {
      final sessionKey = normalizedAssistantSessionKeyInternal(
        record.sessionKey,
      );
      if (!isAppOwnedAssistantSessionKeyInternal(sessionKey) ||
          !record.archived) {
        continue;
      }
      items.add(assistantSessionSummaryForInternal(sessionKey, record: record));
    }
    items.sort((left, right) {
      return (right.updatedAtMs ?? 0).compareTo(left.updatedAtMs ?? 0);
    });
    return items;
  }
}

OpenClawTaskAssociation? _inferOpenClawTaskAssociationFromThreadInternal(
  TaskThread thread,
) {
  final remoteWorkspace = thread.lastRemoteWorkingDirectory?.trim() ?? '';
  if (remoteWorkspace.isEmpty) {
    return null;
  }
  final normalized = remoteWorkspace.replaceAll('\\', '/');
  final segments = normalized
      .split('/')
      .where((segment) => segment.trim().isNotEmpty)
      .toList(growable: false);
  final tasksIndex = segments.lastIndexOf('tasks');
  if (tasksIndex < 0 || tasksIndex + 2 >= segments.length) {
    return null;
  }
  final taskDir = segments[tasksIndex + 1].trim();
  final runId = segments[tasksIndex + 2].trim();
  final openclawSessionKey = _openClawSessionKeyFromTaskDirInternal(taskDir);
  final appThreadKey = _appThreadKeyFromSessionKeyInternal(thread.threadId);
  if (runId.isEmpty || openclawSessionKey.isEmpty || appThreadKey.isEmpty) {
    return null;
  }
  return OpenClawTaskAssociation(
    sessionId: thread.threadId,
    threadId: thread.threadId,
    turnId: runId,
    runId: runId,
    artifactScope: remoteWorkspace,
    artifactDirectory: remoteWorkspace,
    gatewayProviderId: 'openclaw',
    startedAtMs: thread.lifecycleState.lastRunAtMs ?? 0,
    status: 'completed',
    appThreadKey: appThreadKey,
    openclawSessionKey: openclawSessionKey,
  );
}

String _appThreadKeyFromSessionKeyInternal(String sessionKey) {
  final normalized = sessionKey.trim();
  if (normalized.startsWith('draft:')) {
    return normalized;
  }
  if (normalized.startsWith('draft-')) {
    return 'draft:${normalized.substring('draft-'.length)}';
  }
  return normalized;
}

String _openClawSessionKeyFromTaskDirInternal(String taskDir) {
  final normalized = taskDir.trim();
  if (normalized.startsWith('agent_main_draft_')) {
    return 'agent:main:draft:${normalized.substring('agent_main_draft_'.length)}';
  }
  if (normalized.startsWith('draft_')) {
    return 'draft:${normalized.substring('draft_'.length)}';
  }
  return '';
}

AssistantExecutionTarget resolveAssistantExecutionTargetFromRecordForTest(
  TaskThread? record, {
  required AssistantExecutionTarget defaultExecutionTarget,
}) {
  return record == null
      ? defaultExecutionTarget
      : assistantExecutionTargetFromExecutionMode(
          record.executionBinding.executionMode,
        );
}
