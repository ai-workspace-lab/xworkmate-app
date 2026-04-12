// ignore_for_file: unused_import, unnecessary_import

import 'dart:async';
import 'package:flutter/material.dart';
import '../i18n/app_language.dart';
import '../models/app_models.dart';
import '../runtime/desktop_thread_artifact_sync.dart';
import '../runtime/go_task_service_client.dart';
import '../runtime/runtime_models.dart';
import 'app_controller_desktop_core.dart';
import 'app_controller_desktop_external_acp_routing.dart';
import 'app_controller_desktop_runtime_helpers.dart';
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
      final effectiveProvider =
          controller.resolvedSingleAgentProviderInternal(selection) ??
          selection;
      final preflightWorkingDirectory = controller
          .resolveSingleAgentWorkingDirectoryForSessionInternal(sessionKey);
      if (preflightWorkingDirectory == null ||
          preflightWorkingDirectory.trim().isEmpty) {
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
      final unavailableReason =
          controller.singleAgentShouldSuggestAcpSwitchForSession(sessionKey)
          ? singleAgentUnavailableLabelDesktopInternal(
              controller,
              sessionKey,
              null,
            )
          : controller.singleAgentNeedsAiGatewayConfigurationForSession(
              sessionKey,
            )
          ? singleAgentUnavailableLabelDesktopInternal(
              controller,
              sessionKey,
              appText(
                'Bridge 当前没有同步到可用 Provider。',
                'The bridge does not currently have any synced providers.',
              ),
            )
          : controller.resolveExternalAcpEndpointForTargetInternal(
                  AssistantExecutionTarget.singleAgent,
                ) ==
                null
          ? appText(
              'Bridge ACP 入口当前不可用。',
              'The bridge ACP entrypoint is currently unavailable.',
            )
          : null;
      if (unavailableReason != null) {
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
            unavailableReason,
          ),
        );
        return;
      }

      final aiGatewayApiKey = await controller.loadAiGatewayApiKey();
      if (!effectiveProvider.isUnspecified) {
        appendSingleAgentRuntimeStatusDesktopInternal(
          controller,
          sessionKey,
          effectiveProvider,
        );
      }
      final workingDirectory = controller
          .resolveSingleAgentWorkingDirectoryForSessionInternal(
            sessionKey,
            provider: effectiveProvider.isUnspecified
                ? null
                : effectiveProvider,
          );
      final resolvedWorkingDirectory =
          workingDirectory == null || workingDirectory.trim().isEmpty
          ? preflightWorkingDirectory
          : workingDirectory;

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
          workingDirectory: resolvedWorkingDirectory,
          model: controller.assistantModelForSession(sessionKey),
          thinking: thinking,
          selectedSkills: selectedSkills,
          inlineAttachments: attachments,
          localAttachments: localAttachments,
          aiGatewayBaseUrl: controller.aiGatewayUrl,
          aiGatewayApiKey: aiGatewayApiKey,
          agentId: '',
          metadata: const <String, dynamic>{},
          routing: routing,
          routingHint: 'single-agent',
          provider: effectiveProvider,
          remoteWorkingDirectoryHint:
              controller
                  .requireTaskThreadForSessionInternal(sessionKey)
                  .lastRemoteWorkingDirectory ??
              '',
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
      await _applySingleAgentGoTaskResultDesktopInternal(
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
          controller.gatewayExecutionErrorLabelInternal(
            error,
            target: sessionTarget,
          ),
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

Future<void> _applySingleAgentGoTaskResultDesktopInternal(
  AppController controller, {
  required String sessionKey,
  required AssistantExecutionTarget sessionTarget,
  required String message,
  required String thinking,
  required List<GatewayChatAttachmentPayload> attachments,
  required GoTaskServiceResult result,
}) async {
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
    lastRemoteWorkingDirectory: result.remoteWorkingDirectory.trim().isEmpty
        ? null
        : result.remoteWorkingDirectory.trim(),
    lastRemoteWorkspaceRefKind: result.remoteWorkspaceRefKind,
    updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
  );
  await _persistSingleAgentArtifactsDesktopInternal(
    controller,
    sessionKey,
    result,
  );
  controller.clearAiGatewayStreamingTextInternal(sessionKey);
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

Future<void> _persistSingleAgentArtifactsDesktopInternal(
  AppController controller,
  String sessionKey,
  GoTaskServiceResult result,
) => controller.persistGoTaskArtifactsForSessionInternal(sessionKey, result);
