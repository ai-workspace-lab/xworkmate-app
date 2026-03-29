// ignore_for_file: unused_import, unnecessary_import

import 'dart:async';
import 'package:flutter/material.dart';
import '../i18n/app_language.dart';
import '../models/app_models.dart';
import '../runtime/assistant_artifacts.dart';
import '../runtime/go_agent_core_client.dart';
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
import 'app_controller_web_sessions.dart';
import 'app_controller_web_workspace.dart';
import 'app_controller_web_session_actions.dart';
import 'app_controller_web_gateway_config.dart';
import 'app_controller_web_gateway_relay.dart';
import 'app_controller_web_helpers.dart';

extension AppControllerWebGatewayChat on AppController {
  Future<void> sendMessage(
    String rawMessage, {
    String thinking = 'medium',
    List<GatewayChatAttachmentPayload> attachments =
        const <GatewayChatAttachmentPayload>[],
    List<String> selectedSkillLabels = const <String>[],
    bool useMultiAgent = false,
  }) async {
    final trimmed = rawMessage.trim();
    if (trimmed.isEmpty) {
      return;
    }
    await ensureWebTaskThreadBindingInternal(currentSessionKeyInternal);
    if (assistantWorkspacePathForSession(
      currentSessionKeyInternal,
    ).trim().isEmpty) {
      final error = StateError(
        appText(
          '当前线程缺少工作路径，无法运行。',
          'This thread has no workspace path, so it cannot run.',
        ),
      );
      lastAssistantErrorInternal = error.message.toString();
      notifyChangedInternal();
      throw error;
    }
    const maxAttachmentBytes = 10 * 1024 * 1024;
    final totalAttachmentBytes = attachments.fold<int>(
      0,
      (total, item) => total + base64SizeInternal(item.content),
    );
    if (totalAttachmentBytes > maxAttachmentBytes) {
      lastAssistantErrorInternal = appText(
        '附件总大小超过 10MB，请减少附件后重试。',
        'Attachments exceed the 10MB limit. Remove some files and try again.',
      );
      notifyChangedInternal();
      return;
    }
    final sessionKey = normalizedSessionKeyInternal(currentSessionKeyInternal);
    await enqueueThreadTurnInternal<void>(sessionKey, () async {
      lastAssistantErrorInternal = null;
      final target = assistantExecutionTargetForSession(sessionKey);
      final current =
          threadRecordsInternal[sessionKey] ??
          newRecordInternal(target: target);
      final nextMessages = <GatewayChatMessage>[
        ...current.messages,
        GatewayChatMessage(
          id: messageIdInternal(),
          role: 'user',
          text: trimmed,
          timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
          toolCallId: null,
          toolName: null,
          stopReason: null,
          pending: false,
          error: false,
        ),
      ];
      upsertThreadRecordInternal(
        sessionKey,
        messages: nextMessages,
        executionTarget: target,
        title: deriveThreadTitleInternal(current.title, nextMessages),
        updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
      );
      pendingSessionKeysInternal.add(sessionKey);
      await persistThreadsInternal();
      notifyChangedInternal();

      try {
        if (useMultiAgent && settingsInternal.multiAgent.enabled) {
          await runMultiAgentCollaboration(
            rawPrompt: trimmed,
            composedPrompt: trimmed,
            attachments: attachments,
            selectedSkillLabels: selectedSkillLabels,
          );
          return;
        }
        if (target == AssistantExecutionTarget.singleAgent) {
          final provider = singleAgentProviderForSession(sessionKey);
          if (provider == SingleAgentProvider.auto) {
            if (!canUseAiGatewayConversation) {
              throw Exception(
                appText(
                  '请先在 Settings 配置单机智能体所需的 LLM API Endpoint、LLM API Token 和默认模型。',
                  'Configure the Single Agent LLM API Endpoint, LLM API Token, and default model first.',
                ),
              );
            }
            final directPrompt = attachments.isEmpty
                ? trimmed
                : augmentPromptWithAttachmentsInternal(trimmed, attachments);
            final directHistory = List<GatewayChatMessage>.from(nextMessages);
            if (directHistory.isNotEmpty) {
              final last = directHistory.removeLast();
              directHistory.add(
                last.copyWith(text: directPrompt, role: 'user', error: false),
              );
            }
            final reply = await aiGatewayClientInternal.completeChat(
              baseUrl: settingsInternal.aiGateway.baseUrl,
              apiKey: aiGatewayApiKeyCacheInternal,
              model: assistantModelForSession(sessionKey),
              history: directHistory,
            );
            appendAssistantMessageInternal(
              sessionKey: sessionKey,
              text: reply,
              error: false,
            );
          } else {
            await executeGoAgentCoreRunInternal(
              sessionKey: sessionKey,
              prompt: trimmed,
              target: target,
              provider: provider,
              model: assistantModelForSession(sessionKey),
              thinking: thinking,
              attachments: attachments,
              selectedSkillLabels: selectedSkillLabels,
            );
          }
        } else {
          await executeGoAgentCoreRunInternal(
            sessionKey: sessionKey,
            prompt: trimmed,
            target: target,
            provider: SingleAgentProvider.auto,
            model: assistantModelForSession(sessionKey),
            thinking: thinking,
            attachments: attachments,
            selectedSkillLabels: selectedSkillLabels,
          );
        }
      } catch (error) {
        appendAssistantMessageInternal(
          sessionKey: sessionKey,
          text: error.toString(),
          error: true,
        );
        lastAssistantErrorInternal = error.toString();
        pendingSessionKeysInternal.remove(sessionKey);
        streamingTextBySessionInternal.remove(sessionKey);
        await persistThreadsInternal();
        notifyChangedInternal();
      }
    });
  }

