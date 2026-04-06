// ignore_for_file: unused_import, unnecessary_import

import 'dart:async';
import 'package:flutter/material.dart';
import '../i18n/app_language.dart';
import '../models/app_models.dart';
import '../runtime/assistant_artifacts.dart';
import '../runtime/runtime_models.dart';
import '../web/web_acp_client.dart';
import '../web/web_ai_gateway_client.dart';
import '../web/web_artifact_proxy_client.dart';
import '../web/web_relay_gateway_client.dart';
import '../web/web_session_repository.dart';
import '../web/web_store.dart';
import '../web/web_workspace_controllers.dart';
import 'app_capabilities.dart';
import 'ui_feature_manifest.dart';
import 'app_controller_web_core.dart';
import 'app_controller_web_workspace.dart';
import 'app_controller_web_session_actions.dart';
import 'app_controller_web_gateway_config.dart';
import 'app_controller_web_gateway_relay.dart';
import 'app_controller_web_gateway_chat.dart';
import 'app_controller_web_helpers.dart';

extension AppControllerWebSessions on AppController {
  AssistantExecutionTarget assistantExecutionTargetForSession(
    String sessionKey,
  ) {
    final normalizedSessionKey = normalizedSessionKeyInternal(sessionKey);
    final recordTarget = sanitizeTargetInternal(
      threadRecordsInternal[normalizedSessionKey]?.executionTarget,
    );
    final fallback = sanitizeTargetInternal(
      settingsInternal.assistantExecutionTarget,
    );
    return recordTarget ?? fallback ?? AssistantExecutionTarget.auto;
  }

  AssistantExecutionTarget get assistantExecutionTarget =>
      assistantExecutionTargetForSession(currentSessionKeyInternal);
  AssistantExecutionTarget get currentAssistantExecutionTarget =>
      assistantExecutionTarget;
  bool get isSingleAgentMode =>
      assistantExecutionTarget == AssistantExecutionTarget.singleAgent ||
      assistantExecutionTarget == AssistantExecutionTarget.auto;

  AssistantMessageViewMode assistantMessageViewModeForSession(
    String sessionKey,
  ) {
    final normalizedSessionKey = normalizedSessionKeyInternal(sessionKey);
    return threadRecordsInternal[normalizedSessionKey]?.messageViewMode ??
        AssistantMessageViewMode.rendered;
  }

  AssistantMessageViewMode get currentAssistantMessageViewMode =>
      assistantMessageViewModeForSession(currentSessionKeyInternal);

  String assistantWorkspacePathForSession(String sessionKey) {
    final normalizedSessionKey = normalizedSessionKeyInternal(sessionKey);
    return threadRecordsInternal[normalizedSessionKey]
            ?.workspaceBinding
            .workspacePath
            .trim() ??
        '';
  }

  WorkspaceRefKind assistantWorkspaceKindForSession(String sessionKey) {
    final normalizedSessionKey = normalizedSessionKeyInternal(sessionKey);
    final record = threadRecordsInternal[normalizedSessionKey];
    if (record == null || !record.workspaceBinding.isComplete) {
      throw StateError(
        'TaskThread $normalizedSessionKey is missing a complete workspaceBinding.',
      );
    }
    return record.workspaceKind == WorkspaceKind.localFs
        ? WorkspaceRefKind.localPath
        : WorkspaceRefKind.remotePath;
  }

  String assistantWorkspaceDisplayPathForSession(String sessionKey) {
    final normalizedSessionKey = normalizedSessionKeyInternal(sessionKey);
    return threadRecordsInternal[normalizedSessionKey]
            ?.workspaceBinding
            .displayPath
            .trim() ??
        '';
  }

  Future<AssistantArtifactSnapshot> loadAssistantArtifactSnapshot({
    String? sessionKey,
  }) {
    final resolvedSessionKey = normalizedSessionKeyInternal(
      sessionKey ?? currentSessionKeyInternal,
    );
    return artifactProxyClientInternal.loadSnapshot(
      sessionKey: resolvedSessionKey,
      workspacePath: assistantWorkspacePathForSession(resolvedSessionKey),
      workspaceKind: assistantWorkspaceKindForSession(resolvedSessionKey),
    );
  }

