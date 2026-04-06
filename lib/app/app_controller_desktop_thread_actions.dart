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
import '../runtime/go_task_service_client.dart';
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
import 'app_controller_desktop_external_acp_routing.dart';
import 'app_controller_desktop_single_agent.dart';
import 'app_controller_desktop_thread_binding.dart';
import 'app_controller_desktop_thread_sessions.dart';
import 'app_controller_desktop_workspace_execution.dart';
import 'app_controller_desktop_settings_runtime.dart';
import 'app_controller_desktop_thread_storage.dart';
import 'app_controller_desktop_skill_permissions.dart';
import 'app_controller_desktop_runtime_helpers.dart';

// ignore_for_file: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
extension AppControllerDesktopThreadActions on AppController {
  bool assistantSessionHasPendingRun(String sessionKey) {
    final normalized = normalizedAssistantSessionKeyInternal(sessionKey);
    return aiGatewayPendingSessionKeysInternal.contains(normalized) ||
        (multiAgentRunPendingInternal &&
            matchesSessionKey(
              normalized,
              sessionsControllerInternal.currentSessionKey,
            ));
  }

  Future<void> sendSingleAgentMessageInternal(
    String message, {
    required String thinking,
    required List<GatewayChatAttachmentPayload> attachments,
    required List<CollaborationAttachment> localAttachments,
  }) => AppControllerDesktopSingleAgent(this).sendSingleAgentMessageInternal(
    message,
    thinking: thinking,
    attachments: attachments,
    localAttachments: localAttachments,
  );

  Future<void> abortAiGatewayRunInternal(String sessionKey) =>
      AppControllerDesktopSingleAgent(
        this,
      ).abortAiGatewayRunInternal(sessionKey);

