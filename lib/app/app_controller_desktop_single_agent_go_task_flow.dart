// ignore_for_file: unused_import, unnecessary_import

import 'dart:async';
import 'package:flutter/material.dart';
import '../i18n/app_language.dart';
import '../models/app_models.dart';
import '../runtime/go_task_service_client.dart';
import '../runtime/runtime_models.dart';
import 'app_controller_desktop_core.dart';
import 'app_controller_desktop_external_acp_routing.dart';
import 'app_controller_desktop_runtime_helpers.dart';
import 'app_controller_desktop_single_agent_ai_gateway.dart';
import 'app_controller_desktop_single_agent_status_messages.dart';
import 'app_controller_desktop_thread_sessions.dart';
import 'app_controller_desktop_thread_storage.dart';
import 'app_controller_desktop_skill_permissions.dart';

Future<void> sendSingleAgentMessageDesktopGoTaskFlowInternal(
  AppController controller,
  String message, {
  required String thinking,
  required List<GatewayChatAttachmentPayload> attachments,
  required List<CollaborationAttachment> localAttachments,
}) async {
  final sessionKey = controller.normalizedAssistantSessionKeyInternal(
    controller.sessionsControllerInternal.currentSessionKey,
  );
  final trimmed = message.trim();
  if (trimmed.isEmpty && attachments.isEmpty) {
    return;
  }
  await controller.enqueueThreadTurnInternal<void>(sessionKey, () async {
    final sessionTarget = controller.assistantExecutionTargetForSession(
      sessionKey,
    );
    final userText = trimmed.isEmpty ? 'See attached.' : trimmed;
    controller.appendAssistantThreadMessageInternal(
      sessionKey,
      GatewayChatMessage(
        id: controller.nextLocalMessageIdInternal(),
        role: 'user',
        text: userText,
        timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
        toolCallId: null,
        toolName: null,
        stopReason: null,
        pending: false,
        error: false,
      ),
    );
    controller.aiGatewayPendingSessionKeysInternal.add(sessionKey);
    controller.recomputeTasksInternal();
    controller.notifyIfActiveInternal();

    try {
      final routing = controller.buildExternalAcpRoutingForSessionInternal(
        sessionKey,
      );
      final selection = controller.singleAgentProviderForSession(sessionKey);
      await controller.syncExternalAcpProvidersInternal();
      final capabilities = await controller.goTaskServiceClientInternal
          .loadExternalAcpCapabilities(
            target: AssistantExecutionTarget.singleAgent,
            forceRefresh: true,
          );
      final availableProviders = controller.configuredSingleAgentProviders
          .where(capabilities.providers.contains)
          .toList(growable: false);
      final provider = selection == SingleAgentProvider.auto
          ? (availableProviders.isEmpty ? null : availableProviders.first)
          : (capabilities.providers.contains(selection) ? selection : null);
      final fallbackReason = provider == null
          ? (selection == SingleAgentProvider.auto
                ? appText(
                    '当前没有可用的 GoTaskService Provider。',
                    'No GoTaskService provider is currently available.',
                  )
                : appText(
                    '当前 GoTaskService 不支持 ${selection.label}。',
                    'GoTaskService does not currently support ${selection.label}.',
                  ))
          : null;
      if (provider == null && !routing.isAuto) {
        if (controller.singleAgentUsesAiChatFallbackForSession(sessionKey)) {
          appendSingleAgentFallbackStatusDesktopInternal(
            controller,
            sessionKey,
            fallbackReason,
          );
          await sendAiGatewaySingleAgentMessageDesktopInternal(
            controller,
            message,
            thinking: thinking,
            attachments: attachments,
            sessionKeyOverride: sessionKey,
            appendUserMessage: false,
            managePendingState: false,
          );
        } else {
          controller.appendAssistantThreadMessageInternal(
            sessionKey,
            GatewayChatMessage(
              id: controller.nextLocalMessageIdInternal(),
              role: 'assistant',
              text: singleAgentUnavailableLabelDesktopInternal(
                controller,
                sessionKey,
                fallbackReason,
              ),
              timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
              toolCallId: null,
              toolName: singleAgentRuntimeDebugToolNameDesktopInternal(
                controller,
                provider?.label ?? selection.label,
              ),
              stopReason: null,
              pending: false,
              error: false,
            ),
          );
        }
        return;
      }
      final effectiveProvider = provider ?? SingleAgentProvider.auto;

      appendSingleAgentRuntimeStatusDesktopInternal(
        controller,
        sessionKey,
        effectiveProvider,
      );
      final workingDirectory = controller
          .resolveSingleAgentWorkingDirectoryForSessionInternal(
            sessionKey,
            provider: provider,
          );
      if (workingDirectory == null || workingDirectory.trim().isEmpty) {
        final error = StateError(
          appText(
            '当前线程缺少可运行的工作路径，无法启动单机智能体。',
            'This thread does not have a runnable workspace path, so Single Agent cannot start.',
          ),
        );
        controller.appendAssistantThreadMessageInternal(
          sessionKey,
          assistantErrorMessageSingleAgentDesktopInternal(
            controller,
            error.message,
          ),
        );
        throw error;
      }

      final selectedSkills = controller
          .assistantSelectedSkillsForSession(sessionKey)
          .map((item) => item.label.trim().isNotEmpty ? item.label : item.key)
          .where((item) => item.trim().isNotEmpty)
          .toList(growable: false);
      final result = await controller.goTaskServiceClientInternal.executeTask(
        GoTaskServiceRequest(
          sessionId: sessionKey,
          threadId: sessionKey,
          target: AssistantExecutionTarget.singleAgent,
          prompt: message,
          workingDirectory: workingDirectory,
          model: controller.assistantModelForSession(sessionKey),
          thinking: thinking,
          selectedSkills: selectedSkills,
          inlineAttachments: attachments,
          localAttachments: localAttachments,
          aiGatewayBaseUrl: controller.aiGatewayUrl,
          aiGatewayApiKey: await controller.loadAiGatewayApiKey(),
          agentId: '',
          metadata: const <String, dynamic>{},
          routing: routing,
          provider: effectiveProvider,
        ),
        onUpdate: (update) {
          if (update.isDelta) {
            controller.appendAiGatewayStreamingTextInternal(
              sessionKey,
              update.text,
            );
            controller.notifyIfActiveInternal();
          }
        },
      );
      _applySingleAgentGoTaskResultDesktopInternal(
        controller,
        sessionKey: sessionKey,
        sessionTarget: sessionTarget,
        message: message,
        thinking: thinking,
        attachments: attachments,
        result: result,
      );
    } catch (error) {
      controller.clearAiGatewayStreamingTextInternal(sessionKey);
      controller.upsertTaskThreadInternal(
        sessionKey,
        lifecycleStatus: 'ready',
        lastRunAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
        lastResultCode: 'error',
        updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
      );
      controller.appendAssistantThreadMessageInternal(
        sessionKey,
        assistantErrorMessageSingleAgentDesktopInternal(
          controller,
          error.toString(),
        ),
      );
    } finally {
      controller.clearAiGatewayStreamingTextInternal(sessionKey);
      controller.aiGatewayPendingSessionKeysInternal.remove(sessionKey);
      controller.recomputeTasksInternal();
      controller.notifyIfActiveInternal();
    }
  });
}