  Future<AssistantArtifactPreview> loadAssistantArtifactPreview(
    AssistantArtifactEntry entry, {
    String? sessionKey,
  }) {
    final resolvedSessionKey = normalizedSessionKeyInternal(
      sessionKey ?? currentSessionKeyInternal,
    );
    return artifactProxyClientInternal.loadPreview(
      sessionKey: resolvedSessionKey,
      entry: entry,
    );
  }

  SingleAgentProvider singleAgentProviderForSession(String sessionKey) {
    final normalizedSessionKey = normalizedSessionKeyInternal(sessionKey);
    final stored =
        threadRecordsInternal[normalizedSessionKey]?.singleAgentProvider ??
        SingleAgentProvider.auto;
    return settingsInternal.resolveSingleAgentProvider(stored);
  }

  SingleAgentProvider get currentSingleAgentProvider =>
      singleAgentProviderForSession(currentSessionKeyInternal);

  List<SingleAgentProvider> get singleAgentProviderOptions =>
      settingsInternal.availableSingleAgentProviders;

  bool singleAgentUsesAiChatFallbackForSession(String sessionKey) {
    final provider = singleAgentProviderForSession(sessionKey);
    return provider == SingleAgentProvider.auto && canUseAiGatewayConversation;
  }

  bool get currentSingleAgentUsesAiChatFallback =>
      singleAgentUsesAiChatFallbackForSession(currentSessionKeyInternal);

  String singleAgentRuntimeModelForSession(String sessionKey) {
    return singleAgentRuntimeModelBySessionInternal[normalizedSessionKeyInternal(
              sessionKey,
            )]
            ?.trim() ??
        '';
  }

  String get currentSingleAgentRuntimeModel =>
      singleAgentRuntimeModelForSession(currentSessionKeyInternal);

  String assistantModelForSession(String sessionKey) {
    final normalizedSessionKey = normalizedSessionKeyInternal(sessionKey);
    final target = assistantExecutionTargetForSession(normalizedSessionKey);
    final recordModel =
        threadRecordsInternal[normalizedSessionKey]?.assistantModelId.trim() ??
        '';
    if (target == AssistantExecutionTarget.singleAgent ||
        target == AssistantExecutionTarget.auto) {
      if (singleAgentUsesAiChatFallbackForSession(normalizedSessionKey)) {
        if (recordModel.isNotEmpty) {
          return recordModel;
        }
        return resolvedAiGatewayModel;
      }
      final runtimeModel = singleAgentRuntimeModelForSession(
        normalizedSessionKey,
      );
      if (runtimeModel.isNotEmpty) {
        return runtimeModel;
      }
      if (recordModel.isNotEmpty) {
        return recordModel;
      }
      return resolvedAiGatewayModel;
    }
    if (recordModel.isNotEmpty) {
      return recordModel;
    }
    return settingsInternal.defaultModel.trim();
  }

  String get resolvedAssistantModel =>
      assistantModelForSession(currentSessionKeyInternal);

  List<String> assistantModelChoicesForSession(String sessionKey) {
    final target = assistantExecutionTargetForSession(sessionKey);
    if (target == AssistantExecutionTarget.singleAgent ||
        target == AssistantExecutionTarget.auto) {
      if (singleAgentUsesAiChatFallbackForSession(sessionKey)) {
        return aiGatewayConversationModelChoices;
      }
      final runtime = singleAgentRuntimeModelForSession(sessionKey);
      if (runtime.isNotEmpty) {
        return <String>[runtime];
      }
      final recordModel = assistantModelForSession(sessionKey);
      if (recordModel.isNotEmpty) {
        return <String>[recordModel];
      }
      return aiGatewayConversationModelChoices;
    }
    final model = settingsInternal.defaultModel.trim();
    if (model.isEmpty) {
      return const <String>[];
    }
    return <String>[model];
  }

  List<String> get assistantModelChoices =>
      assistantModelChoicesForSession(currentSessionKeyInternal);

