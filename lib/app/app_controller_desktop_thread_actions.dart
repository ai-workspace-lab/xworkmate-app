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
import '../runtime/go_task_service_client.dart';
import '../runtime/mode_switcher.dart';
import '../runtime/agent_registry.dart';
import '../runtime/multi_agent_orchestrator.dart';
import '../runtime/platform_environment.dart';
import '../runtime/skill_directory_access.dart';
import 'app_controller_openclaw_task_queue.dart';
import 'app_controller_desktop_core.dart';
import 'app_controller_desktop_navigation.dart';
import 'app_controller_desktop_gateway.dart';
import 'app_controller_desktop_settings.dart';
import 'app_controller_desktop_external_acp_routing.dart';
import 'app_controller_desktop_thread_binding.dart';
import 'app_controller_desktop_thread_sessions.dart';
import 'app_controller_desktop_workspace_execution.dart';
import 'app_controller_desktop_settings_runtime.dart';
import 'app_controller_desktop_thread_storage.dart';
import 'app_controller_desktop_skill_permissions.dart';
import 'app_controller_desktop_runtime_helpers.dart';

// ignore_for_file: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
extension AppControllerDesktopThreadActions on AppController {
  GatewayChatMessage assistantErrorMessageInternal(String text) {
    return GatewayChatMessage(
      id: nextLocalMessageIdInternal(),
      role: 'assistant',
      text: text,
      timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
      toolCallId: null,
      toolName: null,
      stopReason: null,
      pending: false,
      error: true,
    );
  }

  bool assistantSessionHasPendingRun(String sessionKey) {
    final normalized = normalizedAssistantSessionKeyInternal(sessionKey);
    return aiGatewayPendingSessionKeysInternal.contains(normalized) ||
        (multiAgentRunPendingInternal &&
            matchesSessionKey(
              normalized,
              sessionsControllerInternal.currentSessionKey,
            ));
  }

  Future<void> connectSavedGateway() async {
    final target = currentAssistantExecutionTarget;
    await AppControllerDesktopGateway(this).connectProfileInternal(
      gatewayProfileForAssistantExecutionTargetInternal(target),
      profileIndex: gatewayProfileIndexForExecutionTargetInternal(target),
    );
  }

  Future<void> clearStoredGatewayToken({int? profileIndex}) async {
    await settingsControllerInternal.clearGatewaySecrets(
      profileIndex: profileIndex,
      token: true,
    );
  }

  Future<void> refreshGatewayHealth() async {
    if (!runtimeInternal.isConnected) {
      return;
    }
    try {
      await runtimeInternal.health();
    } catch (_) {}
    try {
      await runtimeInternal.status();
    } catch (_) {}
    notifyListeners();
  }

  Future<void> refreshDevices({bool quiet = false}) async {
    await devicesControllerInternal.refresh(quiet: quiet);
  }

  Future<void> approveDevicePairing(String requestId) async {
    await devicesControllerInternal.approve(requestId);
    await settingsControllerInternal.refreshDerivedState();
  }

  Future<void> rejectDevicePairing(String requestId) async {
    await devicesControllerInternal.reject(requestId);
  }

  Future<void> removePairedDevice(String deviceId) async {
    await devicesControllerInternal.remove(deviceId);
    await settingsControllerInternal.refreshDerivedState();
  }

  Future<String?> rotateDeviceRoleToken({
    required String deviceId,
    required String role,
    List<String> scopes = const <String>[],
  }) async {
    final token = await devicesControllerInternal.rotateToken(
      deviceId: deviceId,
      role: role,
      scopes: scopes,
    );
    await settingsControllerInternal.refreshDerivedState();
    return token;
  }

  Future<void> revokeDeviceRoleToken({
    required String deviceId,
    required String role,
  }) async {
    await devicesControllerInternal.revokeToken(deviceId: deviceId, role: role);
    await settingsControllerInternal.refreshDerivedState();
  }

  Future<void> refreshAgents() async {
    await agentsControllerInternal.refresh();
    sessionsControllerInternal.configure(
      mainSessionKey: runtimeInternal.snapshot.mainSessionKey ?? 'main',
      selectedAgentId: agentsControllerInternal.selectedAgentId,
      defaultAgentId: '',
    );
    recomputeTasksInternal();
  }