  Future<void> connectSavedGateway() async {
    final target = currentAssistantExecutionTarget;
    if (target == AssistantExecutionTarget.singleAgent) {
      return;
    }
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
    if (currentAssistantExecutionTarget !=
        AssistantExecutionTarget.singleAgent) {
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
    }
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

    if (!isSingleAgentMode) {
      preserveGatewayHistoryForSessionInternal(previousSessionKey);
    }

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
    );
    if (nextTarget == AssistantExecutionTarget.singleAgent) {
      await refreshSingleAgentSkillsForSession(nextSessionKey);
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
    final currentSessionKey = sessionsControllerInternal.currentSessionKey;
    final currentTarget = assistantExecutionTargetForSession(currentSessionKey);
    await ensureDesktopTaskThreadBindingInternal(
      currentSessionKey,
      executionTarget: currentTarget,
    );
    var workspacePath = assistantWorkspacePathForSession(
      currentSessionKey,
    ).trim();
    if (workspacePath.isEmpty) {
      final error = StateError(
        appText(
          '当前线程缺少工作路径，无法运行。请先配置工作区根目录后再试。',
          'This thread has no workspace path, so it cannot run. Configure a workspace root and try again.',
        ),
      );
      appendAssistantThreadMessageInternal(
        currentSessionKey,
        assistantErrorMessageInternal(error.message),
      );
      await flushAssistantThreadPersistenceInternal();
      recomputeTasksInternal();
      throw error;
    }
    if (currentTarget == AssistantExecutionTarget.singleAgent) {
      await sendSingleAgentMessageInternal(
        message,
        thinking: thinking,
        attachments: attachments,
        localAttachments: localAttachments,
      );
      await flushAssistantThreadPersistenceInternal();
      recomputeTasksInternal();
      return;
    }
    await enqueueThreadTurnInternal<void>(
      normalizedAssistantSessionKeyInternal(currentSessionKey),
      () async {
        final sessionKey = normalizedAssistantSessionKeyInternal(
          currentSessionKey,
        );
        final userText = message.trim().isEmpty
            ? 'See attached.'
            : message.trim();
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
        aiGatewayPendingSessionKeysInternal.add(sessionKey);
        recomputeTasksInternal();
        notifyIfActiveInternal();
        try {
          final dispatch = await codeAgentNodeOrchestratorInternal
              .buildGatewayDispatch(buildCodeAgentNodeStateInternal());
          final result = await goTaskServiceClientInternal.executeTask(
            GoTaskServiceRequest(
              sessionId: sessionKey,
              threadId: sessionKey,
              target: currentTarget,
              prompt: message,
              workingDirectory: assistantWorkspacePathForSession(
                sessionKey,
              ).trim(),
              model: assistantModelForSession(sessionKey),
              thinking: thinking,
              selectedSkills: selectedSkillLabels,
              inlineAttachments: attachments,
              localAttachments: localAttachments,
              aiGatewayBaseUrl: aiGatewayUrl,
              aiGatewayApiKey: await loadAiGatewayApiKey(),
              agentId: dispatch.agentId ?? '',
              metadata: dispatch.metadata,
              routing: buildExternalAcpRoutingForSessionInternal(sessionKey),
            ),
            onUpdate: (update) {
              if (update.isDelta) {
                appendAiGatewayStreamingTextInternal(sessionKey, update.text);
                notifyIfActiveInternal();
              }
            },
          );
          clearAiGatewayStreamingTextInternal(sessionKey);
          upsertTaskThreadInternal(
            sessionKey,
            gatewayEntryState: goTaskServiceGatewayEntryState(
              requestedTarget: currentTarget,
              result: result,
            ),
            latestResolvedRuntimeModel: result.resolvedModel.trim(),
            lifecycleStatus: 'ready',
            lastRunAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
            lastResultCode: result.success ? 'success' : 'error',
            updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
          );
          if (!result.success) {
            appendLocalSessionMessageInternal(
              sessionKey,
              assistantErrorMessageInternal(
                result.errorMessage.trim().isEmpty
                    ? appText(
                        'GoTaskService 执行失败。',
                        'GoTaskService execution failed.',
                      )
                    : result.errorMessage,
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
        } catch (error) {
          clearAiGatewayStreamingTextInternal(sessionKey);
          upsertTaskThreadInternal(
            sessionKey,
            lifecycleStatus: 'ready',
            lastRunAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
            lastResultCode: 'error',
            updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
          );
          appendLocalSessionMessageInternal(
            sessionKey,
            assistantErrorMessageInternal(error.toString()),
            persistInThreadContext: true,
          );
        } finally {
          aiGatewayPendingSessionKeysInternal.remove(sessionKey);
          clearAiGatewayStreamingTextInternal(sessionKey);
          recomputeTasksInternal();
          notifyIfActiveInternal();
        }
      },
    );
    recomputeTasksInternal();
  }

  Future<void> abortRun() async {
    if (multiAgentRunPendingInternal) {
      final sessionKey = normalizedAssistantSessionKeyInternal(
        sessionsControllerInternal.currentSessionKey,
      );
      try {
        await gatewayAcpClientInternal.cancelSession(
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
    if (isSingleAgentMode) {
      final sessionKey = normalizedAssistantSessionKeyInternal(
        sessionsControllerInternal.currentSessionKey,
      );
      if (aiGatewayPendingSessionKeysInternal.contains(sessionKey)) {
        await goTaskServiceClientInternal.cancelTask(
          route: GoTaskServiceRoute.externalAcpSingle,
          target: AssistantExecutionTarget.singleAgent,
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
      await abortAiGatewayRunInternal(sessionKey);
      return;
    }
    final sessionKey = normalizedAssistantSessionKeyInternal(
      sessionsControllerInternal.currentSessionKey,
    );
    if (aiGatewayPendingSessionKeysInternal.contains(sessionKey)) {
      await goTaskServiceClientInternal.cancelTask(
        route:
            assistantExecutionTargetForSession(sessionKey) ==
                AssistantExecutionTarget.singleAgent
            ? GoTaskServiceRoute.externalAcpSingle
            : GoTaskServiceRoute.openClawTask,
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
        connection.status,
      ),
      'connectionLabel': connection.status.label,
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

  Future<void> tryBindWorkspaceForOnlyChatFallbackInternal(
    String sessionKey,
    AssistantExecutionTarget currentTarget,
  ) async {
    throw StateError(
      'tryBindWorkspaceForOnlyChatFallbackInternal is no longer supported.',
    );
  }
}