  List<AssistantThreadSkillEntry> assistantImportedSkillsForSession(
    String sessionKey,
  ) {
    return threadRecordsInternal[normalizedSessionKeyInternal(sessionKey)]
            ?.importedSkills ??
        const <AssistantThreadSkillEntry>[];
  }

  List<String> assistantSelectedSkillKeysForSession(String sessionKey) {
    final normalizedSessionKey = normalizedSessionKeyInternal(sessionKey);
    final importedKeys = assistantImportedSkillsForSession(
      normalizedSessionKey,
    ).map((item) => item.key).toSet();
    final selected =
        threadRecordsInternal[normalizedSessionKey]?.selectedSkillKeys ??
        const <String>[];
    return selected
        .where((item) => importedKeys.contains(item))
        .toList(growable: false);
  }

  int get currentAssistantSkillCount {
    final target = assistantExecutionTargetForSession(
      currentSessionKeyInternal,
    );
    if (target == AssistantExecutionTarget.singleAgent) {
      return assistantImportedSkillsForSession(
        currentSessionKeyInternal,
      ).length;
    }
    return assistantImportedSkillsForSession(currentSessionKeyInternal).length;
  }

  List<GatewaySkillSummary> get skills => assistantImportedSkillsForSession(
    currentSessionKeyInternal,
  ).map(gatewaySkillFromThreadEntryInternal).toList(growable: false);

  List<GatewayModelSummary> get models {
    if (relayModelsInternal.isNotEmpty &&
        assistantExecutionTargetForSession(currentSessionKeyInternal) !=
            AssistantExecutionTarget.singleAgent) {
      return relayModelsInternal;
    }
    return aiGatewayConversationModelChoices
        .map(
          (item) => GatewayModelSummary(
            id: item,
            name: item,
            provider: settingsInternal.defaultProvider.trim().isEmpty
                ? 'gateway'
                : settingsInternal.defaultProvider.trim(),
            contextWindow: null,
            maxOutputTokens: null,
          ),
        )
        .toList(growable: false);
  }

  bool get currentSingleAgentNeedsAiGatewayConfiguration =>
      currentSingleAgentUsesAiChatFallback && !canUseAiGatewayConversation;

  List<SecretReferenceEntry> get secretReferences {
    final entries = <SecretReferenceEntry>[
      if (storedRelayTokenMaskForProfile(kGatewayLocalProfileIndex) != null)
        SecretReferenceEntry(
          name: 'gateway_token.local',
          provider: 'Gateway',
          module: 'Assistant',
          maskedValue: storedRelayTokenMaskForProfile(
            kGatewayLocalProfileIndex,
          )!,
          status: 'In Use',
        ),
      if (storedRelayPasswordMaskForProfile(kGatewayLocalProfileIndex) != null)
        SecretReferenceEntry(
          name: 'gateway_password.local',
          provider: 'Gateway',
          module: 'Assistant',
          maskedValue: storedRelayPasswordMaskForProfile(
            kGatewayLocalProfileIndex,
          )!,
          status: 'In Use',
        ),
      if (storedRelayTokenMaskForProfile(kGatewayRemoteProfileIndex) != null)
        SecretReferenceEntry(
          name: 'gateway_token.remote',
          provider: 'Gateway',
          module: 'Assistant',
          maskedValue: storedRelayTokenMaskForProfile(
            kGatewayRemoteProfileIndex,
          )!,
          status: 'In Use',
        ),
      if (storedRelayPasswordMaskForProfile(kGatewayRemoteProfileIndex) != null)
        SecretReferenceEntry(
          name: 'gateway_password.remote',
          provider: 'Gateway',
          module: 'Assistant',
          maskedValue: storedRelayPasswordMaskForProfile(
            kGatewayRemoteProfileIndex,
          )!,
          status: 'In Use',
        ),
      if (storedAiGatewayApiKeyMask != null)
        SecretReferenceEntry(
          name: settingsInternal.aiGateway.apiKeyRef,
          provider: 'LLM API',
          module: 'Settings',
          maskedValue: storedAiGatewayApiKeyMask!,
          status: 'In Use',
        ),
      SecretReferenceEntry(
        name: settingsInternal.aiGateway.name,
        provider: 'LLM API',
        module: 'Settings',
        maskedValue: settingsInternal.aiGateway.baseUrl.trim().isEmpty
            ? 'Not set'
            : settingsInternal.aiGateway.baseUrl.trim(),
        status: settingsInternal.aiGateway.syncState,
      ),
    ];
    return entries;
  }