  Future<void> selectAgent(String? agentId) async {
    agentsControllerInternal.selectAgent(agentId);
    final target = currentAssistantExecutionTarget;
    final nextProfile = gatewayProfileForAssistantExecutionTargetInternal(
      target,
    ).copyWith(selectedAgentId: agentsControllerInternal.selectedAgentId);
    await AppControllerDesktopSettings(this).saveSettings(
      settings.copyWithGatewayProfileAt(
        gatewayProfileIndexForExecutionTargetInternal(target),
        nextProfile,
      ),
      refreshAfterSave: false,
    );
    sessionsControllerInternal.configure(
      mainSessionKey: runtimeInternal.snapshot.mainSessionKey ?? 'main',
      selectedAgentId: agentsControllerInternal.selectedAgentId,
      defaultAgentId: '',
    );
    await chatControllerInternal.loadSession(
      sessionsControllerInternal.currentSessionKey,
    );
    await skillsControllerInternal.refresh(
      agentId: agentsControllerInternal.selectedAgentId.isEmpty
          ? null
          : agentsControllerInternal.selectedAgentId,
    );
    recomputeTasksInternal();
  }

  Future<void> refreshSessions() async {
    sessionsControllerInternal.configure(
      mainSessionKey: runtimeInternal.snapshot.mainSessionKey ?? 'main',
      selectedAgentId: agentsControllerInternal.selectedAgentId,
      defaultAgentId: '',
    );
    await sessionsControllerInternal.refresh();
    await chatControllerInternal.loadSession(
      sessionsControllerInternal.currentSessionKey,
    );
    recomputeTasksInternal();
  }