  Future<void> runMultiAgentCollaboration({
    required String rawPrompt,
    required String composedPrompt,
    required List<GatewayChatAttachmentPayload> attachments,
    required List<String> selectedSkillLabels,
  }) async {
    final sessionKey = normalizedSessionKeyInternal(currentSessionKeyInternal);
    await enqueueThreadTurnInternal<void>(sessionKey, () async {
      multiAgentRunPendingInternal = true;
      acpBusyInternal = true;
      pendingSessionKeysInternal.add(sessionKey);
      notifyChangedInternal();
      try {
        final result = await goAgentCoreClientInternal.executeSession(
          GoAgentCoreSessionRequest(
            sessionId: sessionKey,
            threadId: sessionKey,
            target: assistantExecutionTargetForSession(sessionKey),
            prompt: composedPrompt,
            workingDirectory: assistantWorkspacePathForSession(sessionKey),
            model: assistantModelForSession(sessionKey),
            thinking: 'medium',
            selectedSkills: selectedSkillLabels,
            inlineAttachments: attachments,
            localAttachments: const <CollaborationAttachment>[],
            aiGatewayBaseUrl: settingsInternal.aiGateway.baseUrl.trim(),
            aiGatewayApiKey: aiGatewayApiKeyCacheInternal.trim(),
            agentId: selectedAgentId,
            metadata: const <String, dynamic>{},
            multiAgent: true,
          ),
          onUpdate: (update) {
            if (update.isDelta) {
              appendStreamingTextInternal(sessionKey, update.text);
              notifyChangedInternal();
            }
          },
        );
        final summaryText = result.message.trim().isNotEmpty
            ? result.message.trim()
            : appText(
                '多智能体协作已完成。',
                'Multi-agent collaboration completed.',
              );
        appendAssistantMessageInternal(
          sessionKey: sessionKey,
          text: summaryText,
          error: false,
        );
      } catch (error) {
        appendAssistantMessageInternal(
          sessionKey: sessionKey,
          text: error.toString(),
          error: true,
        );
        lastAssistantErrorInternal = error.toString();
      } finally {
        multiAgentRunPendingInternal = false;
        acpBusyInternal = false;
        pendingSessionKeysInternal.remove(sessionKey);
        clearStreamingTextInternal(sessionKey);
        await persistThreadsInternal();
        notifyChangedInternal();
      }
    });
  }

  Future<void> selectDirectModel(String model) async {
    final trimmed = model.trim();
    if (trimmed.isEmpty) {
      return;
    }
    await selectAssistantModel(trimmed);
    settingsInternal = settingsInternal.copyWith(defaultModel: trimmed);
    await persistSettingsInternal();
    notifyChangedInternal();
  }

  Future<void> executeGoAgentCoreRunInternal({
    required String sessionKey,
    required String prompt,
    required AssistantExecutionTarget target,
    required SingleAgentProvider provider,
    required String model,
    required String thinking,
    required List<GatewayChatAttachmentPayload> attachments,
    required List<String> selectedSkillLabels,
  }) async {
    final selectedSkills = selectedSkillLabels
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    final result = await goAgentCoreClientInternal.executeSession(
      GoAgentCoreSessionRequest(
        sessionId: sessionKey,
        threadId: sessionKey,
        target: target,
        prompt: prompt,
        workingDirectory: assistantWorkspacePathForSession(sessionKey),
        model: model,
        thinking: thinking,
        selectedSkills: selectedSkills,
        inlineAttachments: attachments,
        localAttachments: const <CollaborationAttachment>[],
        aiGatewayBaseUrl: settingsInternal.aiGateway.baseUrl.trim(),
        aiGatewayApiKey: aiGatewayApiKeyCacheInternal.trim(),
        agentId: selectedAgentId,
        metadata: <String, dynamic>{
          if (selectedSkills.isNotEmpty) 'selectedSkills': selectedSkills,
        },
        provider: provider,
      ),
      onUpdate: (update) {
        if (update.isDelta) {
          appendStreamingTextInternal(sessionKey, update.text);
          notifyChangedInternal();
        }
      },
    );
    final message = result.message.trim();
    if (!result.success && result.errorMessage.trim().isNotEmpty) {
      throw Exception(result.errorMessage.trim());
    }
    if (message.isEmpty) {
      throw Exception(
        appText(
          'Go Agent-core 没有返回可显示的输出。',
          'Go Agent-core returned no displayable output.',
        ),
      );
    }
    appendAssistantMessageInternal(
      sessionKey: sessionKey,
      text: message,
      error: false,
    );
    clearStreamingTextInternal(sessionKey);
  }
}
