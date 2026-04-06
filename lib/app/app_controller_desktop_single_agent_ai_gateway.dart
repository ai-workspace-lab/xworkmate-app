// ignore_for_file: unused_import, unnecessary_import

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../i18n/app_language.dart';
import '../models/app_models.dart';
import '../runtime/gateway_runtime_helpers.dart';
import '../runtime/runtime_models.dart';
import 'app_controller_desktop_core.dart';
import 'app_controller_desktop_runtime_helpers.dart';
import 'app_controller_desktop_skill_permissions.dart';
import 'app_controller_desktop_thread_sessions.dart';
import 'app_controller_desktop_thread_storage.dart';

GatewayChatMessage assistantErrorMessageSingleAgentDesktopInternal(
  AppController controller,
  String text,
) {
  return GatewayChatMessage(
    id: controller.nextLocalMessageIdInternal(),
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

Future<void> sendAiGatewaySingleAgentMessageDesktopInternal(
  AppController controller,
  String message, {
  required String thinking,
  required List<GatewayChatAttachmentPayload> attachments,
  String? sessionKeyOverride,
  bool appendUserMessage = true,
  bool managePendingState = true,
}) async {
  final sessionKey = controller.normalizedAssistantSessionKeyInternal(
    sessionKeyOverride ??
        controller.sessionsControllerInternal.currentSessionKey,
  );
  final trimmed = message.trim();
  if (trimmed.isEmpty && attachments.isEmpty) {
    return;
  }

  final baseUrl = controller.normalizeAiGatewayBaseUrlInternal(
    controller.aiGatewayUrl,
  );
  if (baseUrl == null) {
    controller.appendAssistantThreadMessageInternal(
      sessionKey,
      assistantErrorMessageSingleAgentDesktopInternal(
        controller,
        appText(
          'LLM API Endpoint 未配置，无法发送对话。',
          'LLM API Endpoint is not configured, so the conversation could not be sent.',
        ),
      ),
    );
    return;
  }

  final apiKey = await controller.loadAiGatewayApiKey();
  final allowsAnonymous =
      controller.isLoopbackHostInternal(baseUrl.host) &&
      (baseUrl.host.trim().toLowerCase() == '127.0.0.1' ||
          baseUrl.host.trim().toLowerCase() == 'localhost');
  if (apiKey.isEmpty && !allowsAnonymous) {
    controller.appendAssistantThreadMessageInternal(
      sessionKey,
      assistantErrorMessageSingleAgentDesktopInternal(
        controller,
        appText(
          'LLM API Token 未配置，无法发送对话。',
          'LLM API Token is not configured, so the conversation could not be sent.',
        ),
      ),
    );
    return;
  }

  final model = controller.resolvedAiGatewayModel;
  if (model.isEmpty) {
    controller.appendAssistantThreadMessageInternal(
      sessionKey,
      assistantErrorMessageSingleAgentDesktopInternal(
        controller,
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
  }
  if (managePendingState) {
    controller.aiGatewayPendingSessionKeysInternal.add(sessionKey);
    controller.recomputeTasksInternal();
    controller.notifyIfActiveInternal();
  }

  try {
    final assistantText =
        await requestAiGatewaySingleAgentCompletionDesktopInternal(
          controller,
          baseUrl: baseUrl,
          apiKey: apiKey,
          model: model,
          thinking: thinking,
          sessionKey: sessionKey,
        );
    controller.appendAssistantThreadMessageInternal(
      sessionKey,
      GatewayChatMessage(
        id: controller.nextLocalMessageIdInternal(),
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
    controller.upsertTaskThreadInternal(
      sessionKey,
      gatewayEntryState: 'only-chat',
      latestResolvedRuntimeModel: model,
      lifecycleStatus: 'ready',
      lastRunAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
      lastResultCode: 'success',
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
  } on AiGatewayAbortExceptionInternal catch (error) {
    final partial = error.partialText.trim();
    if (partial.isNotEmpty) {
      controller.appendAssistantThreadMessageInternal(
        sessionKey,
        GatewayChatMessage(
          id: controller.nextLocalMessageIdInternal(),
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
    controller.upsertTaskThreadInternal(
      sessionKey,
      lifecycleStatus: 'ready',
      lastRunAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
      lastResultCode: 'aborted',
      updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    );
  } catch (error) {
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
        controller.aiGatewayErrorLabelInternal(error),
      ),
    );
  } finally {
    controller.aiGatewayStreamingClientsInternal.remove(sessionKey);
    controller.clearAiGatewayStreamingTextInternal(sessionKey);
    if (managePendingState) {
      controller.aiGatewayPendingSessionKeysInternal.remove(sessionKey);
      controller.recomputeTasksInternal();
      controller.notifyIfActiveInternal();
    }
  }
}

Future<String> requestAiGatewaySingleAgentCompletionDesktopInternal(
  AppController controller, {
  required Uri baseUrl,
  required String apiKey,
  required String model,
  required String thinking,
  required String sessionKey,
}) async {
  final uri = controller.aiGatewayChatUriInternal(baseUrl);
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  controller.aiGatewayStreamingClientsInternal[sessionKey] = client;
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
    final trimmedApiKey = apiKey.trim();
    if (trimmedApiKey.isNotEmpty) {
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $trimmedApiKey',
      );
      request.headers.set('x-api-key', trimmedApiKey);
    }
    final payload = <String, dynamic>{
      'model': model,
      'stream': true,
      'messages': buildAiGatewaySingleAgentRequestMessagesDesktopInternal(
        controller,
        sessionKey,
      ),
    };
    final normalizedThinking = thinking.trim().toLowerCase();
    if (normalizedThinking.isNotEmpty && normalizedThinking != 'off') {
      payload['reasoning_effort'] = normalizedThinking;
    }
    request.add(utf8.encode(jsonEncode(payload)));
    final response = await request.close().timeout(const Duration(seconds: 60));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await response.transform(utf8.decoder).join();
      throw AiGatewayChatExceptionInternal(
        controller.formatAiGatewayHttpErrorInternal(
          response.statusCode,
          controller.extractAiGatewayErrorDetailInternal(body),
        ),
      );
    }
    final contentType =
        response.headers.contentType?.mimeType.toLowerCase() ??
        response.headers.value(HttpHeaders.contentTypeHeader)?.toLowerCase() ??
        '';
    if (contentType.contains('text/event-stream')) {
      final streamed = await readAiGatewayStreamingResponseDesktopInternal(
        controller,
        response: response,
        sessionKey: sessionKey,
      );
      if (streamed.trim().isEmpty) {
        throw const FormatException('Missing assistant content');
      }
      return streamed.trim();
    }
    return await readAiGatewayJsonCompletionDesktopInternal(
      controller,
      response,
    );
  } catch (error) {
    if (consumeAiGatewaySingleAgentAbortDesktopInternal(
      controller,
      sessionKey,
    )) {
      throw AiGatewayAbortExceptionInternal(
        controller.aiGatewayStreamingTextBySessionInternal[sessionKey] ?? '',
      );
    }
    rethrow;
  } finally {
    controller.aiGatewayStreamingClientsInternal.remove(sessionKey);
    client.close(force: true);
  }
}

List<Map<String, String>>
buildAiGatewaySingleAgentRequestMessagesDesktopInternal(
  AppController controller,
  String sessionKey,
) {
  final history = <GatewayChatMessage>[
    ...(controller.gatewayHistoryCacheInternal[sessionKey] ??
        const <GatewayChatMessage>[]),
    ...(controller.assistantThreadMessagesInternal[sessionKey] ??
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

Future<String> readAiGatewayJsonCompletionDesktopInternal(
  AppController controller,
  HttpClientResponse response,
) async {
  final body = await response.transform(utf8.decoder).join();
  final decoded = jsonDecode(controller.extractFirstJsonDocumentInternal(body));
  final assistantText = controller.extractAiGatewayAssistantTextInternal(
    decoded,
  );
  if (assistantText.trim().isEmpty) {
    throw const FormatException('Missing assistant content');
  }
  return assistantText.trim();
}

Future<String> readAiGatewayStreamingResponseDesktopInternal(
  AppController controller, {
  required HttpClientResponse response,
  required String sessionKey,
}) async {
  final buffer = StringBuffer();
  final eventLines = <String>[];

  void processEvent(String payload) {
    final trimmed = payload.trim();
    if (trimmed.isEmpty || trimmed == '[DONE]') {
      return;
    }
    final deltaText = extractAiGatewayStreamTextDesktopInternal(
      controller,
      trimmed,
    );
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
    controller.setAiGatewayStreamingTextInternal(sessionKey, buffer.toString());
  }

  await for (final line
      in response.transform(utf8.decoder).transform(const LineSplitter())) {
    if (consumeAiGatewaySingleAgentAbortDesktopInternal(
      controller,
      sessionKey,
    )) {
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

String extractAiGatewayStreamTextDesktopInternal(
  AppController controller,
  String payload,
) {
  final decoded = jsonDecode(
    controller.extractFirstJsonDocumentInternal(payload),
  );
  final map = asMap(decoded);
  final choices = asList(map['choices']);
  if (choices.isNotEmpty) {
    final firstChoice = asMap(choices.first);
    final delta = asMap(firstChoice['delta']);
    final deltaContent = controller.extractAiGatewayContentInternal(
      delta['content'],
    );
    if (deltaContent.isNotEmpty) {
      return deltaContent;
    }
  }
  return controller.extractAiGatewayAssistantTextInternal(decoded);
}

Future<void> abortAiGatewaySingleAgentRunDesktopInternal(
  AppController controller,
  String sessionKey,
) async {
  final normalizedSessionKey = controller.normalizedAssistantSessionKeyInternal(
    sessionKey,
  );
  controller.aiGatewayAbortedSessionKeysInternal.add(normalizedSessionKey);
  final client = controller.aiGatewayStreamingClientsInternal.remove(
    normalizedSessionKey,
  );
  if (client != null) {
    try {
      client.close(force: true);
    } catch (_) {
      // Best effort only.
    }
  }
  controller.aiGatewayPendingSessionKeysInternal.remove(normalizedSessionKey);
  controller.clearAiGatewayStreamingTextInternal(normalizedSessionKey);
  controller.upsertTaskThreadInternal(
    normalizedSessionKey,
    lifecycleStatus: 'ready',
    lastRunAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
    lastResultCode: 'aborted',
    updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
  );
  controller.recomputeTasksInternal();
  controller.notifyIfActiveInternal();
}

bool consumeAiGatewaySingleAgentAbortDesktopInternal(
  AppController controller,
  String sessionKey,
) {
  return controller.aiGatewayAbortedSessionKeysInternal.remove(
    controller.normalizedAssistantSessionKeyInternal(sessionKey),
  );
}
