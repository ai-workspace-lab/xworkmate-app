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
import '../runtime/direct_single_agent_app_server_client.dart';
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
import '../runtime/single_agent_runner.dart';
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
extension AppControllerDesktopThreadSessions on AppController {
  int assistantSkillCountForSession(String sessionKey) {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    final target = assistantExecutionTargetForSession(normalizedSessionKey);
    if (target == AssistantExecutionTarget.singleAgent ||
        target == AssistantExecutionTarget.auto) {
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
    if (target == AssistantExecutionTarget.singleAgent ||
        target == AssistantExecutionTarget.auto) {
      if (singleAgentUsesAiChatFallbackForSession(normalizedSessionKey)) {
        final recordModel =
            assistantThreadRecordsInternal[normalizedSessionKey]
                ?.assistantModelId
                .trim() ??
            '';
        if (recordModel.isNotEmpty) {
          return recordModel;
        }
        return resolvedAiGatewayModel;
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
    final existing =
        assistantThreadRecordsInternal[normalizedSessionKey]
            ?.workspaceBinding
            .workspacePath
            .trim() ??
        '';
    if (existing.isNotEmpty) {
      return existing;
    }
    final target = assistantExecutionTargetForSession(normalizedSessionKey);
    if (target == AssistantExecutionTarget.singleAgent ||
        target == AssistantExecutionTarget.auto) {
      return localThreadWorkspacePathInternal(normalizedSessionKey);
    }
    return '';
  }

  WorkspaceRefKind assistantWorkspaceKindForSession(String sessionKey) {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    final record = assistantThreadRecordsInternal[normalizedSessionKey];
    if (record != null) {
      return record.workspaceKind == WorkspaceKind.localFs
          ? WorkspaceRefKind.localPath
          : WorkspaceRefKind.remotePath;
    }
    return defaultWorkspaceRefKindForTargetInternal(
      assistantExecutionTargetForSession(normalizedSessionKey),
    );
  }

  String assistantWorkspaceDisplayPathForSession(String sessionKey) {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    return assistantThreadRecordsInternal[normalizedSessionKey]
            ?.workspaceBinding
            .displayPath
            .trim() ??
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
    final stored =
        assistantThreadRecordsInternal[normalizedSessionKey]
            ?.singleAgentProvider ??
        SingleAgentProvider.auto;
    return settings.resolveSingleAgentProvider(stored);
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

  bool singleAgentUsesAiChatFallbackForSession(String sessionKey) {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    if (assistantExecutionTargetForSession(normalizedSessionKey) !=
        AssistantExecutionTarget.singleAgent) {
      return false;
    }
    return !hasAnyAvailableSingleAgentProvider && canUseAiGatewayConversation;
  }

  bool get currentSingleAgentUsesAiChatFallback =>
      singleAgentUsesAiChatFallbackForSession(currentSessionKey);

  bool singleAgentNeedsAiGatewayConfigurationForSession(String sessionKey) {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    if (assistantExecutionTargetForSession(normalizedSessionKey) !=
        AssistantExecutionTarget.singleAgent) {
      return false;
    }
    return !hasAnyAvailableSingleAgentProvider && !canUseAiGatewayConversation;
  }

  bool get currentSingleAgentNeedsAiGatewayConfiguration =>
      singleAgentNeedsAiGatewayConfigurationForSession(currentSessionKey);

  bool singleAgentHasResolvedProviderForSession(String sessionKey) {
    return singleAgentResolvedProviderForSession(sessionKey) != null;
  }

  bool get currentSingleAgentHasResolvedProvider =>
      singleAgentHasResolvedProviderForSession(currentSessionKey);

  bool singleAgentShouldSuggestAutoSwitchForSession(String sessionKey) {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    if (assistantExecutionTargetForSession(normalizedSessionKey) !=
        AssistantExecutionTarget.singleAgent) {
      return false;
    }
    final selection = singleAgentProviderForSession(normalizedSessionKey);
    if (selection == SingleAgentProvider.auto) {
      return false;
    }
    return !canUseSingleAgentProviderInternal(selection) &&
        hasAnyAvailableSingleAgentProvider;
  }

  bool get currentSingleAgentShouldSuggestAutoSwitch =>
      singleAgentShouldSuggestAutoSwitchForSession(currentSessionKey);

  String singleAgentRuntimeModelForSession(String sessionKey) {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    return singleAgentRuntimeModelBySessionInternal[normalizedSessionKey]
            ?.trim() ??
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
    if (singleAgentUsesAiChatFallbackForSession(normalizedSessionKey)) {
      return appText('AI Chat fallback', 'AI Chat fallback');
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
    if (singleAgentUsesAiChatFallbackForSession(normalizedSessionKey)) {
      return true;
    }
    return singleAgentRuntimeModelForSession(normalizedSessionKey).isNotEmpty;
  }

  bool get currentSingleAgentShouldShowModelControl =>
      singleAgentShouldShowModelControlForSession(currentSessionKey);

  List<SingleAgentProvider> get singleAgentProviderOptions =>
      configuredSingleAgentProviders;

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
    if (provider != SingleAgentProvider.auto) {
      return provider.label;
    }
    if (currentSingleAgentUsesAiChatFallback) {
      return appText('AI Chat fallback', 'AI Chat fallback');
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
    if (target == AssistantExecutionTarget.singleAgent ||
        target == AssistantExecutionTarget.auto) {
      final provider = singleAgentProviderForSession(normalizedSessionKey);
      final resolvedProvider = singleAgentResolvedProviderForSession(
        normalizedSessionKey,
      );
      final model = assistantModelForSession(normalizedSessionKey);
      final fallbackReady = singleAgentUsesAiChatFallbackForSession(
        normalizedSessionKey,
      );
      final host = aiGatewayHostLabelInternal(aiGatewayUrl);
      final providerReady = resolvedProvider != null;
      final detail = providerReady
          ? joinConnectionPartsInternal(<String>[resolvedProvider.label, model])
          : fallbackReady
          ? joinConnectionPartsInternal(<String>[
              appText('AI Chat fallback', 'AI Chat fallback'),
              model,
              host,
            ])
          : singleAgentShouldSuggestAutoSwitchForSession(normalizedSessionKey)
          ? appText(
              '${provider.label} 不可用，可切到 Auto',
              '${provider.label} is unavailable. Switch to Auto.',
            )
          : singleAgentNeedsAiGatewayConfigurationForSession(
              normalizedSessionKey,
            )
          ? appText(
              '没有可用的外部 Agent ACP 端点，请配置 LLM API fallback。',
              'No external Agent ACP endpoint is available. Configure LLM API fallback.',
            )
          : appText(
              '当前线程的外部 Agent ACP 连接尚未就绪。',
              'The external Agent ACP connection for this thread is not ready yet.',
            );
      final primaryLabel = target == AssistantExecutionTarget.auto
          ? 'Auto'
          : target.label;
      final actualDetailPrefix = target == AssistantExecutionTarget.auto
          ? appText('当前: ', 'Current: ')
          : '';
      return AssistantThreadConnectionState(
        executionTarget: target,
        status: providerReady || fallbackReady
            ? RuntimeConnectionStatus.connected
            : RuntimeConnectionStatus.offline,
        primaryLabel: primaryLabel,
        detailLabel: detail.isEmpty
            ? appText('未配置单机智能体', 'Single Agent is not configured')
            : '$actualDetailPrefix$detail',
        ready: providerReady || fallbackReady,
        pairingRequired: false,
        gatewayTokenMissing: false,
        lastError: null,
      );
    }

    final expectedMode = target == AssistantExecutionTarget.local
        ? RuntimeConnectionMode.local
        : RuntimeConnectionMode.remote;
    final matchesTarget = connection.mode == expectedMode;
    final fallbackProfile = gatewayProfileForAssistantExecutionTargetInternal(
      target,
    );
    final fallbackAddress = gatewayAddressLabelInternal(fallbackProfile);
    final detail = matchesTarget
        ? (connection.remoteAddress?.trim().isNotEmpty == true
              ? connection.remoteAddress!.trim()
              : fallbackAddress)
        : fallbackAddress;
    final status = matchesTarget
        ? connection.status
        : RuntimeConnectionStatus.offline;
    return AssistantThreadConnectionState(
      executionTarget: target,
      status: status,
      primaryLabel: status.label,
      detailLabel: detail,
      ready: status == RuntimeConnectionStatus.connected,
      pairingRequired: matchesTarget && connection.pairingRequired,
      gatewayTokenMissing: matchesTarget && connection.gatewayTokenMissing,
      lastError: matchesTarget ? connection.lastError?.trim() : null,
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
        settings.assistantNavigationDestinations,
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
    return sanitizeExecutionTargetInternal(
      assistantThreadRecordsInternal[normalizedSessionKey]?.executionTarget ??
          settings.assistantExecutionTarget,
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
      AssistantExecutionTarget.auto => WorkspaceRefKind.localPath,
      AssistantExecutionTarget.singleAgent => WorkspaceRefKind.localPath,
      AssistantExecutionTarget.local ||
      AssistantExecutionTarget.remote => WorkspaceRefKind.remotePath,
    };
  }

  List<GatewaySessionSummary> assistantSessionsInternal() {
    final archivedKeys = settings.assistantArchivedTaskKeys
        .map(normalizedAssistantSessionKeyInternal)
        .toSet();
    final byKey = <String, GatewaySessionSummary>{};

    for (final session in sessionsControllerInternal.sessions) {
      final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
        session.key,
      );
      if (archivedKeys.contains(normalizedSessionKey)) {
        continue;
      }
      byKey[normalizedSessionKey] = session;
    }

    for (final record in assistantThreadRecordsInternal.values) {
      final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
        record.sessionKey,
      );
      if (normalizedSessionKey.isEmpty ||
          archivedKeys.contains(normalizedSessionKey) ||
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
    if (!archivedKeys.contains(currentKey) && !byKey.containsKey(currentKey)) {
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