  List<GatewayChatMessage> get chatMessages {
    final base = List<GatewayChatMessage>.from(currentRecordInternal.messages);
    final streaming =
        streamingTextBySessionInternal[currentSessionKeyInternal]?.trim() ?? '';
    if (streaming.isNotEmpty) {
      base.add(
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
    return base;
  }

  List<WebConversationSummary> get conversations {
    final archivedKeys = settingsInternal.assistantArchivedTaskKeys
        .map(normalizedSessionKeyInternal)
        .toSet();
    final entries =
        threadRecordsInternal.values
            .where(
              (record) =>
                  !record.archived &&
                  !archivedKeys.contains(
                    normalizedSessionKeyInternal(record.sessionKey),
                  ),
            )
            .map(
              (record) => WebConversationSummary(
                sessionKey: record.sessionKey,
                title: titleForRecordInternal(record),
                preview: previewForRecordInternal(record),
                updatedAtMs:
                    record.updatedAtMs ??
                    DateTime.now().millisecondsSinceEpoch.toDouble(),
                executionTarget: assistantExecutionTargetForSession(
                  record.sessionKey,
                ),
                pending: pendingSessionKeysInternal.contains(record.sessionKey),
                current: record.sessionKey == currentSessionKeyInternal,
              ),
            )
            .toList(growable: true)
          ..sort((left, right) {
            if (left.current != right.current) {
              return left.current ? -1 : 1;
            }
            return right.updatedAtMs.compareTo(left.updatedAtMs);
          });
    return entries;
  }

  List<WebConversationSummary> conversationsForTarget(
    AssistantExecutionTarget target,
  ) {
    return conversations
        .where((item) => item.executionTarget == target)
        .toList(growable: false);
  }

  String get aiGatewayUrl => settingsInternal.aiGateway.baseUrl.trim();
  String get resolvedAiGatewayModel {
    final current = settingsInternal.defaultModel.trim();
    final choices = aiGatewayConversationModelChoices;
    if (choices.contains(current)) {
      return current;
    }
    if (choices.isNotEmpty) {
      return choices.first;
    }
    return '';
  }

  List<String> get aiGatewayConversationModelChoices {
    final selected = settingsInternal.aiGateway.selectedModels
        .map((item) => item.trim())
        .where(
          (item) =>
              item.isNotEmpty &&
              settingsInternal.aiGateway.availableModels.contains(item),
        )
        .toList(growable: false);
    if (selected.isNotEmpty) {
      return selected;
    }
    return settingsInternal.aiGateway.availableModels
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  bool get canUseAiGatewayConversation =>
      aiGatewayUrl.isNotEmpty &&
      aiGatewayApiKeyCacheInternal.trim().isNotEmpty &&
      resolvedAiGatewayModel.isNotEmpty;

  AssistantThreadConnectionState get currentAssistantConnectionState =>
      assistantConnectionStateForSession(currentSessionKeyInternal);

  AssistantThreadConnectionState assistantConnectionStateForSession(
    String sessionKey,
  ) {
    final normalizedSessionKey = normalizedSessionKeyInternal(sessionKey);
    final target = assistantExecutionTargetForSession(normalizedSessionKey);
    if (target == AssistantExecutionTarget.singleAgent ||
        target == AssistantExecutionTarget.auto) {
      final provider = singleAgentProviderForSession(normalizedSessionKey);
      final model = assistantModelForSession(normalizedSessionKey);
      final host = hostLabelInternal(settingsInternal.aiGateway.baseUrl);
      if (provider == SingleAgentProvider.auto) {
        final detail = joinConnectionPartsInternal(<String>[model, host]);
        return AssistantThreadConnectionState(
          executionTarget: target,
          status: canUseAiGatewayConversation
              ? RuntimeConnectionStatus.connected
              : RuntimeConnectionStatus.offline,
          primaryLabel: target == AssistantExecutionTarget.auto
              ? 'Auto'
              : target.label,
          detailLabel: detail.isEmpty
              ? appText('单机智能体未配置', 'Single Agent not configured')
              : target == AssistantExecutionTarget.auto
              ? '${appText('当前: ', 'Current: ')}$detail'
              : detail,
          ready: canUseAiGatewayConversation,
          pairingRequired: false,
          gatewayTokenMissing: false,
          lastError: null,
        );
      }
      final remoteAddress = gatewayAddressLabelInternal(
        settingsInternal.primaryRemoteGatewayProfile,
      );
      final remoteReady =
          connection.status == RuntimeConnectionStatus.connected &&
          connection.mode == RuntimeConnectionMode.remote;
      return AssistantThreadConnectionState(
        executionTarget: target,
        status: remoteReady
            ? RuntimeConnectionStatus.connected
            : RuntimeConnectionStatus.offline,
        primaryLabel: target == AssistantExecutionTarget.auto
            ? 'Auto'
            : target.label,
        detailLabel: remoteReady
            ? '${target == AssistantExecutionTarget.auto ? appText('当前: ', 'Current: ') : ''}${joinConnectionPartsInternal(<String>[provider.label, model])}'
            : appText(
                '${provider.label} 需要 Remote ACP（${remoteAddress.isEmpty ? 'Remote Gateway' : remoteAddress}）',
                '${provider.label} requires Remote ACP (${remoteAddress.isEmpty ? 'Remote Gateway' : remoteAddress}).',
              ),
        ready: remoteReady,
        pairingRequired: false,
        gatewayTokenMissing: false,
        lastError: null,
      );
    }
    final expectedMode = target == AssistantExecutionTarget.local
        ? RuntimeConnectionMode.local
        : RuntimeConnectionMode.remote;
    final profile = target == AssistantExecutionTarget.local
        ? settingsInternal.primaryLocalGatewayProfile
        : settingsInternal.primaryRemoteGatewayProfile;
    final matchesTarget = connection.mode == expectedMode;
    final detail = matchesTarget
        ? (connection.remoteAddress?.trim().isNotEmpty == true
              ? connection.remoteAddress!.trim()
              : gatewayAddressLabelInternal(profile))
        : gatewayAddressLabelInternal(profile);
    return AssistantThreadConnectionState(
      executionTarget: target,
      status: matchesTarget
          ? connection.status
          : RuntimeConnectionStatus.offline,
      primaryLabel:
          (matchesTarget ? connection.status : RuntimeConnectionStatus.offline)
              .label,
      detailLabel: detail.isEmpty
          ? appText('Relay 未连接', 'Relay offline')
          : detail,
      ready:
          matchesTarget &&
          connection.status == RuntimeConnectionStatus.connected,
      pairingRequired: false,
      gatewayTokenMissing: false,
      lastError: null,
    );
  }

  String get assistantConnectionStatusLabel =>
      currentAssistantConnectionState.primaryLabel;

  String get assistantConnectionTargetLabel {
    return currentAssistantConnectionState.detailLabel;
  }

  String joinConnectionPartsInternal(List<String> parts) {
    return parts
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .join(' · ');
  }

  String get conversationPersistenceSummary {
    if (usesRemoteSessionPersistence) {
      return appText(
        '当前会话会同步到远端 Session API，并在浏览器中保留一份本地缓存用于恢复。',
        'Conversation history syncs to the remote session API and keeps a browser cache for local recovery.',
      );
    }
    return appText(
      '当前会话列表会在浏览器本地保存，刷新后仍可恢复单机智能体 / Relay 的历史入口。',
      'Conversation history is stored in this browser so Single Agent and Relay entries remain available after reload.',
    );
  }

  String get currentConversationTitle =>
      titleForRecordInternal(currentRecordInternal);

  TaskThread get currentRecordInternal {
    final existing = threadRecordsInternal[currentSessionKeyInternal];
    if (existing != null) {
      return existing;
    }
    throw StateError(
      'Current session $currentSessionKeyInternal has no TaskThread record.',
    );
  }
}