  Future<void> switchSession(String sessionKey) async {
    final previousSessionKey = normalizedAssistantSessionKeyInternal(
      sessionsControllerInternal.currentSessionKey,
    );
    final nextSessionKey = normalizedAssistantSessionKeyInternal(sessionKey);
    final nextTarget = assistantExecutionTargetForSession(nextSessionKey);
    final nextViewMode = assistantMessageViewModeForSession(nextSessionKey);

    preserveGatewayHistoryForSessionInternal(previousSessionKey);

    await setCurrentAssistantSessionKeyInternal(nextSessionKey);
    upsertTaskThreadInternal(
      nextSessionKey,
      executionTarget: nextTarget,
      messageViewMode: nextViewMode,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    await ensureDesktopTaskThreadBindingInternal(
      nextSessionKey,
      executionTarget: nextTarget,
    );
    await applyAssistantExecutionTargetInternal(
      nextTarget,
      sessionKey: nextSessionKey,
      persistDefaultSelection: false,
      preserveGatewayHistoryForSelectedThread: false,
    );
    recomputeTasksInternal();
  }

  Future<void> sendChatMessage(
    String message, {
    String thinking = 'off',
    List<GatewayChatAttachmentPayload> attachments =
        const <GatewayChatAttachmentPayload>[],
    List<CollaborationAttachment> localAttachments =
        const <CollaborationAttachment>[],
    List<String> selectedSkillLabels = const <String>[],
  }) async {
    final sessionKey = normalizedAssistantSessionKeyInternal(
      sessionsControllerInternal.currentSessionKey,
    );
    final currentTarget = assistantExecutionTargetForSession(sessionKey);
    var connectionState = assistantConnectionStateForSession(sessionKey);
    if (!connectionState.connected &&
        isBridgeAcpRuntimeConfiguredInternal() &&
        bridgeCapabilityRefreshNeededForAssistantTargetInternal(
          currentTarget,
        )) {
      try {
        await refreshAcpCapabilitiesInternal(forceRefresh: true);
        connectionState = assistantConnectionStateForSession(sessionKey);
      } catch (_) {
        // Fallback to existing connection state if refresh fails.
      }
    }
    if (!connectionState.connected) {
      final error = StateError(connectionState.detailLabel);
      appendAssistantThreadMessageInternal(
        sessionKey,
        assistantErrorMessageInternal(error.message),
      );
      await flushAssistantThreadPersistenceInternal();
      recomputeTasksInternal();
      notifyIfActiveInternal();
      throw error;
    }
    await ensureDesktopTaskThreadBindingInternal(
      sessionKey,
      executionTarget: currentTarget,
    );
    final workingDirectory =
        assistantWorkingDirectoryForSessionInternal(sessionKey)?.trim() ?? '';
    final remoteWorkingDirectoryHint =
        assistantRemoteWorkingDirectoryHintForSessionInternal(
          sessionKey,
        )?.trim() ??
        '';
    if (workingDirectory.isEmpty) {
      final error = StateError(
        appText(
          '当前任务线程缺少可运行的 workingDirectory，无法执行。',
          'This task thread has no runnable workingDirectory yet.',
        ),
      );
      appendAssistantThreadMessageInternal(
        sessionKey,
        assistantErrorMessageInternal(error.message),
      );
      await flushAssistantThreadPersistenceInternal();
      recomputeTasksInternal();
      throw error;
    }
    if (providerCatalogForExecutionTarget(currentTarget).isEmpty) {
      try {
        await refreshSingleAgentCapabilitiesInternal(forceRefresh: true);
      } catch (_) {
        // Keep the local guard focused on the post-refresh catalog state.
      }
      if (providerCatalogForExecutionTarget(currentTarget).isEmpty) {
        upsertTaskThreadInternal(
          sessionKey,
          selectedProvider: SingleAgentProvider.unspecified,
          selectedProviderSource: ThreadSelectionSource.inherited,
          latestResolvedProviderId: '',
          updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
        );
        final error = StateError(
          currentTarget.isGateway
              ? appText(
                  'Gateway ACP 未报告可用的 gateway provider，当前无法发送。',
                  'Gateway ACP did not report a usable gateway provider, so this Gateway task cannot run yet.',
                )
              : appText(
                  'Gateway ACP 未报告可用的 agent provider，当前无法发送。',
                  'Gateway ACP did not report a usable agent provider, so this Agent task cannot run yet.',
                ),
        );
        appendAssistantThreadMessageInternal(
          sessionKey,
          assistantErrorMessageInternal(error.message),
        );
        await flushAssistantThreadPersistenceInternal();
        recomputeTasksInternal();
        notifyIfActiveInternal();
        throw error;
      }
    }
    final provider = assistantProviderForSession(sessionKey);
    final model = assistantModelForSession(sessionKey);
    final routing = buildExternalAcpRoutingForSessionInternal(sessionKey);
    final dispatch = await codeAgentNodeOrchestratorInternal
        .buildGatewayDispatch(
          buildCodeAgentNodeStateInternal(executionTarget: currentTarget),
        );
    final capturedSelectedSkillLabels = List<String>.unmodifiable(
      selectedSkillLabels,
    );
    final capturedAttachments = List<GatewayChatAttachmentPayload>.unmodifiable(
      attachments,
    );
    final capturedLocalAttachments = List<CollaborationAttachment>.unmodifiable(
      localAttachments,
    );
    if (usesOpenClawGatewayQueueInternal(currentTarget, provider)) {
      await enqueueOpenClawGatewayTurnInternal(
        OpenClawGatewayQueuedTurnInternal(
          queueId:
              'openclaw-${DateTime.now().microsecondsSinceEpoch}-$localMessageCounterInternal',
          sessionKey: sessionKey,
          target: currentTarget,
          provider: provider,
          message: message,
          thinking: thinking,
          selectedSkillLabels: capturedSelectedSkillLabels,
          attachments: capturedAttachments,
          localAttachments: capturedLocalAttachments,
          workingDirectory: workingDirectory,
          remoteWorkingDirectoryHint: remoteWorkingDirectoryHint,
          model: model,
          routing: routing,
          agentId: dispatch.agentId ?? '',
          metadata: Map<String, dynamic>.unmodifiable(dispatch.metadata),
        ),
      );
      return;
    }
    await enqueueThreadTurnInternal<void>(
      sessionKey,
      () => runGatewayChatTurnInternal(
        sessionKey: sessionKey,
        target: currentTarget,
        provider: provider,
        message: message,
        thinking: thinking,
        selectedSkillLabels: capturedSelectedSkillLabels,
        attachments: capturedAttachments,
        localAttachments: capturedLocalAttachments,
        workingDirectory: workingDirectory,
        remoteWorkingDirectoryHint: remoteWorkingDirectoryHint,
        model: model,
        routing: routing,
        agentId: dispatch.agentId ?? '',
        metadata: Map<String, dynamic>.unmodifiable(dispatch.metadata),
      ),
    );
    recomputeTasksInternal();
  }

  Future<void> runGatewayChatTurnInternal({
    required String sessionKey,
    required AssistantExecutionTarget target,
    required SingleAgentProvider provider,
    required String message,
    required String thinking,
    required List<String> selectedSkillLabels,
    required List<GatewayChatAttachmentPayload> attachments,
    required List<CollaborationAttachment> localAttachments,
    required String workingDirectory,
    required String remoteWorkingDirectoryHint,
    required String model,
    required ExternalCodeAgentAcpRoutingConfig routing,
    required String agentId,
    required Map<String, dynamic> metadata,
  }) async {
    final resumeSession = shouldResumeGatewaySessionForNextSendInternal(
      sessionKey,
    );
    appendGatewayUserTurnInternal(sessionKey, message);
    markGatewayChatRunInternal(sessionKey);
    try {
      final result = await goTaskServiceClientInternal.executeTask(
        GoTaskServiceRequest(
          sessionId: sessionKey,
          threadId: sessionKey,
          target: target,
          provider: provider,
          prompt: message,
          workingDirectory: workingDirectory,
          remoteWorkingDirectoryHint: remoteWorkingDirectoryHint,
          model: model,
          thinking: thinking,
          selectedSkills: selectedSkillLabels,
          inlineAttachments: attachments,
          localAttachments: localAttachments,
          agentId: agentId,
          metadata: metadata,
          routing: routing,
          routingHint: 'gateway',
          resumeSession: resumeSession,
        ),
        onUpdate: (update) {
          if (update.isDelta) {
            appendAiGatewayStreamingTextInternal(sessionKey, update.text);
            notifyIfActiveInternal();
          }
        },
      );
      if (!aiGatewayPendingSessionKeysInternal.contains(sessionKey)) {
        clearAiGatewayStreamingTextInternal(sessionKey);
        return;
      }
      await applyGatewayChatResultInternal(
        sessionKey: sessionKey,
        target: target,
        result: result,
      );
    } catch (error) {
      if (!aiGatewayPendingSessionKeysInternal.contains(sessionKey) &&
          taskThreadForSessionInternal(
                sessionKey,
              )?.lifecycleState.lastResultCode ==
              'aborted') {
        clearAiGatewayStreamingTextInternal(sessionKey);
        return;
      }
      applyGatewayChatFailureInternal(
        sessionKey: sessionKey,
        target: target,
        error: error,
      );
    } finally {
      aiGatewayPendingSessionKeysInternal.remove(sessionKey);
      clearAiGatewayStreamingTextInternal(sessionKey);
      recomputeTasksInternal();
      notifyIfActiveInternal();
    }
  }

  bool usesOpenClawGatewayQueueInternal(
    AssistantExecutionTarget target,
    SingleAgentProvider provider,
  ) {
    return target.isGateway &&
        provider.providerId == kCanonicalGatewayProviderId;
  }

  Future<void> enqueueOpenClawGatewayTurnInternal(
    OpenClawGatewayQueuedTurnInternal turn,
  ) async {
    if (openClawGatewayActiveTasksInternal >=
            openClawGatewayMaxActiveTasksInternal &&
        openClawGatewayQueuedTurnsInternal.length >=
            openClawGatewayMaxQueuedTasksInternal) {
      final error = StateError(
        appText(
          'OpenClaw 任务队列已满，请等待当前任务完成后重试。',
          'OpenClaw task queue is full. Wait for the current tasks to finish and try again.',
        ),
      );
      await failOpenClawGatewayQueuedTurnInternal(turn.sessionKey, error);
      throw error;
    }

    openClawGatewayQueuedTurnsInternal.add(turn);
    openClawGatewayQueuedTurnsBySessionInternal
        .putIfAbsent(
          turn.sessionKey,
          () => <OpenClawGatewayQueuedTurnInternal>[],
        )
        .add(turn);
    markOpenClawGatewayQueuedTurnInternal(turn.sessionKey);
    drainOpenClawGatewayQueueInternal();
    await turn.completer.future;
  }

  void markOpenClawGatewayQueuedTurnInternal(String sessionKey) {
    upsertTaskThreadInternal(
      sessionKey,
      lifecycleStatus: 'queued',
      lastResultCode: 'queued',
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    recomputeTasksInternal();
    notifyIfActiveInternal();
  }

  Future<void> failOpenClawGatewayQueuedTurnInternal(
    String sessionKey,
    StateError error,
  ) async {
    upsertTaskThreadInternal(
      sessionKey,
      lifecycleStatus: 'ready',
      lastRunAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
      lastResultCode: 'OPENCLAW_GATEWAY_QUEUE_FULL',
      lastArtifactSyncAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
      lastArtifactSyncStatus: 'failed',
      lastTaskArtifactRelativePaths: const <String>[],
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    appendLocalSessionMessageInternal(
      sessionKey,
      assistantErrorMessageInternal(error.message),
      persistInThreadContext: true,
    );
    await flushAssistantThreadPersistenceInternal();
    recomputeTasksInternal();
    notifyIfActiveInternal();
  }

  bool abortQueuedOpenClawGatewayTurnInternal(String sessionKey) {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    final queuedForSession =
        openClawGatewayQueuedTurnsBySessionInternal[normalizedSessionKey];
    if (queuedForSession == null || queuedForSession.isEmpty) {
      return false;
    }
    final turn = queuedForSession.removeAt(0);
    if (queuedForSession.isEmpty) {
      openClawGatewayQueuedTurnsBySessionInternal.remove(normalizedSessionKey);
    }
    openClawGatewayQueuedTurnsInternal.remove(turn);
    turn.cancelled = true;
    clearAiGatewayStreamingTextInternal(normalizedSessionKey);
    upsertTaskThreadInternal(
      normalizedSessionKey,
      lifecycleStatus: 'ready',
      lastRunAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
      lastResultCode: 'aborted',
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    if (!turn.completer.isCompleted) {
      turn.completer.complete();
    }
    recomputeTasksInternal();
    notifyIfActiveInternal();
    drainOpenClawGatewayQueueInternal();
    return true;
  }

  void drainOpenClawGatewayQueueInternal() {
    while (openClawGatewayActiveTasksInternal <
            openClawGatewayMaxActiveTasksInternal &&
        openClawGatewayQueuedTurnsInternal.isNotEmpty) {
      final turn = openClawGatewayQueuedTurnsInternal.removeAt(0);
      final queuedForSession =
          openClawGatewayQueuedTurnsBySessionInternal[turn.sessionKey];
      queuedForSession?.remove(turn);
      if (queuedForSession != null && queuedForSession.isEmpty) {
        openClawGatewayQueuedTurnsBySessionInternal.remove(turn.sessionKey);
      }
      if (turn.cancelled) {
        if (!turn.completer.isCompleted) {
          turn.completer.complete();
        }
        continue;
      }
      turn.started = true;
      openClawGatewayActiveTasksInternal += 1;
      unawaited(runOpenClawGatewayQueuedTurnInternal(turn));
    }
  }

  Future<void> runOpenClawGatewayQueuedTurnInternal(
    OpenClawGatewayQueuedTurnInternal turn,
  ) async {
    try {
      await enqueueThreadTurnInternal<void>(
        turn.sessionKey,
        () => runGatewayChatTurnInternal(
          sessionKey: turn.sessionKey,
          target: turn.target,
          provider: turn.provider,
          message: turn.message,
          thinking: turn.thinking,
          selectedSkillLabels: turn.selectedSkillLabels,
          attachments: turn.attachments,
          localAttachments: turn.localAttachments,
          workingDirectory: turn.workingDirectory,
          remoteWorkingDirectoryHint: turn.remoteWorkingDirectoryHint,
          model: turn.model,
          routing: turn.routing,
          agentId: turn.agentId,
          metadata: turn.metadata,
        ),
      );
      if (!turn.completer.isCompleted) {
        turn.completer.complete();
      }
    } catch (error, stackTrace) {
      if (!turn.completer.isCompleted) {
        turn.completer.completeError(error, stackTrace);
      }
    } finally {
      openClawGatewayActiveTasksInternal -= 1;
      drainOpenClawGatewayQueueInternal();
    }
  }

  void appendGatewayUserTurnInternal(String sessionKey, String message) {
    final userText = message.trim().isEmpty ? 'See attached.' : message.trim();
    appendLocalSessionMessageInternal(
      sessionKey,
      GatewayChatMessage(
        id: nextLocalMessageIdInternal(),
        role: 'user',
        text: userText,
        timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
        toolCallId: null,
        toolName: null,
        stopReason: null,
        pending: false,
        error: false,
      ),
      persistInThreadContext: true,
    );
  }

  void markGatewayChatRunInternal(String sessionKey) {
    aiGatewayPendingSessionKeysInternal.add(sessionKey);
    upsertTaskThreadInternal(
      sessionKey,
      lifecycleStatus: 'running',
      lastRunAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
      lastResultCode: 'running',
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    recomputeTasksInternal();
    notifyIfActiveInternal();
  }

  Future<void> applyGatewayChatResultInternal({
    required String sessionKey,
    required AssistantExecutionTarget target,
    required GoTaskServiceResult result,
  }) async {
    clearAiGatewayStreamingTextInternal(sessionKey);
    upsertTaskThreadInternal(
      sessionKey,
      gatewayEntryState: goTaskServiceGatewayEntryState(
        requestedTarget: target,
        result: result,
      ),
      latestResolvedRuntimeModel: result.resolvedModel.trim(),
      lastRemoteWorkingDirectory:
          result.remoteWorkingDirectory.trim().isNotEmpty
          ? result.remoteWorkingDirectory.trim()
          : null,
      lastRemoteWorkspaceRefKind: result.remoteWorkspaceRefKind,
      lifecycleStatus: 'ready',
      lastRunAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
      lastResultCode: result.success ? 'success' : 'error',
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    if (isOpenClawNoExportedArtifactsGuardResultInternal(result)) {
      await persistGoTaskArtifactsForSessionInternal(sessionKey, result);
      return;
    }
    if (!result.success) {
      appendLocalSessionMessageInternal(
        sessionKey,
        assistantErrorMessageInternal(
          result.errorMessage.trim().isEmpty
              ? appText(
                  'GoTaskService 执行失败。',
                  'GoTaskService execution failed.',
                )
              : gatewayExecutionErrorLabelInternal(
                  result.errorMessage,
                  target: target,
                ),
        ),
        persistInThreadContext: true,
      );
      return;
    }
    final assistantText = result.message.trim();
    if (assistantText.isEmpty) {
      appendLocalSessionMessageInternal(
        sessionKey,
        assistantErrorMessageInternal(
          appText(
            'GoTaskService 没有返回可显示的输出。',
            'GoTaskService returned no displayable output.',
          ),
        ),
        persistInThreadContext: true,
      );
      return;
    }
    appendLocalSessionMessageInternal(
      sessionKey,
      GatewayChatMessage(
        id: nextLocalMessageIdInternal(),
        role: 'assistant',
        text: assistantText,
        timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
        toolCallId: null,
        toolName: null,
        stopReason: null,
        pending: false,
        error: false,
      ),
      persistInThreadContext: true,
    );
    recomputeTasksInternal();
    notifyIfActiveInternal();
    await persistGoTaskArtifactsForSessionInternal(sessionKey, result);
  }

  void applyGatewayChatFailureInternal({
    required String sessionKey,
    required AssistantExecutionTarget target,
    required Object error,
  }) {
    clearAiGatewayStreamingTextInternal(sessionKey);
    final unconfirmedConnectCode = unconfirmedAcpHttpConnectCodeInternal(error);
    final interruptedTransportCode = interruptedAcpHttpTransportCodeInternal(
      error,
    );
    if (unconfirmedConnectCode != null) {
      upsertTaskThreadInternal(
        sessionKey,
        lifecycleStatus: 'ready',
        lastRunAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
        lastResultCode: unconfirmedConnectCode,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
      );
      appendLocalSessionMessageInternal(
        sessionKey,
        assistantErrorMessageInternal(
          gatewayExecutionErrorLabelInternal(error, target: target),
        ),
        persistInThreadContext: true,
      );
      return;
    }
    upsertTaskThreadInternal(
      sessionKey,
      lifecycleStatus: 'ready',
      lastRunAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
      lastResultCode: interruptedTransportCode ?? 'error',
      lastArtifactSyncAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
      lastArtifactSyncStatus: 'failed',
      lastTaskArtifactRelativePaths: const <String>[],
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    appendLocalSessionMessageInternal(
      sessionKey,
      assistantErrorMessageInternal(
        gatewayExecutionErrorLabelInternal(error, target: target),
      ),
      persistInThreadContext: true,
    );
  }

  bool hasCommittedUserTurnForGatewaySessionInternal(String sessionKey) {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    final messages = <GatewayChatMessage>[
      ...?assistantThreadRecordsInternal[normalizedSessionKey]?.messages,
      ...?assistantThreadMessagesInternal[normalizedSessionKey],
      ...?localSessionMessagesInternal[normalizedSessionKey],
    ];
    return messages.any((message) {
      final role = message.role.trim().toLowerCase();
      return role == 'user' && !message.pending;
    });
  }

  bool shouldResumeGatewaySessionForNextSendInternal(String sessionKey) {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    if (!hasCommittedUserTurnForGatewaySessionInternal(normalizedSessionKey)) {
      return false;
    }
    final lastResultCode = taskThreadForSessionInternal(
      normalizedSessionKey,
    )?.lifecycleState.lastResultCode?.trim().toUpperCase();
    return lastResultCode == 'SUCCESS';
  }

  Future<void> abortRun() async {
    if (multiAgentRunPendingInternal) {
      final sessionKey = normalizedAssistantSessionKeyInternal(
        sessionsControllerInternal.currentSessionKey,
      );
      try {
        await goTaskServiceClientInternal.cancelTask(
          route: GoTaskServiceRoute.externalAcpMulti,
          target: assistantExecutionTargetForSession(sessionKey),
          sessionId: sessionKey,
          threadId: sessionKey,
        );
      } catch (_) {
        // Best effort cancellation only.
      }
      multiAgentRunPendingInternal = false;
      upsertTaskThreadInternal(
        sessionKey,
        lifecycleStatus: 'ready',
        lastRunAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
        lastResultCode: 'aborted',
        updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
      );
      recomputeTasksInternal();
      notifyIfActiveInternal();
      return;
    }
    final sessionKey = normalizedAssistantSessionKeyInternal(
      sessionsControllerInternal.currentSessionKey,
    );
    if (abortQueuedOpenClawGatewayTurnInternal(sessionKey)) {
      return;
    }
    if (aiGatewayPendingSessionKeysInternal.contains(sessionKey)) {
      await goTaskServiceClientInternal.cancelTask(
        route: GoTaskServiceRoute.externalAcpSingle,
        target: assistantExecutionTargetForSession(sessionKey),
        sessionId: sessionKey,
        threadId: sessionKey,
      );
      aiGatewayPendingSessionKeysInternal.remove(sessionKey);
      clearAiGatewayStreamingTextInternal(sessionKey);
      upsertTaskThreadInternal(
        sessionKey,
        lifecycleStatus: 'ready',
        lastRunAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
        lastResultCode: 'aborted',
        updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
      );
      recomputeTasksInternal();
      notifyIfActiveInternal();
      return;
    }
  }

  Future<void> prepareForExit() async {
    try {
      await abortRun();
    } catch (_) {
      // Best effort only. Native termination still proceeds.
    }
    await flushAssistantThreadPersistenceInternal();
  }

  Map<String, dynamic> desktopStatusSnapshot() {
    final connectionState = currentAssistantConnectionState;
    final pausedTasks = tasksControllerInternal.scheduled
        .where((item) => item.status == 'Disabled')
        .length;
    final timedOutTasks = tasksControllerInternal.failed
        .where(looksLikeTimedOutTaskInternal)
        .length;
    final failedTasks = tasksControllerInternal.failed.length;
    final queuedTasks = tasksControllerInternal.queue.length;
    final runningTasks = tasksControllerInternal.running.length;
    final scheduledTasks = tasksControllerInternal.scheduled.length;
    final badgeCount = runningTasks + pausedTasks + timedOutTasks;
    return <String, dynamic>{
      'connectionStatus': desktopConnectionStatusValueInternal(
        connectionState.status,
      ),
      'connectionLabel': connectionState.primaryLabel,
      'runningTasks': runningTasks,
      'pausedTasks': pausedTasks,
      'timedOutTasks': timedOutTasks,
      'queuedTasks': queuedTasks,
      'scheduledTasks': scheduledTasks,
      'failedTasks': failedTasks,
      'totalTasks': tasksControllerInternal.totalCount,
      'badgeCount': badgeCount > 0 ? badgeCount : runningTasks + queuedTasks,
    };
  }

  bool looksLikeTimedOutTaskInternal(DerivedTaskItem item) {
    final haystack = '${item.status} ${item.title} ${item.summary}'
        .toLowerCase();
    return haystack.contains('timed out') ||
        haystack.contains('timeout') ||
        haystack.contains('超时');
  }

  String desktopConnectionStatusValueInternal(RuntimeConnectionStatus status) {
    switch (status) {
      case RuntimeConnectionStatus.connected:
        return 'connected';
      case RuntimeConnectionStatus.connecting:
        return 'connecting';
      case RuntimeConnectionStatus.error:
        return 'error';
      case RuntimeConnectionStatus.offline:
        return 'disconnected';
    }
  }
}
