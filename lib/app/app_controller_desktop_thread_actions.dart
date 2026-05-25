// ignore_for_file: unused_import, unnecessary_import

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
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
        openClawGatewayQueuedTurnsBySessionInternal[normalized]?.any(
              (turn) => !turn.cancelled,
            ) ==
            true ||
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
      selectedAgentId: agentsControllerInternal.selectedAgentId,
      defaultAgentId: '',
    );
    final sessionKey = normalizedAssistantSessionKeyInternal(currentSessionKey);
    if (isAppOwnedAssistantSessionKeyInternal(sessionKey)) {
      await chatControllerInternal.loadSession(sessionKey);
    }
    await skillsControllerInternal.refresh(
      agentId: agentsControllerInternal.selectedAgentId.isEmpty
          ? null
          : agentsControllerInternal.selectedAgentId,
    );
    recomputeTasksInternal();
  }

  Future<void> refreshSessions() async {
    sessionsControllerInternal.configure(
      selectedAgentId: agentsControllerInternal.selectedAgentId,
      defaultAgentId: '',
    );
    await sessionsControllerInternal.refresh();
    await ensureActiveAssistantThreadInternal();
    final selectedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionsControllerInternal.currentSessionKey,
    );
    if (isAppOwnedAssistantSessionKeyInternal(selectedSessionKey)) {
      await chatControllerInternal.loadSession(selectedSessionKey);
    }
    recomputeTasksInternal();
  }

  Future<void> switchSession(String sessionKey) async {
    var nextSessionKey = normalizedAssistantSessionKeyInternal(sessionKey);
    if (!isAppOwnedAssistantSessionKeyInternal(nextSessionKey)) {
      nextSessionKey = createAssistantDraftSessionKeyInternal();
    }
    final nextTarget = assistantExecutionTargetForSession(nextSessionKey);
    final nextViewMode = assistantMessageViewModeForSession(nextSessionKey);

    await setCurrentAssistantSessionKeyInternal(nextSessionKey);
    upsertTaskThreadInternal(
      nextSessionKey,
      executionTarget: nextTarget,
      messageViewMode: nextViewMode,
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
    if (runtimeInternal.isConnected) {
      await chatControllerInternal.loadSession(nextSessionKey);
    } else {
      chatControllerInternal.resetSession(nextSessionKey);
    }
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
    var sessionKey = normalizedAssistantSessionKeyInternal(
      sessionsControllerInternal.currentSessionKey,
    );
    if (!isAppOwnedAssistantSessionKeyInternal(sessionKey)) {
      await ensureActiveAssistantThreadInternal();
      sessionKey = normalizedAssistantSessionKeyInternal(
        sessionsControllerInternal.currentSessionKey,
      );
    }
    final currentTarget = assistantExecutionTargetForSession(sessionKey);
    final resumeSessionHint = shouldResumeGatewaySessionForNextSendInternal(
      sessionKey,
    );
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
    final model = currentTarget.isGateway
        ? ''
        : assistantModelForSession(sessionKey);
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
          resumeSessionHint: resumeSessionHint,
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
        resumeSessionHint: resumeSessionHint,
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
    required bool resumeSessionHint,
    bool appendUserTurn = true,
  }) async {
    final resumeSession =
        resumeSessionHint ||
        (appendUserTurn &&
            shouldResumeGatewaySessionForNextSendInternal(sessionKey));
    final messageWithSkills = messageWithSelectedSkillsContextInternal(
      message: message,
      selectedSkillLabels: selectedSkillLabels,
    );
    final taskPrompt = taskWorkspaceContextPromptInternal(
      sessionKey: sessionKey,
      userPrompt: messageWithSkills,
      workingDirectory: workingDirectory,
      remoteWorkingDirectoryHint: remoteWorkingDirectoryHint,
    );
    if (appendUserTurn) {
      appendGatewayUserTurnInternal(sessionKey, message);
    }
    markGatewayChatRunInternal(sessionKey);
    try {
      final result = await goTaskServiceClientInternal.executeTask(
        GoTaskServiceRequest(
          sessionId: sessionKey,
          threadId: sessionKey,
          target: target,
          provider: provider,
          prompt: taskPrompt,
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

  String messageWithSelectedSkillsContextInternal({
    required String message,
    required List<String> selectedSkillLabels,
  }) {
    final labels = selectedSkillLabels
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (labels.isEmpty || message.contains('Preferred skills:')) {
      return message;
    }
    return 'Preferred skills:\n${labels.map((name) => '- $name').join('\n')}\n\n$message';
  }

  String taskWorkspaceContextPromptInternal({
    required String sessionKey,
    required String userPrompt,
    required String workingDirectory,
    required String remoteWorkingDirectoryHint,
  }) {
    final requestText = userPrompt.trim().isEmpty
        ? 'See attached.'
        : userPrompt.trim();
    final buffer = StringBuffer()
      ..writeln('TaskThread workspace context:')
      ..writeln('- sessionKey: $sessionKey')
      ..writeln('- localWorkspace: ${workingDirectory.trim()}');
    final remoteHint = remoteWorkingDirectoryHint.trim();
    if (remoteHint.isNotEmpty) {
      buffer.writeln('- remoteWorkspaceHint: $remoteHint');
    }
    buffer.writeln(
      '- currentTaskWorkspace: ${remoteHint.isNotEmpty ? remoteHint : workingDirectory.trim()}',
    );
    buffer
      ..writeln()
      ..writeln('Workspace isolation rules:')
      ..writeln(
        '1. Treat currentTaskWorkspace as the only writable workspace for this TaskThread execution.',
      )
      ..writeln(
        '2. Create, modify, and export task files inside currentTaskWorkspace or its task artifact scope.',
      )
      ..writeln(
        '3. Do not use arbitrary global directories, OpenClaw media cache, Downloads, Desktop, or /tmp as final deliverable locations.',
      )
      ..writeln(
        '4. If a tool creates output outside currentTaskWorkspace, copy or export the final deliverables into currentTaskWorkspace before claiming completion.',
      )
      ..writeln(
        '5. When reporting files, prefer paths inside currentTaskWorkspace or paths relative to currentTaskWorkspace.',
      )
      ..writeln(
        '6. The app syncs final artifacts from currentTaskWorkspace back into localWorkspace.',
      )
      ..writeln()
      ..writeln('User request:')
      ..write(requestText);
    return buffer.toString();
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
    appendGatewayUserTurnInternal(turn.sessionKey, turn.message);
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
  }

  void markOpenClawGatewayQueuedTurnInternal(String sessionKey) {
    final queuedAtMs = DateTime.now().millisecondsSinceEpoch.toDouble();
    upsertTaskThreadInternal(
      sessionKey,
      lifecycleStatus: 'queued',
      lastResultCode: 'queued',
      lastArtifactSyncAtMs: queuedAtMs,
      lastArtifactSyncStatus: 'queued',
      lastTaskArtifactRelativePaths: const <String>[],
      updatedAtMs: queuedAtMs,
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
      lastRemoteWorkingDirectory: '',
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
    if (!removeQueuedOpenClawGatewayTurnsForSessionInternal(
      normalizedSessionKey,
    )) {
      return false;
    }
    markOpenClawGatewayTurnAbortedInternal(normalizedSessionKey);
    drainOpenClawGatewayQueueInternal();
    return true;
  }

  bool removeQueuedOpenClawGatewayTurnsForSessionInternal(String sessionKey) {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    final queuedForSession = openClawGatewayQueuedTurnsBySessionInternal.remove(
      normalizedSessionKey,
    );
    if (queuedForSession == null || queuedForSession.isEmpty) {
      return false;
    }
    for (final turn in queuedForSession) {
      turn.cancelled = true;
      openClawGatewayQueuedTurnsInternal.remove(turn);
    }
    return true;
  }

  void markOpenClawGatewayTurnAbortedInternal(String sessionKey) {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    clearAiGatewayStreamingTextInternal(normalizedSessionKey);
    aiGatewayPendingSessionKeysInternal.remove(normalizedSessionKey);
    final nowMs = DateTime.now().millisecondsSinceEpoch.toDouble();
    upsertTaskThreadInternal(
      normalizedSessionKey,
      lifecycleStatus: 'ready',
      lastRunAtMs: nowMs,
      lastResultCode: 'aborted',
      lastRemoteWorkingDirectory: '',
      lastArtifactSyncAtMs: nowMs,
      lastArtifactSyncStatus: 'failed',
      lastTaskArtifactRelativePaths: const <String>[],
      updatedAtMs: nowMs,
    );
    recomputeTasksInternal();
    notifyIfActiveInternal();
  }

  void removeOpenClawGatewayQueuedTurnIndexInternal(
    OpenClawGatewayQueuedTurnInternal turn,
  ) {
    final queuedForSession =
        openClawGatewayQueuedTurnsBySessionInternal[turn.sessionKey];
    queuedForSession?.remove(turn);
    if (queuedForSession != null && queuedForSession.isEmpty) {
      openClawGatewayQueuedTurnsBySessionInternal.remove(turn.sessionKey);
    }
  }

  void drainOpenClawGatewayQueueInternal() {
    while (openClawGatewayActiveTasksInternal <
            openClawGatewayMaxActiveTasksInternal &&
        openClawGatewayQueuedTurnsInternal.isNotEmpty) {
      final turn = openClawGatewayQueuedTurnsInternal.removeAt(0);
      removeOpenClawGatewayQueuedTurnIndexInternal(turn);
      if (turn.cancelled) {
        continue;
      }
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
          resumeSessionHint: turn.resumeSessionHint,
          appendUserTurn: false,
        ),
      );
    } catch (error) {
      if (!disposedInternal) {
        applyGatewayChatFailureInternal(
          sessionKey: turn.sessionKey,
          target: turn.target,
          error: error,
        );
      }
    } finally {
      openClawGatewayActiveTasksInternal = math.max(
        0,
        openClawGatewayActiveTasksInternal - 1,
      );
      if (!disposedInternal) {
        drainOpenClawGatewayQueueInternal();
        recomputeTasksInternal();
        notifyIfActiveInternal();
      }
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
    final startedAtMs = DateTime.now().millisecondsSinceEpoch.toDouble();
    aiGatewayPendingSessionKeysInternal.add(sessionKey);
    upsertTaskThreadInternal(
      sessionKey,
      lifecycleStatus: 'running',
      lastRunAtMs: startedAtMs,
      lastResultCode: 'running',
      lastArtifactSyncAtMs: startedAtMs,
      lastArtifactSyncStatus: 'running',
      lastTaskArtifactRelativePaths: const <String>[],
      updatedAtMs: startedAtMs,
    );
    recomputeTasksInternal();
    notifyIfActiveInternal();
  }

  void clearGatewayTaskArtifactStateInternal(
    String sessionKey, {
    required double completedAtMs,
    required String syncStatus,
  }) {
    upsertTaskThreadInternal(
      sessionKey,
      lastArtifactSyncAtMs: completedAtMs,
      lastArtifactSyncStatus: syncStatus,
      lastTaskArtifactRelativePaths: const <String>[],
      updatedAtMs: completedAtMs,
    );
  }

  Future<void> applyGatewayChatResultInternal({
    required String sessionKey,
    required AssistantExecutionTarget target,
    required GoTaskServiceResult result,
  }) async {
    final completedAtMs = DateTime.now().millisecondsSinceEpoch.toDouble();
    final assistantText = result.message.trim();
    final hasCurrentRunArtifacts = result.artifacts.isNotEmpty;
    final noDisplayableOutput =
        result.success && assistantText.isEmpty && !hasCurrentRunArtifacts;
    final terminalResultCode = noDisplayableOutput
        ? 'failed'
        : gatewayTerminalResultCodeInternal(result);
    final remoteWorkingDirectory = result.remoteWorkingDirectory.trim();
    clearAiGatewayStreamingTextInternal(sessionKey);
    upsertTaskThreadInternal(
      sessionKey,
      gatewayEntryState: goTaskServiceGatewayEntryState(
        requestedTarget: target,
        result: result,
      ),
      latestResolvedRuntimeModel: result.resolvedModel.trim(),
      lastRemoteWorkingDirectory: remoteWorkingDirectory.isNotEmpty
          ? remoteWorkingDirectory
          : '',
      lastRemoteWorkspaceRefKind: result.remoteWorkspaceRefKind,
      lifecycleStatus: 'ready',
      lastRunAtMs: completedAtMs,
      lastResultCode: terminalResultCode,
      updatedAtMs: completedAtMs,
    );
    if (isOpenClawNoExportedArtifactsGuardResultInternal(result)) {
      await persistGoTaskArtifactsForSessionInternal(sessionKey, result);
      return;
    }
    if (!result.success) {
      clearGatewayTaskArtifactStateInternal(
        sessionKey,
        completedAtMs: completedAtMs,
        syncStatus: 'failed',
      );
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
    if (noDisplayableOutput) {
      clearGatewayTaskArtifactStateInternal(
        sessionKey,
        completedAtMs: completedAtMs,
        syncStatus: 'failed',
      );
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
    if (assistantText.isNotEmpty) {
      appendLocalSessionMessageInternal(
        sessionKey,
        GatewayChatMessage(
          id: nextLocalMessageIdInternal(),
          role: 'assistant',
          text: assistantText,
          timestampMs: completedAtMs,
          toolCallId: null,
          toolName: null,
          stopReason: null,
          pending: false,
          error: false,
        ),
        persistInThreadContext: true,
      );
    }
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
        lastRemoteWorkingDirectory: '',
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
      return;
    }
    upsertTaskThreadInternal(
      sessionKey,
      lifecycleStatus: 'ready',
      lastRunAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
      lastResultCode: interruptedTransportCode ?? 'error',
      lastRemoteWorkingDirectory: '',
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
    return lastResultCode != 'RUNNING' &&
        lastResultCode != 'QUEUED' &&
        lastResultCode != 'ABORTED' &&
        lastResultCode != gatewayAcpHttpConnectTimeoutCode &&
        lastResultCode != gatewayAcpHttpConnectFailedCode &&
        lastResultCode != gatewayAcpHttpHandshakeInterruptedCode;
  }

  String gatewayTerminalResultCodeInternal(GoTaskServiceResult result) {
    if (result.success) {
      return 'success';
    }
    final status = result.status.trim();
    if (status.isNotEmpty) {
      return status;
    }
    final code = result.code.trim();
    if (code.isNotEmpty) {
      return code;
    }
    return 'error';
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
        lastRemoteWorkingDirectory: '',
        lastArtifactSyncAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
        lastArtifactSyncStatus: 'failed',
        lastTaskArtifactRelativePaths: const <String>[],
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
      try {
        await goTaskServiceClientInternal.cancelTask(
          route: GoTaskServiceRoute.externalAcpSingle,
          target: assistantExecutionTargetForSession(sessionKey),
          sessionId: sessionKey,
          threadId: sessionKey,
        );
      } catch (_) {
        // Best effort cancellation only. Local state must still leave pending.
      }
      removeQueuedOpenClawGatewayTurnsForSessionInternal(sessionKey);
      markOpenClawGatewayTurnAbortedInternal(sessionKey);
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
