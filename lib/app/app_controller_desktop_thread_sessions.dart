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
import 'app_controller_desktop_thread_actions.dart';
import 'app_controller_desktop_workspace_execution.dart';
import 'app_controller_desktop_settings_runtime.dart';
import 'app_controller_desktop_thread_storage.dart';
import 'app_controller_desktop_skill_permissions.dart';
import 'app_controller_desktop_runtime_helpers.dart';

// ignore_for_file: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
extension AppControllerDesktopThreadSessions on AppController {
  int assistantSkillCountForSession(String sessionKey) {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    if (assistantExecutionTargetForSession(normalizedSessionKey) ==
        AssistantExecutionTarget.singleAgent) {
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
    if (target == AssistantExecutionTarget.singleAgent) {
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
    if (recordModel.isNotEmpty) {
      return recordModel;
    }
    return resolvedAssistantModelForTargetInternal(target);
  }

  String assistantWorkspaceRefForSession(String sessionKey) {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    final recordRef =
        assistantThreadRecordsInternal[normalizedSessionKey]?.workspaceRef
            .trim() ??
        '';
    if (recordRef.isNotEmpty) {
      return recordRef;
    }
    return defaultWorkspaceRefForSessionInternal(normalizedSessionKey);
  }

  WorkspaceRefKind assistantWorkspaceRefKindForSession(String sessionKey) {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    final record = assistantThreadRecordsInternal[normalizedSessionKey];
    if (record != null && record.workspaceRef.trim().isNotEmpty) {
      return record.workspaceRefKind;
    }
    return defaultWorkspaceRefKindForTargetInternal(
      assistantExecutionTargetForSession(normalizedSessionKey),
    );
  }

  Future<AssistantArtifactSnapshot> loadAssistantArtifactSnapshot({
    String? sessionKey,
  }) {
    final resolvedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey ?? currentSessionKey,
    );
    return threadArtifactServiceInternal.loadSnapshot(
      workspaceRef: assistantWorkspaceRefForSession(resolvedSessionKey),
      workspaceRefKind: assistantWorkspaceRefKindForSession(resolvedSessionKey),
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
      workspaceRef: assistantWorkspaceRefForSession(resolvedSessionKey),
      workspaceRefKind: assistantWorkspaceRefKindForSession(resolvedSessionKey),
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
      <SingleAgentProvider>[
        SingleAgentProvider.auto,
        ...configuredSingleAgentProviders,
      ];

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
    if (target == AssistantExecutionTarget.singleAgent) {
      final provider = singleAgentProviderForSession(normalizedSessionKey);
      final resolvedProvider = singleAgentResolvedProviderForSession(
        normalizedSessionKey,
      );
      final model = assistantModelForSession(normalizedSessionKey);
      final fallbackReady = singleAgentUsesAiChatFallbackForSession(
        normalizedSessionKey,
      );
      final host = aiGatewayHostLabelInternal(settings.aiGateway.baseUrl);
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
      return AssistantThreadConnectionState(
        executionTarget: target,
        status: providerReady || fallbackReady
            ? RuntimeConnectionStatus.connected
            : RuntimeConnectionStatus.offline,
        primaryLabel: target.label,
        detailLabel: detail.isEmpty
            ? appText('未配置单机智能体', 'Single Agent is not configured')
            : detail,
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

  String get assistantConnectionTargetLabel {
    return currentAssistantConnectionState.detailLabel;
  }

  Future<String> loadAiGatewayApiKey() async {
    return (await storeInternal.loadAiGatewayApiKey())?.trim() ?? '';
  }

  Future<void> saveMultiAgentConfig(MultiAgentConfig config) async {
    final resolved = resolveMultiAgentConfigInternal(
      settings.copyWith(multiAgent: config),
    );
    await AppControllerDesktopSettings(this).saveSettings(
      settings.copyWith(multiAgent: resolved),
      refreshAfterSave: false,
    );
    await refreshMultiAgentMounts(sync: resolved.autoSync);
  }

  Future<void> refreshMultiAgentMounts({bool sync = false}) async {
    await refreshAcpCapabilitiesInternal(persistMountTargets: true);
  }

  Future<void> runMultiAgentCollaboration({
    required String rawPrompt,
    required String composedPrompt,
    required List<CollaborationAttachment> attachments,
    required List<String> selectedSkillLabels,
  }) async {
    final sessionKey = currentSessionKey.trim().isEmpty
        ? 'main'
        : currentSessionKey;
    await enqueueThreadTurnInternal<void>(sessionKey, () async {
      final aiGatewayApiKey = await loadAiGatewayApiKey();
      multiAgentRunPendingInternal = true;
      appendLocalSessionMessageInternal(
        sessionKey,
        GatewayChatMessage(
          id: nextLocalMessageIdInternal(),
          role: 'user',
          text: rawPrompt,
          timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
          toolCallId: null,
          toolName: null,
          stopReason: null,
          pending: false,
          error: false,
        ),
      );
      recomputeTasksInternal();
      try {
        final taskStream = gatewayAcpClientInternal.runMultiAgent(
          GatewayAcpMultiAgentRequest(
            sessionId: sessionKey,
            threadId: sessionKey,
            prompt: composedPrompt,
            workingDirectory:
                assistantWorkingDirectoryForSessionInternal(sessionKey) ??
                Directory.current.path,
            attachments: attachments,
            selectedSkills: selectedSkillLabels,
            aiGatewayBaseUrl: aiGatewayUrl,
            aiGatewayApiKey: aiGatewayApiKey,
            resumeSession: true,
          ),
        );
        await for (final event in taskStream) {
          if (event.type == 'result') {
            final success = event.data['success'] == true;
            final finalScore = event.data['finalScore'];
            final iterations = event.data['iterations'];
            appendLocalSessionMessageInternal(
              sessionKey,
              GatewayChatMessage(
                id: nextLocalMessageIdInternal(),
                role: 'assistant',
                text: success
                    ? appText(
                        '多 Agent 协作完成，评分 ${finalScore ?? '-'}，迭代 ${iterations ?? 0} 次。',
                        'Multi-agent collaboration completed with score ${finalScore ?? '-'} after ${iterations ?? 0} iteration(s).',
                      )
                    : appText(
                        '多 Agent 协作失败：${event.data['error'] ?? event.message}',
                        'Multi-agent collaboration failed: ${event.data['error'] ?? event.message}',
                      ),
                timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
                toolCallId: null,
                toolName: null,
                stopReason: null,
                pending: false,
                error: !success,
              ),
            );
            continue;
          }
          appendLocalSessionMessageInternal(
            sessionKey,
            GatewayChatMessage(
              id: nextLocalMessageIdInternal(),
              role: 'assistant',
              text: event.message,
              timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
              toolCallId: null,
              toolName: event.title,
              stopReason: null,
              pending: event.pending,
              error: event.error,
            ),
          );
        }
      } on GatewayAcpException catch (error) {
        appendLocalSessionMessageInternal(
          sessionKey,
          GatewayChatMessage(
            id: nextLocalMessageIdInternal(),
            role: 'assistant',
            text: appText(
              '多 Agent 协作不可用（Gateway ACP）：${error.message}',
              'Multi-agent collaboration is unavailable (Gateway ACP): ${error.message}',
            ),
            timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
            toolCallId: null,
            toolName: 'Multi-Agent',
            stopReason: null,
            pending: false,
            error: true,
          ),
        );
      } catch (error) {
        appendLocalSessionMessageInternal(
          sessionKey,
          GatewayChatMessage(
            id: nextLocalMessageIdInternal(),
            role: 'assistant',
            text: error.toString(),
            timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
            toolCallId: null,
            toolName: 'Multi-Agent',
            stopReason: null,
            pending: false,
            error: true,
          ),
        );
      } finally {
        multiAgentRunPendingInternal = false;
        recomputeTasksInternal();
        notifyIfActiveInternal();
      }
    });
  }

  Future<void> openOnlineWorkspace() async {
    const url = 'https://www.svc.plus/Xworkmate';
    try {
      if (Platform.isMacOS) {
        await Process.run('open', [url]);
        return;
      }
      if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', '', url]);
        return;
      }
      if (Platform.isLinux) {
        await Process.run('xdg-open', [url]);
      }
    } catch (_) {
      // Best effort only. Do not surface a blocking error from a convenience link.
    }
  }

  List<String> get aiGatewayModelChoices {
    return aiGatewayConversationModelChoices;
  }

  List<String> get connectedGatewayModelChoices {
    if (connection.status != RuntimeConnectionStatus.connected) {
      return const <String>[];
    }
    return modelsControllerInternal.items
        .map((item) => item.id.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  List<String> get assistantModelChoices {
    return assistantModelChoicesForSessionInternal(currentSessionKey);
  }

  List<String> assistantModelChoicesForSessionInternal(String sessionKey) {
    final target = assistantExecutionTargetForSession(sessionKey);
    if (target == AssistantExecutionTarget.singleAgent) {
      if (singleAgentUsesAiChatFallbackForSession(sessionKey)) {
        return aiGatewayConversationModelChoices;
      }
      final selectedModel =
          assistantThreadRecordsInternal[normalizedAssistantSessionKeyInternal(
                sessionKey,
              )]
              ?.assistantModelId
              .trim();
      if (selectedModel?.isNotEmpty == true) {
        return <String>[selectedModel!];
      }
      return const <String>[];
    }
    final runtimeModels = connectedGatewayModelChoices;
    if (runtimeModels.isNotEmpty) {
      return runtimeModels;
    }
    final resolved = resolvedDefaultModel.trim();
    if (resolved.isNotEmpty) {
      return <String>[resolved];
    }
    final localDefault = settings.ollamaLocal.defaultModel.trim();
    if (localDefault.isNotEmpty) {
      return <String>[localDefault];
    }
    return const <String>[];
  }

  String get resolvedDefaultModel {
    final current = settings.defaultModel.trim();
    if (current.isNotEmpty) {
      return current;
    }
    final localDefault = settings.ollamaLocal.defaultModel.trim();
    if (localDefault.isNotEmpty) {
      return localDefault;
    }
    final runtimeModels = connectedGatewayModelChoices;
    if (runtimeModels.isNotEmpty) {
      return runtimeModels.first;
    }
    final aiGatewayChoices = aiGatewayConversationModelChoices;
    if (aiGatewayChoices.isNotEmpty) {
      return aiGatewayChoices.first;
    }
    return '';
  }

  bool get canQuickConnectGateway {
    final target = currentAssistantExecutionTarget;
    if (target == AssistantExecutionTarget.singleAgent) {
      return false;
    }
    final profile = gatewayProfileForAssistantExecutionTargetInternal(target);
    if (profile.useSetupCode && profile.setupCode.trim().isNotEmpty) {
      return true;
    }
    final host = profile.host.trim();
    if (host.isEmpty || profile.port <= 0) {
      return false;
    }
    if (profile.mode == RuntimeConnectionMode.local) {
      return true;
    }
    final defaults = switch (target) {
      AssistantExecutionTarget.singleAgent =>
        GatewayConnectionProfile.emptySlot(index: kGatewayRemoteProfileIndex),
      AssistantExecutionTarget.local =>
        GatewayConnectionProfile.defaultsLocal(),
      AssistantExecutionTarget.remote =>
        GatewayConnectionProfile.defaultsRemote(),
    };
    return hasStoredGatewayCredential ||
        host != defaults.host ||
        profile.port != defaults.port ||
        profile.tls != defaults.tls ||
        profile.mode != defaults.mode;
  }

  String joinConnectionPartsInternal(List<String> parts) {
    final normalized = parts
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    return normalized.join(' · ');
  }

  String gatewayAddressLabelInternal(GatewayConnectionProfile profile) {
    final host = profile.host.trim();
    if (host.isEmpty || profile.port <= 0) {
      return appText('未连接目标', 'No target');
    }
    return '$host:${profile.port}';
  }

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

  String defaultWorkspaceRefForSessionInternal(String sessionKey) {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    return defaultLocalWorkspaceRefForSessionInternal(normalizedSessionKey);
  }

  String defaultLocalWorkspaceRefForSessionInternal(String sessionKey) {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    final baseWorkspace = settings.workspacePath.trim();
    if (baseWorkspace.isEmpty) {
      return '';
    }
    final threadWorkspace =
        '${trimTrailingPathSeparatorInternal(baseWorkspace)}/.xworkmate/threads/${threadWorkspaceDirectoryNameInternal(normalizedSessionKey)}';
    ensureLocalWorkspaceDirectoryInternal(threadWorkspace);
    return threadWorkspace;
  }

  String threadWorkspaceDirectoryNameInternal(String sessionKey) {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    final sanitized = normalizedSessionKey
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
        .replaceAll(RegExp(r'-{2,}'), '-')
        .replaceAll(RegExp(r'^[-.]+|[-.]+$'), '');
    return sanitized.isEmpty ? 'thread' : sanitized;
  }

  String trimTrailingPathSeparatorInternal(String path) {
    if (path.endsWith('/') && path.length > 1) {
      return path.substring(0, path.length - 1);
    }
    return path;
  }

  void ensureLocalWorkspaceDirectoryInternal(String path) {
    final normalizedPath = path.trim();
    if (normalizedPath.isEmpty) {
      return;
    }
    try {
      Directory(normalizedPath).createSync(recursive: true);
    } catch (_) {
      // Best effort only. The caller can still decide whether to use fallback behavior.
    }
  }

  bool usesLegacySharedWorkspaceRefInternal(
    String? workspaceRef,
    WorkspaceRefKind? workspaceRefKind,
  ) {
    final normalizedRef = workspaceRef?.trim() ?? '';
    if (normalizedRef.isEmpty) {
      return false;
    }
    return workspaceRefKind == WorkspaceRefKind.localPath &&
        normalizedRef == settings.workspacePath.trim();
  }

  bool usesDefaultThreadWorkspaceRefFromAnotherRootInternal(
    String sessionKey, {
    String? workspaceRef,
    WorkspaceRefKind? workspaceRefKind,
  }) {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    final normalizedRef = workspaceRef?.trim() ?? '';
    if (normalizedRef.isEmpty ||
        workspaceRefKind != WorkspaceRefKind.localPath) {
      return false;
    }
    final expectedDefault = defaultWorkspaceRefForSessionInternal(
      normalizedSessionKey,
    ).trim();
    if (expectedDefault.isEmpty) {
      return false;
    }
    final normalizedPath = trimTrailingPathSeparatorInternal(
      normalizedRef.replaceAll('\\', '/'),
    );
    final normalizedExpected = trimTrailingPathSeparatorInternal(
      expectedDefault.replaceAll('\\', '/'),
    );
    if (normalizedPath == normalizedExpected) {
      return false;
    }
    final expectedSuffix =
        '/.xworkmate/threads/${threadWorkspaceDirectoryNameInternal(normalizedSessionKey)}';
    return normalizedPath.endsWith(expectedSuffix);
  }

  bool shouldMigrateWorkspaceRefInternal(
    String sessionKey, {
    String? workspaceRef,
    WorkspaceRefKind? workspaceRefKind,
  }) {
    final normalizedRef = workspaceRef?.trim() ?? '';
    if (normalizedRef.isEmpty) {
      return true;
    }
    if (usesMissingWorkspaceRefInternal(
      sessionKey,
      workspaceRefKind,
      normalizedRef,
    )) {
      return true;
    }
    return usesLegacySharedWorkspaceRefInternal(
          normalizedRef,
          workspaceRefKind,
        ) ||
        usesDefaultThreadWorkspaceRefFromAnotherRootInternal(
          sessionKey,
          workspaceRef: normalizedRef,
          workspaceRefKind: workspaceRefKind,
        );
  }

  bool usesMissingWorkspaceRefInternal(
    String sessionKey,
    WorkspaceRefKind? workspaceRefKind,
    String workspaceRef,
  ) {
    if (workspaceRefKind != WorkspaceRefKind.localPath) {
      return false;
    }
    final normalizedPath = workspaceRef.trim();
    if (normalizedPath.isEmpty) {
      return true;
    }
    return FileSystemEntity.typeSync(normalizedPath) ==
        FileSystemEntityType.notFound;
  }

  WorkspaceRefKind defaultWorkspaceRefKindForTargetInternal(
    AssistantExecutionTarget target,
  ) {
    return switch (target) {
      AssistantExecutionTarget.singleAgent => WorkspaceRefKind.localPath,
      AssistantExecutionTarget.local ||
      AssistantExecutionTarget.remote => WorkspaceRefKind.remotePath,
    };
  }

  void syncAssistantWorkspaceRefForSessionInternal(
    String sessionKey, {
    AssistantExecutionTarget? executionTarget,
  }) {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    final nextWorkspaceRef = defaultWorkspaceRefForSessionInternal(
      normalizedSessionKey,
    );
    final nextWorkspaceRefKind = defaultWorkspaceRefKindForTargetInternal(
      executionTarget ??
          assistantExecutionTargetForSession(normalizedSessionKey),
    );
    final existing = assistantThreadRecordsInternal[normalizedSessionKey];
    final existingWorkspaceRef = existing?.workspaceRef.trim() ?? '';
    if (existing != null &&
        existingWorkspaceRef.isNotEmpty &&
        existing.workspaceRefKind == nextWorkspaceRefKind &&
        !shouldMigrateWorkspaceRefInternal(
          normalizedSessionKey,
          workspaceRef: existingWorkspaceRef,
          workspaceRefKind: existing.workspaceRefKind,
        )) {
      return;
    }
    if (existing != null &&
        existingWorkspaceRef == nextWorkspaceRef &&
        existing.workspaceRefKind == nextWorkspaceRefKind) {
      return;
    }
    upsertAssistantThreadRecordInternal(
      normalizedSessionKey,
      executionTarget:
          executionTarget ??
          assistantExecutionTargetForSession(normalizedSessionKey),
      workspaceRef: nextWorkspaceRef,
      workspaceRefKind: nextWorkspaceRefKind,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
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
