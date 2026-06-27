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
    final association = taskThreadForSessionInternal(
      normalized,
    )?.openClawTaskAssociation;
    return aiGatewayPendingSessionKeysInternal.contains(normalized) ||
        (association != null && !association.isTerminal) ||
        openClawGatewayQueuedTurnsBySessionInternal[normalized]?.any(
              (turn) => !turn.cancelled,
            ) ==
            true ||
        false;
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
    } catch (error) {
      debugPrint('Gateway health refresh failed: $error');
    }
    try {
      await runtimeInternal.status();
    } catch (error) {
      debugPrint('Gateway status refresh failed: $error');
    }
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

  Future<void> refreshSessions({bool preserveCurrentSelection = false}) async {
    final previousSessionKey = normalizedAssistantSessionKeyInternal(
      sessionsControllerInternal.currentSessionKey,
    );
    sessionsControllerInternal.configure(
      selectedAgentId: agentsControllerInternal.selectedAgentId,
      defaultAgentId: '',
    );
    await sessionsControllerInternal.refresh();
    if (preserveCurrentSelection &&
        isAppOwnedAssistantSessionKeyInternal(previousSessionKey) &&
        !isAssistantTaskArchived(previousSessionKey)) {
      await setCurrentAssistantSessionKeyInternal(
        previousSessionKey,
        persistSelection: false,
      );
      recomputeTasksInternal();
      return;
    }
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
    String? sessionKey,
    String thinking = 'off',
    List<GatewayChatAttachmentPayload> attachments =
        const <GatewayChatAttachmentPayload>[],
    List<CollaborationAttachment> localAttachments =
        const <CollaborationAttachment>[],
    List<String> selectedSkillLabels = const <String>[],
  }) async {
    var targetSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey ?? sessionsControllerInternal.currentSessionKey,
    );
    if (!isAppOwnedAssistantSessionKeyInternal(targetSessionKey)) {
      if (sessionKey != null && sessionKey.trim().isNotEmpty) {
        throw StateError(
          appText(
            '提交目标会话无效，请重新选择任务后提交。',
            'The submit target session is invalid. Select the task again before submitting.',
          ),
        );
      }
      await ensureActiveAssistantThreadInternal();
      targetSessionKey = normalizedAssistantSessionKeyInternal(
        sessionsControllerInternal.currentSessionKey,
      );
    }
    final resumeSessionHint = shouldResumeGatewaySessionForNextSendInternal(
      targetSessionKey,
    );
    await dispatchGatewayChatTurnInternal(
      sessionKey: targetSessionKey,
      message: message,
      thinking: thinking,
      attachments: attachments,
      localAttachments: localAttachments,
      selectedSkillLabels: selectedSkillLabels,
      resumeSessionHint: resumeSessionHint,
    );
  }

  Future<void> continueAssistantTaskInternal(String sessionKey) async {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey.trim().isEmpty
          ? sessionsControllerInternal.currentSessionKey
          : sessionKey,
    );
    final thread = taskThreadForSessionInternal(normalizedSessionKey);
    final lifecycleStatus = thread?.lifecycleState.status ?? '';
    final lastResultCode = thread?.lifecycleState.lastResultCode ?? '';
    final artifactSyncStatus = thread?.lastArtifactSyncStatus ?? '';
    if (!isRecoverableAssistantTaskStateInternal(
      lifecycleStatus: lifecycleStatus,
      lastResultCode: lastResultCode,
      artifactSyncStatus: artifactSyncStatus,
    )) {
      final error = StateError(
        appText('当前任务状态不可继续执行。', 'The current task state cannot be continued.'),
      );
      appendAssistantThreadMessageInternal(
        normalizedSessionKey,
        assistantErrorMessageInternal(error.message),
      );
      await flushAssistantThreadPersistenceInternal();
      recomputeTasksInternal();
      notifyIfActiveInternal();
      throw error;
    }
    final lastUserTurn = lastCommittedUserTurnForGatewaySessionInternal(
      normalizedSessionKey,
    );
    final message = lastUserTurn?.text.trim() ?? '';
    if (message.isEmpty) {
      final error = StateError(
        appText(
          '当前任务没有可恢复的用户请求，请输入需求后重新提交。',
          'This task has no recoverable user request. Enter a request and submit it again.',
        ),
      );
      appendAssistantThreadMessageInternal(
        normalizedSessionKey,
        assistantErrorMessageInternal(error.message),
      );
      await flushAssistantThreadPersistenceInternal();
      recomputeTasksInternal();
      notifyIfActiveInternal();
      throw error;
    }
    await dispatchGatewayChatTurnInternal(
      sessionKey: normalizedSessionKey,
      message: message,
      thinking: 'off',
      attachments: const <GatewayChatAttachmentPayload>[],
      localAttachments: const <CollaborationAttachment>[],
      selectedSkillLabels: const <String>[],
      resumeSessionHint:
          lastResultCode.trim().toUpperCase() != 'ABORTED' &&
          shouldResumeGatewaySessionForNextSendInternal(normalizedSessionKey),
      appendUserTurn: false,
    );
  }

  Future<void> dispatchGatewayChatTurnInternal({
    required String sessionKey,
    required String message,
    required String thinking,
    required List<GatewayChatAttachmentPayload> attachments,
    required List<CollaborationAttachment> localAttachments,
    required List<String> selectedSkillLabels,
    required bool resumeSessionHint,
    bool appendUserTurn = true,
  }) async {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    final currentTarget = assistantExecutionTargetForSession(
      normalizedSessionKey,
    );
    var connectionState = assistantConnectionStateForSession(
      normalizedSessionKey,
    );
    if (!connectionState.connected &&
        isBridgeAcpRuntimeConfiguredInternal() &&
        bridgeCapabilityRefreshNeededForAssistantTargetInternal(
          currentTarget,
        )) {
      await refreshAcpCapabilitiesInternal(forceRefresh: true);
      connectionState = assistantConnectionStateForSession(
        normalizedSessionKey,
      );
    }
    if (!connectionState.connected) {
      final error = StateError(connectionState.detailLabel);
      appendAssistantThreadMessageInternal(
        normalizedSessionKey,
        assistantErrorMessageInternal(error.message),
      );
      await flushAssistantThreadPersistenceInternal();
      recomputeTasksInternal();
      notifyIfActiveInternal();
      throw error;
    }
    await ensureDesktopTaskThreadBindingInternal(
      normalizedSessionKey,
      executionTarget: currentTarget,
    );
    final workingDirectory =
        assistantWorkingDirectoryForSessionInternal(
          normalizedSessionKey,
        )?.trim() ??
        '';
    final remoteWorkingDirectoryHint =
        assistantRemoteWorkingDirectoryHintForSessionInternal(
          normalizedSessionKey,
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
        normalizedSessionKey,
        assistantErrorMessageInternal(error.message),
      );
      await flushAssistantThreadPersistenceInternal();
      recomputeTasksInternal();
      throw error;
    }
    if (providerCatalogForExecutionTarget(currentTarget).isEmpty) {
      await refreshSingleAgentCapabilitiesInternal(forceRefresh: true);
      if (providerCatalogForExecutionTarget(currentTarget).isEmpty) {
        upsertTaskThreadInternal(
          normalizedSessionKey,
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
          normalizedSessionKey,
          assistantErrorMessageInternal(error.message),
        );
        await flushAssistantThreadPersistenceInternal();
        recomputeTasksInternal();
        notifyIfActiveInternal();
        throw error;
      }
    }
    final provider = assistantProviderForSession(normalizedSessionKey);
    final model = currentTarget.isGateway
        ? ''
        : assistantModelForSession(normalizedSessionKey);
    final routing = buildExternalAcpRoutingForSessionInternal(
      normalizedSessionKey,
    );
    final dispatch = await codeAgentNodeOrchestratorInternal
        .buildGatewayDispatch(
          buildCodeAgentNodeStateInternal(executionTarget: currentTarget),
        );
    final capturedSelectedSkillLabels = List<String>.unmodifiable(
      selectedSkillLabels,
    );
    final inlineAttachmentsToUpload =
        registerTaskInputAttachmentsForGatewayTurnInternal(
          normalizedSessionKey,
          attachments,
        );
    final capturedAttachments = List<GatewayChatAttachmentPayload>.unmodifiable(
      inlineAttachmentsToUpload,
    );
    final capturedLocalAttachments = List<CollaborationAttachment>.unmodifiable(
      localAttachments,
    );
    final executionWorkingDirectory = gatewayExecutionWorkingDirectoryInternal(
      target: currentTarget,
      workingDirectory: workingDirectory,
      remoteWorkingDirectoryHint: remoteWorkingDirectoryHint,
    );
    final taskMetadata = Map<String, dynamic>.unmodifiable(
      gatewayTaskMetadataWithArtifactContractInternal(
        baseMetadata: dispatch.metadata,
        sessionKey: normalizedSessionKey,
        userPrompt: message,
        localWorkingDirectory: workingDirectory,
        executionWorkingDirectory: executionWorkingDirectory,
        remoteWorkingDirectoryHint: remoteWorkingDirectoryHint,
      ),
    );
    if (usesOpenClawGatewayQueueInternal(currentTarget, provider)) {
      await enqueueOpenClawGatewayTurnInternal(
        OpenClawGatewayQueuedTurnInternal(
          queueId:
              'openclaw-${DateTime.now().microsecondsSinceEpoch}-$localMessageCounterInternal',
          sessionKey: normalizedSessionKey,
          target: currentTarget,
          provider: provider,
          message: message,
          thinking: thinking,
          selectedSkillLabels: capturedSelectedSkillLabels,
          attachments: capturedAttachments,
          localAttachments: capturedLocalAttachments,
          workingDirectory: executionWorkingDirectory,
          localWorkingDirectory: workingDirectory,
          remoteWorkingDirectoryHint: remoteWorkingDirectoryHint,
          model: model,
          routing: routing,
          agentId: dispatch.agentId ?? '',
          metadata: taskMetadata,
          resumeSessionHint: resumeSessionHint,
          appendUserTurn: appendUserTurn,
        ),
      );
      return;
    }
    await enqueueThreadTurnInternal<void>(
      normalizedSessionKey,
      () => runGatewayChatTurnInternal(
        sessionKey: normalizedSessionKey,
        target: currentTarget,
        provider: provider,
        message: message,
        thinking: thinking,
        selectedSkillLabels: capturedSelectedSkillLabels,
        attachments: capturedAttachments,
        localAttachments: capturedLocalAttachments,
        workingDirectory: workingDirectory,
        localWorkingDirectory: workingDirectory,
        executionWorkingDirectory: executionWorkingDirectory,
        remoteWorkingDirectoryHint: remoteWorkingDirectoryHint,
        model: model,
        routing: routing,
        agentId: dispatch.agentId ?? '',
        metadata: taskMetadata,
        resumeSessionHint: resumeSessionHint,
        appendUserTurn: appendUserTurn,
      ),
    );
    recomputeTasksInternal();
  }

  List<GatewayChatAttachmentPayload>
  registerTaskInputAttachmentsForGatewayTurnInternal(
    String sessionKey,
    List<GatewayChatAttachmentPayload> attachments,
  ) {
    if (attachments.isEmpty) {
      return const <GatewayChatAttachmentPayload>[];
    }
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    final existing = taskThreadForSessionInternal(normalizedSessionKey);
    final existingByKey = <String, TaskInputAttachmentRecord>{
      for (final item
          in existing?.taskInputAttachments ??
              const <TaskInputAttachmentRecord>[])
        if (item.key.isNotEmpty) item.key: item,
    };
    final inlineAttachmentsToUpload = <GatewayChatAttachmentPayload>[];
    final nextByKey = <String, TaskInputAttachmentRecord>{...existingByKey};
    final uploadedAtMs = DateTime.now().millisecondsSinceEpoch.toDouble();
    for (final attachment in attachments) {
      final key = gatewayAttachmentPayloadSha256Internal(attachment);
      if (key.isEmpty) {
        inlineAttachmentsToUpload.add(attachment);
        continue;
      }
      if (!existingByKey.containsKey(key)) {
        inlineAttachmentsToUpload.add(attachment);
      }
      nextByKey.putIfAbsent(
        key,
        () => TaskInputAttachmentRecord(
          name: attachment.fileName.trim(),
          mimeType: attachment.mimeType.trim(),
          sha256: key,
          type: attachment.type.trim(),
          uploadedAtMs: uploadedAtMs,
          sourcePath: attachment.sourcePath.trim(),
        ),
      );
    }
    if (nextByKey.length != existingByKey.length) {
      upsertTaskThreadInternal(
        normalizedSessionKey,
        taskInputAttachments: nextByKey.values.toList(growable: false),
        updatedAtMs: uploadedAtMs,
      );
    }
    return inlineAttachmentsToUpload;
  }

  String gatewayAttachmentPayloadSha256Internal(
    GatewayChatAttachmentPayload attachment,
  ) => goTaskServiceAttachmentSha256(attachment);

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
    String? localWorkingDirectory,
    String? executionWorkingDirectory,
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
      workingDirectory: localWorkingDirectory ?? workingDirectory,
      executionWorkingDirectory: executionWorkingDirectory ?? workingDirectory,
      remoteWorkingDirectoryHint: remoteWorkingDirectoryHint,
      target: target,
      taskInputAttachments:
          taskThreadForSessionInternal(sessionKey)?.taskInputAttachments ??
          const <TaskInputAttachmentRecord>[],
    );
    if (appendUserTurn) {
      appendGatewayUserTurnInternal(sessionKey, message);
    }
    markGatewayChatRunInternal(sessionKey);
    var handedOffToBridgeTask = false;
    try {
      final result = await goTaskServiceClientInternal.executeTask(
        GoTaskServiceRequest(
          sessionId: sessionKey,
          threadId: sessionKey,
          target: target,
          provider: provider,
          prompt: taskPrompt,
          workingDirectory: executionWorkingDirectory ?? workingDirectory,
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
      if (!aiGatewayPendingSessionKeysInternal.contains(sessionKey) &&
          taskThreadForSessionInternal(
                sessionKey,
              )?.lifecycleState.lastResultCode ==
              'aborted') {
        clearAiGatewayStreamingTextInternal(sessionKey);
        return;
      }
      final association = result.openClawTaskAssociation;
      if (association != null) {
        handedOffToBridgeTask = true;
        persistOpenClawTaskAssociationInternal(
          sessionKey: sessionKey,
          association: association,
        );
        unawaited(
          pollOpenClawTaskAssociationInternal(
            sessionKey: sessionKey,
            target: target,
            association: association,
          ),
        );
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
      await applyGatewayChatFailureInternal(
        sessionKey: sessionKey,
        target: target,
        error: error,
      );
    } finally {
      if (!handedOffToBridgeTask) {
        aiGatewayPendingSessionKeysInternal.remove(sessionKey);
        clearAiGatewayStreamingTextInternal(sessionKey);
      }
      recomputeTasksInternal();
      notifyIfActiveInternal();
    }
  }

  void persistOpenClawTaskAssociationInternal({
    required String sessionKey,
    required OpenClawTaskAssociation association,
  }) {
    final nowMs = DateTime.now().millisecondsSinceEpoch.toDouble();
    aiGatewayPendingSessionKeysInternal.add(sessionKey);
    upsertTaskThreadInternal(
      sessionKey,
      lifecycleStatus: 'running',
      lastResultCode: 'running',
      lastRunAtMs: association.startedAtMs > 0
          ? association.startedAtMs
          : nowMs,
      lastArtifactSyncAtMs: nowMs,
      lastArtifactSyncStatus: 'running',
      openClawTaskAssociation: association,
      updatedAtMs: nowMs,
    );
    recomputeTasksInternal();
    notifyIfActiveInternal();
    unawaited(flushAssistantThreadPersistenceInternal());
  }

  Future<void> pollOpenClawTaskAssociationInternal({
    required String sessionKey,
    required AssistantExecutionTarget target,
    required OpenClawTaskAssociation association,
    Duration pollInterval = const Duration(seconds: 2),
  }) async {
    var current = association;
    var firstAttempt = true;
    var artifactSyncAttempts = 0;
    double? artifactSyncStartedAtMs;
    // T3: running 轮询兜底截止的起算锚点（首次进入 running 轮询的时间）。
    double? runningPollFirstAtMs;
    // T5: 连续传输瞬断计数（每次成功 getTask 重置）。
    var transientRetries = 0;
    final existingThread = taskThreadForSessionInternal(sessionKey);
    if (association.status.trim().toLowerCase() == 'syncing-artifacts') {
      artifactSyncStartedAtMs = existingThread?.lastArtifactSyncAtMs;
    }
    while (true) {
      if (disposedInternal) {
        return;
      }
      if (!aiGatewayPendingSessionKeysInternal.contains(sessionKey)) {
        return;
      }
      if (!firstAttempt) {
        await Future<void>.delayed(pollInterval);
      }
      firstAttempt = false;
      try {
        final result = await goTaskServiceClientInternal.getTask(
          route: GoTaskServiceRoute.externalAcpSingle,
          target: target,
          association: current,
        );
        if (disposedInternal) {
          return;
        }
        // T5: 成功一次即重置连续瞬断计数。
        transientRetries = 0;
        final nextAssociation =
            result.openClawTaskAssociation ??
            current.copyWith(
              status: result.status.trim().isEmpty
                  ? current.status
                  : result.status.trim(),
            );
        current = nextAssociation;
        // A tasks.get response may temporarily omit association decoration
        // while the plugin/runtime is reconnecting. The explicit status is
        // authoritative; never finalize a running task as an empty success.
        if (result.status.trim().toLowerCase() == 'running' ||
            result.isOpenClawRunningTaskHandle) {
          // T3: 给 running 轮询加兜底截止，避免 gateway 始终回 running 时无限轮询、永远卡「任务运行中...」。
          final nowMs = DateTime.now().millisecondsSinceEpoch.toDouble();
          runningPollFirstAtMs ??= nowMs;
          if (openClawRunningPollDeadlineReachedInternal(
            startedAtMs: current.startedAtMs,
            taskLoadClass: current.taskLoadClass,
            firstPollAtMs: runningPollFirstAtMs,
            nowMs: nowMs,
          )) {
            markOpenClawRunningPollTimeoutInternal(
              sessionKey: sessionKey,
              association: current,
            );
            return;
          }
          persistOpenClawTaskAssociationInternal(
            sessionKey: sessionKey,
            association: nextAssociation,
          );
          continue;
        }
        if (aiGatewayPendingSessionKeysInternal.contains(sessionKey)) {
          final hasTaskScopedOpenClawArtifacts =
              current.artifactScope.trim().isNotEmpty ||
              current.artifactDirectory.trim().isNotEmpty;
          final hasRequiredExts = current.requiredArtifactExtensions.isNotEmpty;
          final requiresArtifactExport =
              current.requiresArtifactExport || hasRequiredExts;
          final hasEnoughArtifacts =
              result.artifacts.isNotEmpty &&
              (!hasRequiredExts ||
                  current.requiredArtifactExtensions.every((ext) {
                    return result.artifacts.any(
                      (a) => openClawArtifactPathHasRequiredExtension(
                        a.relativePath,
                        ext,
                      ),
                    );
                  }));
          final shouldKeepPollingForArtifacts =
              hasTaskScopedOpenClawArtifacts &&
              requiresArtifactExport &&
              !hasEnoughArtifacts;
          if (shouldKeepPollingForArtifacts) {
            final nowMs = DateTime.now().millisecondsSinceEpoch.toDouble();
            artifactSyncAttempts += 1;
            artifactSyncStartedAtMs ??= nowMs;
            final missingRequired = current.requiredArtifactExtensions
                .where((ext) {
                  return !result.artifacts.any(
                    (a) => openClawArtifactPathHasRequiredExtension(
                      a.relativePath,
                      ext,
                    ),
                  );
                })
                .toList(growable: false);
            if (openClawArtifactSyncLimitReachedInternal(
              attemptCount: artifactSyncAttempts,
              firstSyncAtMs: artifactSyncStartedAtMs,
              nowMs: nowMs,
            )) {
              markOpenClawArtifactSyncTimeoutInternal(
                sessionKey: sessionKey,
                association: current,
                missingRequiredExtensions: missingRequired.isEmpty
                    ? current.requiredArtifactExtensions
                    : missingRequired,
                remoteWorkingDirectory: result.remoteWorkingDirectory,
                remoteWorkspaceRefKind: result.remoteWorkspaceRefKind,
              );
              return;
            }
            current = current.copyWith(status: 'syncing-artifacts');
            upsertTaskThreadInternal(
              sessionKey,
              lifecycleStatus: 'running',
              lastResultCode: 'running',
              lastRemoteWorkingDirectory:
                  result.remoteWorkingDirectory.trim().isEmpty
                  ? taskThreadForSessionInternal(
                      sessionKey,
                    )?.lastRemoteWorkingDirectory
                  : result.remoteWorkingDirectory.trim(),
              lastRemoteWorkspaceRefKind:
                  result.remoteWorkspaceRefKind ??
                  taskThreadForSessionInternal(
                    sessionKey,
                  )?.lastRemoteWorkspaceRefKind,
              lastArtifactSyncAtMs: nowMs,
              lastArtifactSyncStatus: 'syncing',
              openClawTaskAssociation: current,
              updatedAtMs: nowMs,
            );
            recomputeTasksInternal();
            notifyIfActiveInternal();
            unawaited(flushAssistantThreadPersistenceInternal());
            continue;
          }
          await applyGatewayChatResultInternal(
            sessionKey: sessionKey,
            target: target,
            result: result,
            artifactSyncAttempts: artifactSyncAttempts,
            artifactSyncStartedAtMs: artifactSyncStartedAtMs,
          );
        }
        aiGatewayPendingSessionKeysInternal.remove(sessionKey);
        clearAiGatewayStreamingTextInternal(sessionKey);
        recomputeTasksInternal();
        notifyIfActiveInternal();
        return;
      } catch (error) {
        if (disposedInternal) {
          return;
        }
        // T5: 轮询期间 App↔bridge 传输瞬断（ACP_HTTP_CONNECTION_CLOSED）时，有界重试续轮询，
        // 降级为「后台续跑·重连中」而非硬失败丢结果。bridge 侧 T7/T9 会在网关侧抖动时保持 run
        // 可查/到点收口；这里只兜 App↔bridge 这一跳的瞬断。连续超过上限才落终态。
        if (aiGatewayPendingSessionKeysInternal.contains(sessionKey) &&
            interruptedAcpHttpTransportCodeInternal(error) ==
                'ACP_HTTP_CONNECTION_CLOSED' &&
            transientRetries < kOpenClawPollTransientRetryLimit) {
          transientRetries += 1;
          // 不清 pending、不落终态：任务保持「运行中」，循环顶部 2s 延迟后重试下一次 getTask。
          recomputeTasksInternal();
          notifyIfActiveInternal();
          continue;
        }
        if (aiGatewayPendingSessionKeysInternal.contains(sessionKey)) {
          await applyGatewayChatFailureInternal(
            sessionKey: sessionKey,
            target: target,
            error: error,
          );
        }
        aiGatewayPendingSessionKeysInternal.remove(sessionKey);
        clearAiGatewayStreamingTextInternal(sessionKey);
        recomputeTasksInternal();
        notifyIfActiveInternal();
        return;
      }
    }
  }

  void resumeOpenClawTaskAssociationsInternal({String? onlySessionKey}) {
    final normalizedOnly = onlySessionKey == null
        ? ''
        : normalizedAssistantSessionKeyInternal(onlySessionKey);
    for (final record in taskThreadRepositoryInternal.snapshot()) {
      if (normalizedOnly.isNotEmpty && record.threadId != normalizedOnly) {
        continue;
      }
      final association = record.openClawTaskAssociation;
      if (association == null || association.isTerminal) {
        continue;
      }
      if (association.status.trim().toLowerCase() == 'syncing-artifacts' &&
          openClawArtifactSyncLimitReachedInternal(
            attemptCount: 0,
            firstSyncAtMs: record.lastArtifactSyncAtMs,
          )) {
        markOpenClawArtifactSyncTimeoutInternal(
          sessionKey: record.threadId,
          association: association,
          missingRequiredExtensions: association.requiredArtifactExtensions,
          remoteWorkingDirectory: record.lastRemoteWorkingDirectory,
          remoteWorkspaceRefKind: record.lastRemoteWorkspaceRefKind,
        );
        continue;
      }
      aiGatewayPendingSessionKeysInternal.add(record.threadId);
      unawaited(
        pollOpenClawTaskAssociationInternal(
          sessionKey: record.threadId,
          target: assistantExecutionTargetFromExecutionMode(
            record.executionBinding.executionMode,
          ),
          association: association,
        ),
      );
    }
    recomputeTasksInternal();
    notifyIfActiveInternal();
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
    String? executionWorkingDirectory,
    required String remoteWorkingDirectoryHint,
    required AssistantExecutionTarget target,
    List<TaskInputAttachmentRecord> taskInputAttachments =
        const <TaskInputAttachmentRecord>[],
  }) {
    final requestText = userPrompt.trim().isEmpty
        ? 'See attached.'
        : userPrompt.trim();
    final executionWorkspace =
        executionWorkingDirectory?.trim().isNotEmpty == true
        ? executionWorkingDirectory!.trim()
        : (remoteWorkingDirectoryHint.trim().isNotEmpty
              ? remoteWorkingDirectoryHint.trim()
              : workingDirectory.trim());
    final currentTaskWorkspace = executionWorkspace.isNotEmpty
        ? executionWorkspace
        : (target.isGateway
              ? r'$XWORKMATE_ARTIFACT_DIRECTORY'
              : workingDirectory.trim());
    // 精简工作区上下文：只给 agent 一个明确的工作目录。
    // 此前同时塞 sessionKey + currentTaskWorkspace + localWorkspace + remoteWorkspaceHint
    // 三个近似重复的绝对路径——其中 localWorkspace 是 App 本机线程目录（`~/.xworkmate/threads/…`），
    // 与网关 agent 的文件系统无关；remoteWorkspaceHint 又与 currentTaskWorkspace 重复。
    // 多个相互冲突的路径会让 agent 不知该在哪工作，导致对话任务无法继续执行。
    final buffer = StringBuffer()
      ..writeln('TaskThread workspace context:')
      ..writeln('- sessionKey: $sessionKey')
      ..writeln('- currentTaskWorkspace: $currentTaskWorkspace');
    // 网关任务由插件托管 artifact scope，agent 只需认 currentTaskWorkspace；
    // 本机线程目录对网关 agent 无意义，仅在非网关（本地 agent 实际运行于此）时给出。
    if (!target.isGateway && workingDirectory.trim().isNotEmpty) {
      buffer.writeln('- localWorkspace: ${workingDirectory.trim()}');
    }
    // remoteWorkspaceHint 仅在与 currentTaskWorkspace 不同时才输出（去重）。
    final remoteHint = remoteWorkingDirectoryHint.trim();
    if (remoteHint.isNotEmpty && remoteHint != currentTaskWorkspace) {
      buffer.writeln('- remoteWorkspaceHint: $remoteHint');
    }
    final visibleTaskInputAttachments = taskInputAttachments
        .where((item) => item.name.trim().isNotEmpty && item.key.isNotEmpty)
        .toList(growable: false);
    if (visibleTaskInputAttachments.isNotEmpty) {
      buffer.writeln('- taskInputAttachments:');
      for (final attachment in visibleTaskInputAttachments) {
        final sourcePath = attachment.sourcePath.trim();
        final pathSuffix = sourcePath.isEmpty ? '' : ', path: $sourcePath';
        buffer.writeln(
          '  - ${attachment.name.trim()} (${attachment.mimeType.trim()}, sha256: ${attachment.key}$pathSuffix)',
        );
      }
    }
    buffer
      ..writeln('User request:')
      ..write(requestText);
    return buffer.toString();
  }

  Map<String, dynamic> gatewayTaskMetadataWithArtifactContractInternal({
    required Map<String, dynamic> baseMetadata,
    required String sessionKey,
    required String userPrompt,
    required String localWorkingDirectory,
    required String executionWorkingDirectory,
    required String remoteWorkingDirectoryHint,
  }) {
    final localWorkspace = localWorkingDirectory.trim();
    final executionWorkspace = executionWorkingDirectory.trim();
    final remoteHint = remoteWorkingDirectoryHint.trim();
    final caseHint = gatewayCaseHintForPromptInternal(userPrompt);
    final metadata = <String, dynamic>{
      ...baseMetadata,
      if (caseHint.caseId.isNotEmpty) 'xworkmateCaseId': caseHint.caseId,
      if (caseHint.taskLoadClass.isNotEmpty)
        'taskLoadClass': caseHint.taskLoadClass,
      if (caseHint.requiredArtifactExtensions.isNotEmpty)
        'requiredArtifactExtensions': caseHint.requiredArtifactExtensions,
      if (caseHint.expectedArtifactExtensions.isNotEmpty)
        'expectedArtifactExtensions': caseHint.expectedArtifactExtensions,
    };
    if (caseHint.expectedFileCountByExtension.isNotEmpty) {
      metadata['xworkmateArtifactConstraints'] = <String, dynamic>{
        'schemaVersion': 1,
        'expectedFileCountByExtension': caseHint.expectedFileCountByExtension,
      };
    }
    return <String, dynamic>{
      ...metadata,
      'xworkmateTaskArtifactContract': <String, dynamic>{
        'schemaVersion': 1,
        'appThreadKey': sessionKey,
        'scopeKind': 'task',
        'finalDeliverableDetection': 'remote-runtime',
        'requiresExportBeforeFinalResponse': true,
        'rejectTextOnlyFileClaims': true,
        'expectedArtifactDirs': caseHint.expectedArtifactDirs.isNotEmpty
            ? caseHint.expectedArtifactDirs
            : const <String>[
                'artifacts/',
                'reports/',
                'exports/',
                'assets/',
                'assets/images/',
                'dist/',
              ],
        if (caseHint.requiredArtifactExtensions.isNotEmpty)
          'requiredArtifactExtensions': caseHint.requiredArtifactExtensions,
        if (caseHint.expectedFileCountByExtension.isNotEmpty)
          'expectedFileCountByExtension': caseHint.expectedFileCountByExtension,
        'currentTaskWorkspace': executionWorkspace.isNotEmpty
            ? executionWorkspace
            : (remoteHint.isNotEmpty ? remoteHint : localWorkspace),
        if (localWorkspace.isNotEmpty) 'localWorkspace': localWorkspace,
        if (remoteHint.isNotEmpty) 'remoteWorkspaceHint': remoteHint,
      },
    };
  }

  GatewayTaskCaseHintInternal gatewayCaseHintForPromptInternal(String prompt) {
    final text = prompt.trim();
    final lower = text.toLowerCase();
    final hasSecurityEvolution =
        text.contains('从单机权限') &&
        text.contains('网络边界') &&
        text.contains('Web安全') &&
        text.contains('云身份') &&
        text.contains('Zero Trust') &&
        text.contains('AI Agent') &&
        text.contains('AI模型');
    final wantsAiNewsMd =
        (text.contains('AI资讯') ||
            text.contains('AI 资讯') ||
            text.contains('AI新闻') ||
            lower.contains('ai news')) &&
        (text.contains('md文件') ||
            text.contains('Markdown') ||
            lower.contains('.md') ||
            lower.contains('markdown'));
    if (wantsAiNewsMd) {
      return const GatewayTaskCaseHintInternal(
        caseId: 'case1-ai-news-md',
        taskLoadClass: 'long_task',
        requiredArtifactExtensions: <String>['md'],
        expectedArtifactExtensions: <String>['md'],
        expectedArtifactDirs: <String>['reports/', 'artifacts/'],
      );
    }
    final wantsVideo =
        text.contains('制作视频') ||
        text.contains('测试制作视频') ||
        lower.contains('make video') ||
        lower.contains('mp4');
    final wantsImages =
        text.contains('7张') ||
        text.contains('七张') ||
        text.contains('连续制作') ||
        text.contains('系列图片') ||
        text.contains('一些列图片') ||
        text.contains('一系列图片');
    final wantsPdf =
        text.contains('输出 PDF') ||
        text.contains('输出PDF') ||
        text.contains('PDF文件') ||
        lower.contains('final.pdf');
    final wantsSocialCopy =
        text.contains('微信公众号短图文') ||
        text.contains('小红书风格') ||
        text.contains('X文案串') ||
        text.contains('头条号长文');
    final wantsChapteredImages =
        text.contains('拆章节') ||
        text.contains('每章') ||
        lower.contains('gpt images') ||
        lower.contains('images2');
    if (hasSecurityEvolution && wantsPdf && wantsChapteredImages) {
      return const GatewayTaskCaseHintInternal(
        caseId: 'case5-security-evolution-pdf',
        taskLoadClass: 'complex_chain_task',
        requiredArtifactExtensions: <String>['pdf', 'png', 'md'],
        expectedArtifactExtensions: <String>['pdf', 'png', 'md'],
        expectedArtifactDirs: <String>[
          'exports/',
          'assets/',
          'assets/images/',
          'prompts/',
          'reports/',
        ],
        expectedFileCountByExtension: <String, int>{'pdf': 1, 'png': 7},
      );
    }
    if (hasSecurityEvolution && wantsVideo) {
      return const GatewayTaskCaseHintInternal(
        caseId: 'case2-security-evolution-video',
        taskLoadClass: 'complex_chain_task',
        requiredArtifactExtensions: <String>['mp4'],
        expectedArtifactExtensions: <String>['mp4', 'png', 'md'],
        expectedArtifactDirs: <String>[
          'renders/',
          'assets/',
          'assets/images/',
          'exports/',
        ],
      );
    }
    if (hasSecurityEvolution && wantsImages) {
      return const GatewayTaskCaseHintInternal(
        caseId: 'case3-security-evolution-seven-images',
        taskLoadClass: 'complex_chain_task',
        requiredArtifactExtensions: <String>['png'],
        expectedArtifactExtensions: <String>['png', 'md'],
        expectedArtifactDirs: <String>['assets/', 'assets/images/', 'prompts/'],
        expectedFileCountByExtension: <String, int>{'png': 7},
      );
    }
    if (hasSecurityEvolution && wantsSocialCopy) {
      return const GatewayTaskCaseHintInternal(
        caseId: 'case4-security-evolution-social-copy',
        taskLoadClass: 'long_task',
        requiredArtifactExtensions: <String>['md'],
        expectedArtifactExtensions: <String>['md'],
        expectedArtifactDirs: <String>['reports/', 'artifacts/'],
        expectedFileCountByExtension: <String, int>{'md': 5},
      );
    }
    return const GatewayTaskCaseHintInternal();
  }

  bool usesOpenClawGatewayQueueInternal(
    AssistantExecutionTarget target,
    SingleAgentProvider provider,
  ) {
    return target.isGateway &&
        provider.providerId == kCanonicalGatewayProviderId;
  }

  String gatewayExecutionWorkingDirectoryInternal({
    required AssistantExecutionTarget target,
    required String workingDirectory,
    required String remoteWorkingDirectoryHint,
  }) {
    final remoteHint = remoteWorkingDirectoryHint.trim();
    if (target.isGateway && remoteHint.isNotEmpty) {
      return remoteHint;
    }
    return workingDirectory.trim();
  }

  Future<void> enqueueOpenClawGatewayTurnInternal(
    OpenClawGatewayQueuedTurnInternal turn,
  ) async {
    if (turn.appendUserTurn) {
      appendGatewayUserTurnInternal(turn.sessionKey, turn.message);
    }
    if (openClawGatewayActiveTurnsInternal.length >=
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

  bool removeActiveOpenClawGatewayTurnsForSessionInternal(String sessionKey) {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    var removed = false;
    openClawGatewayActiveTurnsInternal.removeWhere((_, turn) {
      final matches =
          normalizedAssistantSessionKeyInternal(turn.sessionKey) ==
          normalizedSessionKey;
      if (matches) {
        turn.cancelled = true;
        removed = true;
      }
      return matches;
    });
    return removed;
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
      clearOpenClawTaskAssociation: true,
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
    while (openClawGatewayActiveTurnsInternal.length <
            openClawGatewayMaxActiveTasksInternal &&
        openClawGatewayQueuedTurnsInternal.isNotEmpty) {
      final turn = openClawGatewayQueuedTurnsInternal.removeAt(0);
      removeOpenClawGatewayQueuedTurnIndexInternal(turn);
      if (turn.cancelled) {
        continue;
      }
      openClawGatewayActiveTurnsInternal[turn.queueId] = turn;
      markOpenClawGatewayRunningTurnInternal(turn.sessionKey);
      unawaited(runOpenClawGatewayQueuedTurnInternal(turn));
    }
  }

  void markOpenClawGatewayRunningTurnInternal(String sessionKey) {
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
          localWorkingDirectory: turn.localWorkingDirectory,
          executionWorkingDirectory: turn.workingDirectory,
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
        await applyGatewayChatFailureInternal(
          sessionKey: turn.sessionKey,
          target: turn.target,
          error: error,
        );
      }
    } finally {
      openClawGatewayActiveTurnsInternal.remove(turn.queueId);
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

  Future<void> applyGatewayChatResultInternal({
    required String sessionKey,
    required AssistantExecutionTarget target,
    required GoTaskServiceResult result,
    int artifactSyncAttempts = 0,
    double? artifactSyncStartedAtMs,
  }) async {
    final completedAtMs = DateTime.now().millisecondsSinceEpoch.toDouble();
    final assistantText = result.message.trim();
    final hasCurrentRunArtifacts = result.artifacts.isNotEmpty;
    final openClawAssociation = result.openClawTaskAssociation;
    final waitingForOpenClawArtifacts =
        openClawAssociation != null &&
        !hasCurrentRunArtifacts &&
        result.success &&
        (openClawAssociation.requiresArtifactExport ||
            openClawAssociation.requiredArtifactExtensions.isNotEmpty) &&
        (openClawAssociation.artifactScope.trim().isNotEmpty ||
            openClawAssociation.artifactDirectory.trim().isNotEmpty);
    if (waitingForOpenClawArtifacts) {
      persistOpenClawTaskAssociationInternal(
        sessionKey: sessionKey,
        association: openClawAssociation.copyWith(status: 'syncing-artifacts'),
      );
      return;
    }
    final noDisplayableOutput =
        result.success && assistantText.isEmpty && !hasCurrentRunArtifacts;
    final terminalResultCode = noDisplayableOutput
        ? 'OPENCLAW_NO_DISPLAYABLE_OUTPUT'
        : gatewayTerminalResultCodeInternal(result);
    final remoteWorkingDirectory = result.remoteWorkingDirectory.trim();
    clearAiGatewayStreamingTextInternal(sessionKey);
    clearPendingToolCallsForGatewaySessionInternal(
      sessionKey,
      hasError: !result.success,
    );
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
    if (!result.success) {
      upsertTaskThreadInternal(
        sessionKey,
        lastArtifactSyncAtMs: completedAtMs,
        lastArtifactSyncStatus: 'failed',
        lastTaskArtifactRelativePaths: const <String>[],
        clearOpenClawTaskAssociation: true,
        updatedAtMs: completedAtMs,
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
      upsertTaskThreadInternal(
        sessionKey,
        lastArtifactSyncAtMs: completedAtMs,
        lastArtifactSyncStatus: 'failed',
        lastTaskArtifactRelativePaths: const <String>[],
        clearOpenClawTaskAssociation: true,
        updatedAtMs: completedAtMs,
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
    await persistGoTaskArtifactsForSessionInternal(
      sessionKey,
      result,
      artifactSyncAttempts: artifactSyncAttempts,
      artifactSyncStartedAtMs: artifactSyncStartedAtMs,
    );
    if (taskThreadForSessionInternal(
          sessionKey,
        )?.lifecycleState.lastResultCode ==
        kOpenClawArtifactSyncTimeoutCode) {
      return;
    }
    upsertTaskThreadInternal(
      sessionKey,
      lifecycleStatus: 'ready',
      lastRunAtMs: completedAtMs,
      lastResultCode: terminalResultCode,
      clearOpenClawTaskAssociation: !hasCurrentRunArtifacts,
      updatedAtMs: completedAtMs,
    );
  }

  Future<void> applyGatewayChatFailureInternal({
    required String sessionKey,
    required AssistantExecutionTarget target,
    required Object error,
  }) async {
    // T6: 终态一致性。失败处理器是本轮的终态出口，必须自身权威地清 pending，
    // 不能依赖各调用方的 finally（runOpenClawGatewayQueuedTurnInternal 的 finally 此前并不清 pending，
    // 导致「错误已渲染但进度条仍卡在任务运行中」）。对其它已显式 remove 的调用方是幂等的。
    // pending 集合在不同路径下分别用原始 / 归一化 key，两种都移除以确保彻底清空。
    aiGatewayPendingSessionKeysInternal.remove(sessionKey);
    aiGatewayPendingSessionKeysInternal.remove(
      normalizedAssistantSessionKeyInternal(sessionKey),
    );
    clearAiGatewayStreamingTextInternal(sessionKey);
    clearPendingToolCallsForGatewaySessionInternal(sessionKey, hasError: true);
    final completedAtMs = DateTime.now().millisecondsSinceEpoch.toDouble();
    final recoveredArtifactPaths =
        await recoverGatewayFailureArtifactPathsInternal(sessionKey, error);
    upsertTaskThreadInternal(
      sessionKey,
      lifecycleStatus: 'ready',
      lastRunAtMs: completedAtMs,
      lastResultCode: gatewayFailureResultCodeInternal(error),
      lastRemoteWorkingDirectory: '',
      lastArtifactSyncAtMs: completedAtMs,
      lastArtifactSyncStatus: recoveredArtifactPaths.isEmpty
          ? 'failed'
          : 'interrupted',
      lastTaskArtifactRelativePaths: recoveredArtifactPaths,
      clearOpenClawTaskAssociation: true,
      updatedAtMs: completedAtMs,
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

  GatewayChatMessage? lastCommittedUserTurnForGatewaySessionInternal(
    String sessionKey,
  ) {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    final messages = <GatewayChatMessage>[
      ...?assistantThreadRecordsInternal[normalizedSessionKey]?.messages,
      ...?assistantThreadMessagesInternal[normalizedSessionKey],
      ...?localSessionMessagesInternal[normalizedSessionKey],
    ];
    for (final message in messages.reversed) {
      final role = message.role.trim().toLowerCase();
      if (role == 'user' && !message.pending) {
        return message;
      }
    }
    return null;
  }

  bool isRecoverableAssistantTaskStateInternal({
    required String lifecycleStatus,
    required String lastResultCode,
    required String artifactSyncStatus,
  }) {
    final status = lifecycleStatus.trim().toLowerCase();
    final syncStatus = artifactSyncStatus.trim().toLowerCase();
    final result = lastResultCode.trim().toUpperCase();
    return status == 'interrupted' ||
        syncStatus == 'interrupted' ||
        result == 'ABORTED' ||
        result == 'ERROR' ||
        result == 'ACP_HTTP_CONNECTION_CLOSED' ||
        result == 'SESSION_CONTINUATION_UNAVAILABLE';
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
    return !gatewayResultCodeRequiresNewSessionInternal(lastResultCode ?? '');
  }

  String gatewayTerminalResultCodeInternal(GoTaskServiceResult result) {
    if (result.success) {
      return 'success';
    }
    final status = result.status.trim();
    final code = result.code.trim();
    if (status.isNotEmpty && status.toLowerCase() != 'failed') {
      return status;
    }
    if (code.isNotEmpty) {
      return code;
    }
    if (status.isNotEmpty) {
      return status;
    }
    return 'error';
  }

  String gatewayFailureResultCodeInternal(Object error) {
    final unconfirmedConnectCode = unconfirmedAcpHttpConnectCodeInternal(error);
    if (unconfirmedConnectCode != null) {
      return unconfirmedConnectCode;
    }
    final interruptedTransportCode = interruptedAcpHttpTransportCodeInternal(
      error,
    );
    if (interruptedTransportCode != null) {
      return interruptedTransportCode;
    }
    final primaryCode = gatewayExecutionPrimaryCodeInternal(error);
    if (primaryCode != null && primaryCode.isNotEmpty) {
      return primaryCode;
    }
    final detailCode = gatewayExecutionDetailCodeInternal(error);
    if (detailCode != null && detailCode.isNotEmpty) {
      return detailCode;
    }
    return 'error';
  }

  bool gatewayResultCodeRequiresNewSessionInternal(String code) {
    final normalized = code.trim().toUpperCase();
    if (normalized.isEmpty || normalized == 'ACP_HTTP_CONNECTION_CLOSED') {
      return false;
    }
    return const <String>{
      'RUNNING',
      'QUEUED',
      'ABORTED',
      'BRIDGE_NOT_CONNECTED',
      'ARTIFACT_MISSING',
      'OPENCLAW_ARTIFACT_MISSING',
      'OPENCLAW_GATEWAY_QUEUE_FULL',
      'OPENCLAW_GATEWAY_SOCKET_CLOSED',
      'OPENCLAW_NO_DISPLAYABLE_OUTPUT',
      'OPENCLAW_NO_EXPORTED_ARTIFACTS',
      'OPENCLAW_WAIT_FAILED',
      'ACP_HTTP_401',
      'ACP_HTTP_502',
      'ACP_HTTP_CONNECT_FAILED',
      'ACP_HTTP_CONNECT_TIMEOUT',
      'ACP_HTTP_HANDSHAKE_INTERRUPTED',
      'GATEWAY_TASK_REJECTED',
    }.contains(normalized);
  }

  Future<void> abortRun() async {
    final sessionKey = normalizedAssistantSessionKeyInternal(
      sessionsControllerInternal.currentSessionKey,
    );
    if (abortQueuedOpenClawGatewayTurnInternal(sessionKey)) {
      return;
    }
    if (aiGatewayPendingSessionKeysInternal.contains(sessionKey)) {
      // T4: 停止本地权威化。先捕获 association，再立刻把本轮标记为 aborted（清 pending / 置终态 /
      // 让轮询 loop 在下一次迭代退出），UI 立即停止——不依赖 gateway 往返。
      // 随后 best-effort 下发 tasks.cancel；其失败/挂起都不得阻塞或回滚本地终止。
      final association = taskThreadForSessionInternal(
        sessionKey,
      )?.openClawTaskAssociation;
      removeQueuedOpenClawGatewayTurnsForSessionInternal(sessionKey);
      removeActiveOpenClawGatewayTurnsForSessionInternal(sessionKey);
      markOpenClawGatewayTurnAbortedInternal(sessionKey);
      drainOpenClawGatewayQueueInternal();
      unawaited(
        cancelAssistantTaskForSessionInternal(
          sessionKey,
          association: association,
        ),
      );
      return;
    }
  }

  Future<void> cancelAssistantTaskForSessionInternal(
    String sessionKey, {
    OpenClawTaskAssociation? association,
  }) async {
    final normalized = normalizedAssistantSessionKeyInternal(sessionKey);
    // association 可能已被本地终止清空，故允许调用方预先捕获后传入。
    final effectiveAssociation =
        association ??
        taskThreadForSessionInternal(normalized)?.openClawTaskAssociation;
    // best-effort：gateway 不可达 / run 已不存在时不得抛出，避免阻塞停止流程。
    try {
      await goTaskServiceClientInternal.cancelTask(
        route: GoTaskServiceRoute.externalAcpSingle,
        target: assistantExecutionTargetForSession(normalized),
        sessionId: normalized,
        threadId: normalized,
        association: effectiveAssociation,
      );
    } catch (error) {
      debugPrint('cancelAssistantTaskForSession best-effort failed: $error');
    }
  }

  Future<void> prepareForExit() async {
    await abortRun();
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

class GatewayTaskCaseHintInternal {
  const GatewayTaskCaseHintInternal({
    this.caseId = '',
    this.taskLoadClass = '',
    this.requiredArtifactExtensions = const <String>[],
    this.expectedArtifactExtensions = const <String>[],
    this.expectedArtifactDirs = const <String>[],
    this.expectedFileCountByExtension = const <String, int>{},
  });

  final String caseId;
  final String taskLoadClass;
  final List<String> requiredArtifactExtensions;
  final List<String> expectedArtifactExtensions;
  final List<String> expectedArtifactDirs;
  final Map<String, int> expectedFileCountByExtension;
}