void _applySingleAgentGoTaskResultDesktopInternal(
  AppController controller, {
  required String sessionKey,
  required AssistantExecutionTarget sessionTarget,
  required String message,
  required String thinking,
  required List<GatewayChatAttachmentPayload> attachments,
  required GoTaskServiceResult result,
}) {
  final resolvedRuntimeModel = result.resolvedModel.trim();
  final resolvedGatewayEntryState = goTaskServiceGatewayEntryState(
    requestedTarget: sessionTarget,
    result: result,
  );
  controller.upsertTaskThreadInternal(
    sessionKey,
    gatewayEntryState: resolvedGatewayEntryState,
    latestResolvedRuntimeModel: resolvedRuntimeModel,
    lifecycleStatus: 'ready',
    lastRunAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    lastResultCode: result.success ? 'success' : 'error',
    updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
  );
  _updateSingleAgentWorkspaceBindingFromResultDesktopInternal(
    controller,
    sessionKey,
    result,
  );
  controller.clearAiGatewayStreamingTextInternal(sessionKey);
  if (!result.success &&
      controller.singleAgentUsesAiChatFallbackForSession(sessionKey)) {
    appendSingleAgentFallbackStatusDesktopInternal(
      controller,
      sessionKey,
      result.errorMessage,
    );
    controller.upsertTaskThreadInternal(
      sessionKey,
      gatewayEntryState: 'only-chat',
      latestResolvedRuntimeModel: controller.resolvedAiGatewayModel,
      lifecycleStatus: 'ready',
      lastRunAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
      lastResultCode: 'fallback',
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
    unawaited(
      sendAiGatewaySingleAgentMessageDesktopInternal(
        controller,
        message,
        thinking: thinking,
        attachments: attachments,
        sessionKeyOverride: sessionKey,
        appendUserMessage: false,
        managePendingState: false,
      ),
    );
    return;
  }

  if (!result.success) {
    controller.appendAssistantThreadMessageInternal(
      sessionKey,
      assistantErrorMessageSingleAgentDesktopInternal(
        controller,
        appText(
          'GoTaskService 执行失败：${result.errorMessage}',
          'GoTaskService execution failed: ${result.errorMessage}',
        ),
      ),
    );
    return;
  }

  if (result.message.trim().isEmpty) {
    controller.appendAssistantThreadMessageInternal(
      sessionKey,
      assistantErrorMessageSingleAgentDesktopInternal(
        controller,
        appText(
          'GoTaskService 没有返回可显示的输出。',
          'GoTaskService returned no displayable output.',
        ),
      ),
    );
    return;
  }

  controller.appendAssistantThreadMessageInternal(
    sessionKey,
    GatewayChatMessage(
      id: controller.nextLocalMessageIdInternal(),
      role: 'assistant',
      text: result.message,
      timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
      toolCallId: null,
      toolName: null,
      stopReason: null,
      pending: false,
      error: false,
    ),
  );
}

void _updateSingleAgentWorkspaceBindingFromResultDesktopInternal(
  AppController controller,
  String sessionKey,
  GoTaskServiceResult result,
) {
  final resolvedWorkspaceKind = result.resolvedWorkspaceRefKind;
  final resolvedWorkingDirectory = result.resolvedWorkingDirectory.trim();
  if (resolvedWorkspaceKind == null || resolvedWorkingDirectory.isEmpty) {
    return;
  }
  final existingThread = controller.requireTaskThreadForSessionInternal(
    sessionKey,
  );
  controller.upsertTaskThreadInternal(
    sessionKey,
    workspaceBinding: WorkspaceBinding(
      workspaceId: existingThread.workspaceBinding.workspaceId,
      workspaceKind: resolvedWorkspaceKind == WorkspaceRefKind.remotePath
          ? WorkspaceKind.remoteFs
          : WorkspaceKind.localFs,
      workspacePath: resolvedWorkingDirectory,
      displayPath: resolvedWorkingDirectory,
      writable: existingThread.workspaceBinding.writable,
    ),
    updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
  );
}
