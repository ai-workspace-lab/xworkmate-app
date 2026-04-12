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
  required GatewayConnectionSnapshot connection,
  required GatewayConnectionProfile targetProfile,
}) {
  const expectedMode = RuntimeConnectionMode.remote;
  final matchesTarget = connection.mode == expectedMode;
  final targetAddress =
      targetProfile.host.trim().isNotEmpty && targetProfile.port > 0
      ? '${targetProfile.host.trim()}:${targetProfile.port}'
      : appText('未连接目标', 'No target');
  final rawStatus = matchesTarget
      ? connection.status
      : RuntimeConnectionStatus.offline;
  final pairingRequired = matchesTarget && connection.pairingRequired;
  final gatewayTokenMissing = matchesTarget && connection.gatewayTokenMissing;
  final status = pairingRequired || gatewayTokenMissing
      ? RuntimeConnectionStatus.error
      : rawStatus;
  final primaryLabel = pairingRequired
      ? appText('需配对', 'Pairing Required')
      : gatewayTokenMissing
      ? appText('缺少令牌', 'Missing Token')
      : status.label;
  return AssistantThreadConnectionState(
    executionTarget: target,
    status: status,
    primaryLabel: primaryLabel,
    detailLabel: targetAddress,
    ready: status == RuntimeConnectionStatus.connected,
    pairingRequired: pairingRequired,
    gatewayTokenMissing: gatewayTokenMissing,
    lastError: matchesTarget ? connection.lastError?.trim() : null,
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
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    final target = assistantExecutionTargetForSession(normalizedSessionKey);
    if (target == AssistantExecutionTarget.singleAgent) {
      return assistantImportedSkillsForSession(normalizedSessionKey).length;
    }
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
    final target = assistantExecutionTargetForSession(normalizedSessionKey);
    final latestResolvedModel =
        taskThreadForSessionInternal(
          normalizedSessionKey,
        )?.latestResolvedRuntimeModel.trim() ??
        '';
    if (target == AssistantExecutionTarget.singleAgent) {
      if (latestResolvedModel.isNotEmpty) {
        return latestResolvedModel;
      }
      return singleAgentRuntimeModelForSession(normalizedSessionKey);
    }
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
    return resolvedAssistantModelForTargetInternal(target);
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
      return WorkspaceRefKind.localPath;
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

  SingleAgentProvider singleAgentProviderForSession(String sessionKey) {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    final stored = SingleAgentProviderCopy.fromJsonValue(
      taskThreadForSessionInternal(
            normalizedSessionKey,
          )?.executionBinding.providerId ??
          '',
    );
    final sanitized = settings.sanitizeSingleAgentProviderSelection(stored);
    if (!sanitized.isUnspecified) {
      return sanitized;
    }
    final options = singleAgentProviderOptions;
    return options.isEmpty ? SingleAgentProvider.unspecified : options.first;
  }

  SingleAgentProvider get currentSingleAgentProvider =>
      singleAgentProviderForSession(currentSessionKey);

  SingleAgentProvider? singleAgentResolvedProviderForSession(
    String sessionKey,
  ) {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    return resolvedSingleAgentProviderInternal(
      singleAgentProviderForSession(normalizedSessionKey),
    );
  }

  SingleAgentProvider? get currentSingleAgentResolvedProvider =>
      singleAgentResolvedProviderForSession(currentSessionKey);

  bool singleAgentNeedsAiGatewayConfigurationForSession(String sessionKey) {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    if (assistantExecutionTargetForSession(normalizedSessionKey) !=
        AssistantExecutionTarget.singleAgent) {
      return false;
    }
    return !hasAnyAvailableSingleAgentProvider;
  }

  bool get currentSingleAgentNeedsAiGatewayConfiguration =>
      singleAgentNeedsAiGatewayConfigurationForSession(currentSessionKey);

  bool singleAgentHasResolvedProviderForSession(String sessionKey) {
    return singleAgentResolvedProviderForSession(sessionKey) != null;
  }

  bool get currentSingleAgentHasResolvedProvider =>
      singleAgentHasResolvedProviderForSession(currentSessionKey);

  bool singleAgentShouldSuggestAcpSwitchForSession(String sessionKey) {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    if (assistantExecutionTargetForSession(normalizedSessionKey) !=
        AssistantExecutionTarget.singleAgent) {
      return false;
    }
    final selection = singleAgentProviderForSession(normalizedSessionKey);
    if (selection.isUnspecified) {
      return false;
    }
    return !canUseSingleAgentProviderInternal(selection) &&
        hasAnyAvailableSingleAgentProvider;
  }

  bool get currentSingleAgentShouldSuggestAcpSwitch =>
      singleAgentShouldSuggestAcpSwitchForSession(currentSessionKey);

  String singleAgentRuntimeModelForSession(String sessionKey) {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    return taskThreadForSessionInternal(
          normalizedSessionKey,
        )?.latestResolvedRuntimeModel.trim() ??
        '';
  }

  String get currentSingleAgentRuntimeModel =>
      singleAgentRuntimeModelForSession(currentSessionKey);

  String singleAgentModelDisplayLabelForSession(String sessionKey) {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    final runtimeModel = singleAgentRuntimeModelForSession(
      normalizedSessionKey,
    );
    if (runtimeModel.isNotEmpty) {
      return runtimeModel;
    }
    final model = assistantModelForSession(normalizedSessionKey);
    if (model.isNotEmpty) {
      return model;
    }
    final provider =
        singleAgentResolvedProviderForSession(normalizedSessionKey) ??
        singleAgentProviderForSession(normalizedSessionKey);
    return appText(
      '请先配置 ${provider.label} 模型',
      'Configure ${provider.label} model',
    );
  }

  String get currentSingleAgentModelDisplayLabel =>
      singleAgentModelDisplayLabelForSession(currentSessionKey);

  bool singleAgentShouldShowModelControlForSession(String sessionKey) {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    if (assistantExecutionTargetForSession(normalizedSessionKey) !=
        AssistantExecutionTarget.singleAgent) {
      return true;
    }
    return singleAgentRuntimeModelForSession(normalizedSessionKey).isNotEmpty;
  }

  bool get currentSingleAgentShouldShowModelControl =>
      singleAgentShouldShowModelControlForSession(currentSessionKey);

  List<SingleAgentProvider> get singleAgentProviderOptions =>
      availableSingleAgentProviders.isNotEmpty
      ? availableSingleAgentProviders
      : configuredSingleAgentProviders;

  String singleAgentProviderLabelForSession(String sessionKey) {
    return singleAgentProviderForSession(sessionKey).label;
  }

  String get assistantConversationOwnerLabel {
    if (!isSingleAgentMode) {
      return activeAgentName;
    }
    final resolvedProvider = currentSingleAgentResolvedProvider;
    if (resolvedProvider != null) {
      return resolvedProvider.label;
    }
    final provider = currentSingleAgentProvider;
    if (!provider.isUnspecified) {
      return provider.label;
    }
    return appText('单机智能体', 'Single Agent');
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
    if (target == AssistantExecutionTarget.singleAgent) {
      final primaryLabel = appText('Bridge', 'Bridge');
      final provider = singleAgentProviderForSession(normalizedSessionKey);
      final resolvedProvider = singleAgentResolvedProviderForSession(
        normalizedSessionKey,
      );
      final model = assistantModelForSession(normalizedSessionKey);
      final providerReady = resolvedProvider != null;
      final detail = providerReady
          ? joinConnectionPartsInternal(<String>[resolvedProvider.label, model])
          : singleAgentShouldSuggestAcpSwitchForSession(normalizedSessionKey)
          ? appText(
              '${provider.label} 当前不可用，请改成 Bridge 当前可用的 Provider。',
              '${provider.label} is unavailable. Switch to a provider currently advertised by the bridge.',
            )
          : singleAgentNeedsAiGatewayConfigurationForSession(
              normalizedSessionKey,
            )
          ? appText(
              'Bridge 当前没有可用 Provider。',
              'The bridge does not currently advertise any available providers.',
            )
          : appText(
              '当前线程的 Bridge Provider 尚未就绪。',
              'The bridge provider for this thread is not ready yet.',
            );
      return AssistantThreadConnectionState(
        executionTarget: target,
        status: providerReady
            ? RuntimeConnectionStatus.connected
            : RuntimeConnectionStatus.offline,
        primaryLabel: primaryLabel,
        detailLabel: detail.isEmpty
            ? appText('未配置单机智能体', 'Single Agent is not configured')
            : detail,
        ready: providerReady,
        pairingRequired: false,
        gatewayTokenMissing: false,
        lastError: null,
      );
    }

    return resolveGatewayThreadConnectionStateInternal(
      target: target,
      connection: connection,
      targetProfile: gatewayProfileForAssistantExecutionTargetInternal(target),
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

  List<SecretReferenceEntry> get secretReferences =>
      settingsControllerInternal.buildSecretReferences();
  List<SecretAuditEntry> get secretAuditTrail =>
      settingsControllerInternal.auditTrail;
  List<RuntimeLogEntry> get runtimeLogs => runtimeInternal.logs;
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
      isSingleAgentMode
          ? const <GatewayChatMessage>[]
          : chatControllerInternal.messages,
    );
    final threadItems = isSingleAgentMode
        ? assistantThreadMessagesInternal[sessionKey]
        : null;
    if (threadItems != null && threadItems.isNotEmpty) {
      items.addAll(threadItems);
    }
    final localItems = localSessionMessagesInternal[sessionKey];
    if (localItems != null && localItems.isNotEmpty) {
      items.addAll(localItems);
    }
    final streaming = isSingleAgentMode
        ? (aiGatewayStreamingTextBySessionInternal[sessionKey]?.trim() ?? '')
        : (chatControllerInternal.streamingAssistantText?.trim() ?? '');
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
  ) {
    return switch (target) {
      AssistantExecutionTarget.singleAgent => WorkspaceRefKind.localPath,
      AssistantExecutionTarget.gateway => WorkspaceRefKind.remotePath,
    };
  }

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
      ? AssistantExecutionTarget.singleAgent
      : assistantExecutionTargetFromExecutionMode(
          record.executionBinding.executionMode,
        );
}
