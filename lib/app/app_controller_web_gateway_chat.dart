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
    syncThreadWorkspaceRefInternal(currentSessionKeyInternal);
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
            await sendSingleAgentViaAcpInternal(
              sessionKey: sessionKey,
              prompt: trimmed,
              provider: provider,
              model: assistantModelForSession(sessionKey),
              thinking: thinking,
              attachments: attachments,
              selectedSkillLabels: selectedSkillLabels,
            );
          }
        } else {
          final expectedMode = target == AssistantExecutionTarget.local
              ? RuntimeConnectionMode.local
              : RuntimeConnectionMode.remote;
          if (connection.status != RuntimeConnectionStatus.connected ||
              connection.mode != expectedMode) {
            throw Exception(
              appText(
                '当前线程目标网关未连接。',
                'The gateway for this thread target is not connected.',
              ),
            );
          }
          await relayClientInternal.sendChat(
            sessionKey: sessionKey,
            message: attachments.isEmpty
                ? trimmed
                : augmentPromptWithAttachmentsInternal(trimmed, attachments),
            thinking: thinking,
            attachments: attachments,
            metadata: <String, dynamic>{
              if (selectedSkillLabels.isNotEmpty)
                'selectedSkills': selectedSkillLabels,
            },
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
        final target = assistantExecutionTargetForSession(sessionKey);
        final endpoint = acpEndpointForTargetInternal(
          target == AssistantExecutionTarget.singleAgent
              ? AssistantExecutionTarget.remote
              : target,
        );
        if (endpoint == null) {
          throw Exception(
            appText(
              '当前线程的 ACP 端点不可用，请先配置并连接 Gateway。',
              'ACP endpoint is unavailable for this thread. Configure and connect Gateway first.',
            ),
          );
        }
        await refreshAcpCapabilitiesInternal(endpoint);
        final inlineAttachments = attachments
            .map(
              (item) => <String, dynamic>{
                'name': item.fileName,
                'mimeType': item.mimeType,
                'content': item.content,
                'sizeBytes': base64SizeInternal(item.content),
              },
            )
            .toList(growable: false);
        final params = <String, dynamic>{
          'sessionId': sessionKey,
          'threadId': sessionKey,
          'mode': 'multi-agent',
          'taskPrompt': composedPrompt,
          'workingDirectory': '',
          'selectedSkills': selectedSkillLabels,
          'attachments': attachments
              .map(
                (item) => <String, dynamic>{
                  'name': item.fileName,
                  'description': item.mimeType,
                  'path': '',
                },
              )
              .toList(growable: false),
          if (inlineAttachments.isNotEmpty)
            'inlineAttachments': inlineAttachments,
          'aiGatewayBaseUrl': settingsInternal.aiGateway.baseUrl.trim(),
          'aiGatewayApiKey': aiGatewayApiKeyCacheInternal.trim(),
        };
        String? summary;
        final response = await requestAcpSessionMessageInternal(
          endpoint: endpoint,
          params: params,
          hasInlineAttachments: inlineAttachments.isNotEmpty,
          onNotification: (notification) {
            final update = acpSessionUpdateFromNotificationInternal(
              notification,
              sessionKey: sessionKey,
            );
            if (update == null) {
              return;
            }
            if (update.type == 'delta' && update.text.isNotEmpty) {
              appendStreamingTextInternal(sessionKey, update.text);
              notifyChangedInternal();
              return;
            }
            if (update.error && update.message.isNotEmpty) {
              summary = update.message;
            }
            if (update.type == 'done' &&
                summary == null &&
                update.message.isNotEmpty) {
              summary = update.message;
            }
          },
        );
        final result = castMapInternal(response['result']);
        final summaryText = summary?.trim().isNotEmpty == true
            ? summary!.trim()
            : result['summary']?.toString().trim() ??
                  result['message']?.toString().trim() ??
                  appText('多智能体协作已完成。', 'Multi-agent collaboration completed.');
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

  Future<void> sendSingleAgentViaAcpInternal({
    required String sessionKey,
    required String prompt,
    required SingleAgentProvider provider,
    required String model,
    required String thinking,
    required List<GatewayChatAttachmentPayload> attachments,
    required List<String> selectedSkillLabels,
  }) async {
    final endpoint = acpEndpointForTargetInternal(
      AssistantExecutionTarget.remote,
    );
    if (endpoint == null) {
      throw Exception(
        appText(
          'Remote ACP 端点不可用，请先配置 Remote Gateway。',
          'Remote ACP endpoint is unavailable. Configure Remote Gateway first.',
        ),
      );
    }
    await refreshAcpCapabilitiesInternal(endpoint);
    if (acpCapabilitiesInternal.providers.isNotEmpty &&
        !acpCapabilitiesInternal.providers.any(
          (item) => item.providerId == provider.providerId,
        )) {
      throw Exception(
        appText(
          '当前 ACP 不支持所选 Provider：${provider.label}',
          'Current ACP does not support provider: ${provider.label}',
        ),
      );
    }
    final selectedSkills = selectedSkillLabels
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    final inlineAttachments = attachments
        .map(
          (item) => <String, dynamic>{
            'name': item.fileName,
            'mimeType': item.mimeType,
            'content': item.content,
            'sizeBytes': base64SizeInternal(item.content),
          },
        )
        .toList(growable: false);
    final params = <String, dynamic>{
      'sessionId': sessionKey,
      'threadId': sessionKey,
      'mode': 'single-agent',
      'provider': provider.providerId,
      'model': model.trim(),
      'thinking': thinking,
      'taskPrompt': prompt,
      'selectedSkills': selectedSkills,
      'attachments': attachments
          .map(
            (item) => <String, dynamic>{
              'name': item.fileName,
              'description': item.mimeType,
              'path': '',
            },
          )
          .toList(growable: false),
      if (inlineAttachments.isNotEmpty) 'inlineAttachments': inlineAttachments,
      'aiGatewayBaseUrl': settingsInternal.aiGateway.baseUrl.trim(),
      'aiGatewayApiKey': aiGatewayApiKeyCacheInternal.trim(),
    };

    String streamingText = '';
    String? completionText;
    String? errorText;
    final response = await requestAcpSessionMessageInternal(
      endpoint: endpoint,
      params: params,
      hasInlineAttachments: inlineAttachments.isNotEmpty,
      onNotification: (notification) {
        final update = acpSessionUpdateFromNotificationInternal(
          notification,
          sessionKey: sessionKey,
        );
        if (update == null) {
          return;
        }
        if (update.type == 'delta' && update.text.isNotEmpty) {
          streamingText += update.text;
          appendStreamingTextInternal(sessionKey, update.text);
          notifyChangedInternal();
          return;
        }
        if (update.error && update.message.isNotEmpty) {
          errorText = update.message;
          return;
        }
        if (update.type == 'done' && update.message.isNotEmpty) {
          completionText = update.message;
        }
      },
    );

    final result = castMapInternal(response['result']);
    final message =
        (completionText?.trim().isNotEmpty == true
                ? completionText!.trim()
                : (streamingText.trim().isNotEmpty
                      ? streamingText.trim()
                      : (result['message']?.toString().trim() ?? '')))
            .trim();

    if (errorText?.trim().isNotEmpty == true) {
      throw Exception(errorText!.trim());
    }
    if (message.isEmpty) {
      throw Exception(
        appText(
          'Single Agent 没有返回可显示的输出。',
          'Single Agent returned no displayable output.',
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
