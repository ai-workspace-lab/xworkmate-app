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
import '../runtime/go_agent_core_client.dart';
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
import 'app_controller_desktop_thread_sessions.dart';
import 'app_controller_desktop_thread_actions.dart';
import 'app_controller_desktop_workspace_execution.dart';
import 'app_controller_desktop_settings_runtime.dart';
import 'app_controller_desktop_thread_storage.dart';
import 'app_controller_desktop_skill_permissions.dart';
import 'app_controller_desktop_runtime_helpers.dart';

extension AppControllerDesktopSingleAgent on AppController {
  Future<void> sendSingleAgentMessageInternal(
    String message, {
    required String thinking,
    required List<GatewayChatAttachmentPayload> attachments,
    required List<CollaborationAttachment> localAttachments,
  }) async {
    final sessionKey = normalizedAssistantSessionKeyInternal(
      sessionsControllerInternal.currentSessionKey,
    );
    final trimmed = message.trim();
    if (trimmed.isEmpty && attachments.isEmpty) {
      return;
    }
    await enqueueThreadTurnInternal<void>(sessionKey, () async {
      final userText = trimmed.isEmpty ? 'See attached.' : trimmed;
      appendAssistantThreadMessageInternal(
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
      );
      aiGatewayPendingSessionKeysInternal.add(sessionKey);
      recomputeTasksInternal();
      notifyIfActiveInternal();

      try {
        final selection = singleAgentProviderForSession(sessionKey);
        final capabilities = await goAgentCoreClientInternal.loadCapabilities(
          target: AssistantExecutionTarget.singleAgent,
          forceRefresh: true,
        );
        final availableProviders = configuredSingleAgentProviders
            .where(capabilities.providers.contains)
            .toList(growable: false);
        final provider = selection == SingleAgentProvider.auto
            ? (availableProviders.isEmpty ? null : availableProviders.first)
            : (capabilities.providers.contains(selection) ? selection : null);
        final fallbackReason = provider == null
            ? (selection == SingleAgentProvider.auto
                  ? appText(
                      '当前没有可用的 Go Agent-core Provider。',
                      'No Go Agent-core provider is currently available.',
                    )
                  : appText(
                      '当前 Go Agent-core 不支持 ${selection.label}。',
                      'Go Agent-core does not currently support ${selection.label}.',
                    ))
            : null;
        if (provider == null) {
          if (singleAgentUsesAiChatFallbackForSession(sessionKey)) {
            appendSingleAgentFallbackStatusMessageInternal(
              sessionKey,
              fallbackReason,
            );
            await sendAiGatewayMessageInternal(
              message,
              thinking: thinking,
              attachments: attachments,
              sessionKeyOverride: sessionKey,
              appendUserMessage: false,
              managePendingState: false,
            );
          } else {
            appendAssistantThreadMessageInternal(
              sessionKey,
              GatewayChatMessage(
                id: nextLocalMessageIdInternal(),
                role: 'assistant',
                text: singleAgentUnavailableLabelInternal(
                  sessionKey,
                  fallbackReason,
                ),
                timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
                toolCallId: null,
                toolName: singleAgentRuntimeDebugToolNameInternal(
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

        appendSingleAgentRuntimeStatusMessageInternal(sessionKey, provider);
        final workingDirectory =
            resolveSingleAgentWorkingDirectoryForSessionInternal(
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
          appendAssistantThreadMessageInternal(
            sessionKey,
            assistantErrorMessageInternal(error.message),
          );
          throw error;
        }

        final selectedSkills = assistantSelectedSkillsForSession(sessionKey)
            .map((item) => item.label.trim().isNotEmpty ? item.label : item.key)
            .where((item) => item.trim().isNotEmpty)
            .toList(growable: false);
        final result = await goAgentCoreClientInternal.executeSession(
          GoAgentCoreSessionRequest(
            sessionId: sessionKey,
            threadId: sessionKey,
            target: AssistantExecutionTarget.singleAgent,
            prompt: message,
            workingDirectory: workingDirectory,
            model: assistantModelForSession(sessionKey),
            thinking: thinking,
            selectedSkills: selectedSkills,
            inlineAttachments: attachments,
            localAttachments: localAttachments,
            aiGatewayBaseUrl: aiGatewayUrl,
            aiGatewayApiKey: await loadAiGatewayApiKey(),
            agentId: '',
            metadata: const <String, dynamic>{},
            provider: provider,
          ),
          onUpdate: (update) {
            if (update.isDelta) {
              appendAiGatewayStreamingTextInternal(sessionKey, update.text);
              notifyIfActiveInternal();
            }
          },
        );
        final resolvedRuntimeModel = result.resolvedModel.trim();
        if (resolvedRuntimeModel.isNotEmpty) {
          singleAgentRuntimeModelBySessionInternal[sessionKey] =
              resolvedRuntimeModel;
        }
        final resolvedWorkspaceKind = result.resolvedWorkspaceRefKind;
        final resolvedWorkingDirectory = result.resolvedWorkingDirectory.trim();
        if (resolvedWorkspaceKind != null &&
            resolvedWorkingDirectory.isNotEmpty &&
            resolvedWorkspaceKind != WorkspaceRefKind.localPath) {
          upsertTaskThreadInternal(
            sessionKey,
            workspaceRef: resolvedWorkingDirectory,
            workspaceRefKind: resolvedWorkspaceKind,
            updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
          );
        }
        clearAiGatewayStreamingTextInternal(sessionKey);
        if (!result.success &&
            singleAgentUsesAiChatFallbackForSession(sessionKey)) {
          if (singleAgentUsesAiChatFallbackForSession(sessionKey)) {
            appendSingleAgentFallbackStatusMessageInternal(
              sessionKey,
              result.errorMessage,
            );
            await sendAiGatewayMessageInternal(
              message,
              thinking: thinking,
              attachments: attachments,
              sessionKeyOverride: sessionKey,
              appendUserMessage: false,
              managePendingState: false,
            );
          } else {
            appendAssistantThreadMessageInternal(
              sessionKey,
              GatewayChatMessage(
                id: nextLocalMessageIdInternal(),
                role: 'assistant',
                text: singleAgentUnavailableLabelInternal(
                  sessionKey,
                  result.errorMessage,
                ),
                timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
                toolCallId: null,
                toolName: singleAgentRuntimeDebugToolNameInternal(
                  provider.label,
                ),
                stopReason: null,
                pending: false,
                error: false,
              ),
            );
          }
          return;
        }

        if (!result.success) {
          appendAssistantThreadMessageInternal(
            sessionKey,
            assistantErrorMessageInternal(
              appText(
                'Go Agent-core 执行失败：${result.errorMessage}',
                'Go Agent-core execution failed: ${result.errorMessage}',
              ),
            ),
          );
          return;
        }

        if (result.message.trim().isEmpty) {
          appendAssistantThreadMessageInternal(
            sessionKey,
            assistantErrorMessageInternal(
              appText(
                'Go Agent-core 没有返回可显示的输出。',
                'Go Agent-core returned no displayable output.',
              ),
            ),
          );
          return;
        }

        appendAssistantThreadMessageInternal(
          sessionKey,
          GatewayChatMessage(
            id: nextLocalMessageIdInternal(),
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
      } catch (error) {
        clearAiGatewayStreamingTextInternal(sessionKey);
        appendAssistantThreadMessageInternal(
          sessionKey,
          assistantErrorMessageInternal(error.toString()),
        );
      } finally {
        clearAiGatewayStreamingTextInternal(sessionKey);
        aiGatewayPendingSessionKeysInternal.remove(sessionKey);
        recomputeTasksInternal();
        notifyIfActiveInternal();
      }
    });
  }

  Future<void> sendAiGatewayMessageInternal(
    String message, {
    required String thinking,
    required List<GatewayChatAttachmentPayload> attachments,
    String? sessionKeyOverride,
    bool appendUserMessage = true,
    bool managePendingState = true,
  }) async {
    final sessionKey = normalizedAssistantSessionKeyInternal(
      sessionKeyOverride ?? sessionsControllerInternal.currentSessionKey,
    );
    final trimmed = message.trim();
    if (trimmed.isEmpty && attachments.isEmpty) {
      return;
    }

    final baseUrl = normalizeAiGatewayBaseUrlInternal(
      settings.aiGateway.baseUrl,
    );
    if (baseUrl == null) {
      appendAssistantThreadMessageInternal(
        sessionKey,
        assistantErrorMessageInternal(
          appText(
            'LLM API Endpoint 未配置，无法发送对话。',
            'LLM API Endpoint is not configured, so the conversation could not be sent.',
          ),
        ),
      );
      return;
    }

    final apiKey = await loadAiGatewayApiKey();
    if (apiKey.isEmpty) {
      appendAssistantThreadMessageInternal(
        sessionKey,
        assistantErrorMessageInternal(
          appText(
            'LLM API Token 未配置，无法发送对话。',
            'LLM API Token is not configured, so the conversation could not be sent.',
          ),
        ),
      );
      return;
    }

    final model = resolvedAiGatewayModel;
    if (model.isEmpty) {
      appendAssistantThreadMessageInternal(
        sessionKey,
        assistantErrorMessageInternal(
          appText(
            '当前没有可用的 LLM API 对话模型。请先在 设置 -> 集成 中同步并选择可用模型。',
            'No LLM API chat model is available yet. Sync and select a supported model in Settings -> Integrations first.',
          ),
        ),
      );
      return;
    }

    if (appendUserMessage) {
      final userText = trimmed.isEmpty ? 'See attached.' : trimmed;
      appendAssistantThreadMessageInternal(
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
      );
    }
    if (managePendingState) {
      aiGatewayPendingSessionKeysInternal.add(sessionKey);
      recomputeTasksInternal();
      notifyIfActiveInternal();
    }

    try {
      final assistantText = await requestAiGatewayCompletionInternal(
        baseUrl: baseUrl,
        apiKey: apiKey,
        model: model,
        thinking: thinking,
        sessionKey: sessionKey,
      );
      appendAssistantThreadMessageInternal(
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
      );
    } on AiGatewayAbortExceptionInternal catch (error) {
      final partial = error.partialText.trim();
      if (partial.isNotEmpty) {
        appendAssistantThreadMessageInternal(
          sessionKey,
          GatewayChatMessage(
            id: nextLocalMessageIdInternal(),
            role: 'assistant',
            text: partial,
            timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
            toolCallId: null,
            toolName: null,
            stopReason: 'aborted',
            pending: false,
            error: false,
          ),
        );
      }
    } catch (error) {
      appendAssistantThreadMessageInternal(
        sessionKey,
        assistantErrorMessageInternal(aiGatewayErrorLabelInternal(error)),
      );
    } finally {
      aiGatewayStreamingClientsInternal.remove(sessionKey);
      clearAiGatewayStreamingTextInternal(sessionKey);
      if (managePendingState) {
        aiGatewayPendingSessionKeysInternal.remove(sessionKey);
        recomputeTasksInternal();
        notifyIfActiveInternal();
      }
    }
  }

  Future<String> requestAiGatewayCompletionInternal({
    required Uri baseUrl,
    required String apiKey,
    required String model,
    required String thinking,
    required String sessionKey,
  }) async {
    final uri = aiGatewayChatUriInternal(baseUrl);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    aiGatewayStreamingClientsInternal[sessionKey] = client;
    try {
      final request = await client
          .postUrl(uri)
          .timeout(const Duration(seconds: 20));
      request.headers.set(
        HttpHeaders.acceptHeader,
        'text/event-stream, application/json',
      );
      request.headers.set(
        HttpHeaders.contentTypeHeader,
        'application/json; charset=utf-8',
      );
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
      request.headers.set('x-api-key', apiKey);
      final payload = <String, dynamic>{
        'model': model,
        'stream': true,
        'messages': buildAiGatewayRequestMessagesInternal(sessionKey),
      };
      final normalizedThinking = thinking.trim().toLowerCase();
      if (normalizedThinking.isNotEmpty && normalizedThinking != 'off') {
        payload['reasoning_effort'] = normalizedThinking;
      }
      request.add(utf8.encode(jsonEncode(payload)));
      final response = await request.close().timeout(
        const Duration(seconds: 60),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body = await response.transform(utf8.decoder).join();
        throw AiGatewayChatExceptionInternal(
          formatAiGatewayHttpErrorInternal(
            response.statusCode,
            extractAiGatewayErrorDetailInternal(body),
          ),
        );
      }
      final contentType =
          response.headers.contentType?.mimeType.toLowerCase() ??
          response.headers
              .value(HttpHeaders.contentTypeHeader)
              ?.toLowerCase() ??
          '';
      if (contentType.contains('text/event-stream')) {
        final streamed = await readAiGatewayStreamingResponseInternal(
          response: response,
          sessionKey: sessionKey,
        );
        if (streamed.trim().isEmpty) {
          throw const FormatException('Missing assistant content');
        }
        return streamed.trim();
      }
      return await readAiGatewayJsonCompletionInternal(response);
    } catch (error) {
      if (consumeAiGatewayAbortInternal(sessionKey)) {
        throw AiGatewayAbortExceptionInternal(
          aiGatewayStreamingTextBySessionInternal[sessionKey] ?? '',
        );
      }
      rethrow;
    } finally {
      aiGatewayStreamingClientsInternal.remove(sessionKey);
      client.close(force: true);
    }
  }

  List<Map<String, String>> buildAiGatewayRequestMessagesInternal(
    String sessionKey,
  ) {
    final history = <GatewayChatMessage>[
      ...(gatewayHistoryCacheInternal[sessionKey] ??
          const <GatewayChatMessage>[]),
      ...(assistantThreadMessagesInternal[sessionKey] ??
          const <GatewayChatMessage>[]),
    ];
    return history
        .where((message) {
          final role = message.role.trim().toLowerCase();
          return (role == 'user' || role == 'assistant') &&
              (message.toolName ?? '').trim().isEmpty &&
              message.text.trim().isNotEmpty;
        })
        .map(
          (message) => <String, String>{
            'role': message.role.trim().toLowerCase() == 'assistant'
                ? 'assistant'
                : 'user',
            'content': message.text.trim(),
          },
        )
        .toList(growable: false);
  }

  Future<String> readAiGatewayJsonCompletionInternal(
    HttpClientResponse response,
  ) async {
    final body = await response.transform(utf8.decoder).join();
    final decoded = jsonDecode(extractFirstJsonDocumentInternal(body));
    final assistantText = extractAiGatewayAssistantTextInternal(decoded);
    if (assistantText.trim().isEmpty) {
      throw const FormatException('Missing assistant content');
    }
    return assistantText.trim();
  }

  Future<String> readAiGatewayStreamingResponseInternal({
    required HttpClientResponse response,
    required String sessionKey,
  }) async {
    final buffer = StringBuffer();
    final eventLines = <String>[];

    void processEvent(String payload) {
      final trimmed = payload.trim();
      if (trimmed.isEmpty) {
        return;
      }
      if (trimmed == '[DONE]') {
        return;
      }
      final deltaText = extractAiGatewayStreamTextInternal(trimmed);
      if (deltaText.isEmpty) {
        return;
      }
      final current = buffer.toString();
      if (current.isEmpty || deltaText == current) {
        buffer
          ..clear()
          ..write(deltaText);
      } else if (deltaText.startsWith(current)) {
        buffer
          ..clear()
          ..write(deltaText);
      } else {
        buffer.write(deltaText);
      }
      setAiGatewayStreamingTextInternal(sessionKey, buffer.toString());
    }

    await for (final line
        in response.transform(utf8.decoder).transform(const LineSplitter())) {
      if (consumeAiGatewayAbortInternal(sessionKey)) {
        throw AiGatewayAbortExceptionInternal(buffer.toString());
      }
      if (line.isEmpty) {
        if (eventLines.isNotEmpty) {
          processEvent(eventLines.join('\n'));
          eventLines.clear();
        }
        continue;
      }
      if (line.startsWith('data:')) {
        eventLines.add(line.substring(5).trimLeft());
      }
    }

    if (eventLines.isNotEmpty) {
      processEvent(eventLines.join('\n'));
    }

    return buffer.toString();
  }

  String extractAiGatewayStreamTextInternal(String payload) {
    final decoded = jsonDecode(extractFirstJsonDocumentInternal(payload));
    final map = asMap(decoded);
    final choices = asList(map['choices']);
    if (choices.isNotEmpty) {
      final firstChoice = asMap(choices.first);
      final delta = asMap(firstChoice['delta']);
      final deltaContent = extractAiGatewayContentInternal(delta['content']);
      if (deltaContent.isNotEmpty) {
        return deltaContent;
      }
    }
    return extractAiGatewayAssistantTextInternal(decoded);
  }

  Future<void> abortAiGatewayRunInternal(String sessionKey) async {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    aiGatewayAbortedSessionKeysInternal.add(normalizedSessionKey);
    final client = aiGatewayStreamingClientsInternal.remove(
      normalizedSessionKey,
    );
    if (client != null) {
      try {
        client.close(force: true);
      } catch (_) {
        // Best effort only.
      }
    }
    aiGatewayPendingSessionKeysInternal.remove(normalizedSessionKey);
    clearAiGatewayStreamingTextInternal(normalizedSessionKey);
    recomputeTasksInternal();
    notifyIfActiveInternal();
  }

  bool consumeAiGatewayAbortInternal(String sessionKey) {
    return aiGatewayAbortedSessionKeysInternal.remove(
      normalizedAssistantSessionKeyInternal(sessionKey),
    );
  }

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

  String? singleAgentRuntimeDebugToolNameInternal(String label) {
    if (!showsSingleAgentRuntimeDebugMessagesInternal) {
      return null;
    }
    final trimmed = label.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  void appendSingleAgentRuntimeStatusMessageInternal(
    String sessionKey,
    SingleAgentProvider provider,
  ) {
    if (!showsSingleAgentRuntimeDebugMessagesInternal) {
      return;
    }
    appendAssistantThreadMessageInternal(
      sessionKey,
      GatewayChatMessage(
        id: nextLocalMessageIdInternal(),
        role: 'assistant',
        text: appText(
          '单机智能体已切换到 ${provider.label} 执行当前任务。',
          'Single Agent is using ${provider.label} for this task.',
        ),
        timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
        toolCallId: null,
        toolName: provider.label,
        stopReason: null,
        pending: false,
        error: false,
      ),
    );
  }

  void appendSingleAgentFallbackStatusMessageInternal(
    String sessionKey,
    String? reason,
  ) {
    if (!showsSingleAgentRuntimeDebugMessagesInternal) {
      return;
    }
    appendAssistantThreadMessageInternal(
      sessionKey,
      GatewayChatMessage(
        id: nextLocalMessageIdInternal(),
        role: 'assistant',
        text: singleAgentFallbackLabelInternal(reason),
        timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
        toolCallId: null,
        toolName: 'AI Chat fallback',
        stopReason: null,
        pending: false,
        error: false,
      ),
    );
  }

  String singleAgentFallbackLabelInternal(String? reason) {
    final detail = reason?.trim() ?? '';
    return detail.isEmpty
        ? appText(
            '未发现可用的外部 Agent ACP 端点，已回退到 AI Chat。',
            'No external Agent ACP endpoint is available. Falling back to AI Chat.',
          )
        : appText(
            '外部 Agent ACP 连接不可用，已回退到 AI Chat：$detail',
            'External Agent ACP connection is unavailable. Falling back to AI Chat: $detail',
          );
  }

  String singleAgentUnavailableLabelInternal(
    String sessionKey,
    String? reason,
  ) {
    final normalizedSessionKey = normalizedAssistantSessionKeyInternal(
      sessionKey,
    );
    final detail = reason?.trim() ?? '';
    final selection = singleAgentProviderForSession(normalizedSessionKey);
    if (singleAgentShouldSuggestAutoSwitchForSession(normalizedSessionKey)) {
      return detail.isEmpty
          ? appText(
              '当前线程固定为 ${selection.label}，但它在这台设备上不可用。检测到其他外部 Agent ACP 端点时不会自动改线，可切到 Auto。',
              'This thread is pinned to ${selection.label}, but it is unavailable on this device. XWorkmate will not reroute to another external Agent ACP endpoint automatically. Switch to Auto instead.',
            )
          : appText(
              '当前线程固定为 ${selection.label}：$detail 检测到其他外部 Agent ACP 端点时不会自动改线，可切到 Auto。',
              'This thread is pinned to ${selection.label}: $detail XWorkmate will not reroute to another external Agent ACP endpoint automatically. Switch to Auto instead.',
            );
    }
    if (singleAgentNeedsAiGatewayConfigurationForSession(
      normalizedSessionKey,
    )) {
      return detail.isEmpty
          ? appText(
              '当前没有可用的外部 Agent ACP 端点，也没有可用的 AI Chat fallback。请先配置外部 Agent 连接，或配置 LLM API。',
              'No external Agent ACP endpoint is available, and AI Chat fallback is not configured. Configure an external Agent connection or configure LLM API first.',
            )
          : appText(
              '$detail 当前没有可用的外部 Agent ACP 端点，也没有可用的 AI Chat fallback。请先配置外部 Agent 连接，或配置 LLM API。',
              '$detail No external Agent ACP endpoint is available, and AI Chat fallback is not configured. Configure an external Agent connection or configure LLM API first.',
            );
    }
    return detail.isEmpty
        ? appText(
            '当前线程的外部 Agent ACP 连接尚未就绪。',
            'The external Agent ACP connection for this thread is not ready yet.',
          )
        : appText(
            '当前线程的外部 Agent ACP 连接尚未就绪：$detail',
            'The external Agent ACP connection for this thread is not ready yet: $detail',
          );
  }
}
