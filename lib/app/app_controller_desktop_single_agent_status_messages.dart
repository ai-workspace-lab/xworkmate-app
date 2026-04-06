// ignore_for_file: unused_import, unnecessary_import

import 'package:flutter/material.dart';
import '../i18n/app_language.dart';
import '../runtime/runtime_models.dart';
import 'app_controller_desktop_core.dart';
import 'app_controller_desktop_runtime_helpers.dart';
import 'app_controller_desktop_thread_sessions.dart';
import 'app_controller_desktop_thread_storage.dart';

String? singleAgentRuntimeDebugToolNameDesktopInternal(
  AppController controller,
  String label,
) {
  if (!controller.showsSingleAgentRuntimeDebugMessagesInternal) {
    return null;
  }
  final trimmed = label.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}

void appendSingleAgentRuntimeStatusDesktopInternal(
  AppController controller,
  String sessionKey,
  SingleAgentProvider provider,
) {
  if (!controller.showsSingleAgentRuntimeDebugMessagesInternal) {
    return;
  }
  controller.appendAssistantThreadMessageInternal(
    sessionKey,
    GatewayChatMessage(
      id: controller.nextLocalMessageIdInternal(),
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

void appendSingleAgentFallbackStatusDesktopInternal(
  AppController controller,
  String sessionKey,
  String? reason,
) {
  if (!controller.showsSingleAgentRuntimeDebugMessagesInternal) {
    return;
  }
  controller.appendAssistantThreadMessageInternal(
    sessionKey,
    GatewayChatMessage(
      id: controller.nextLocalMessageIdInternal(),
      role: 'assistant',
      text: singleAgentFallbackLabelDesktopInternal(reason),
      timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
      toolCallId: null,
      toolName: 'AI Chat fallback',
      stopReason: null,
      pending: false,
      error: false,
    ),
  );
}

String singleAgentFallbackLabelDesktopInternal(String? reason) {
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

String singleAgentUnavailableLabelDesktopInternal(
  AppController controller,
  String sessionKey,
  String? reason,
) {
  final normalizedSessionKey = controller.normalizedAssistantSessionKeyInternal(
    sessionKey,
  );
  final detail = reason?.trim() ?? '';
  final selection = controller.singleAgentProviderForSession(
    normalizedSessionKey,
  );
  if (controller.singleAgentShouldSuggestAcpSwitchForSession(
    normalizedSessionKey,
  )) {
    return detail.isEmpty
        ? appText(
            '当前线程固定为 ${selection.label}，但它在这台设备上不可用。检测到其他外部 Agent ACP 端点时不会自动改线，请切到可用的 ACP Server。',
            'This thread is pinned to ${selection.label}, but it is unavailable on this device. XWorkmate will not reroute to another external Agent ACP endpoint automatically. Switch to an available ACP Server.',
          )
        : appText(
            '当前线程固定为 ${selection.label}：$detail 检测到其他外部 Agent ACP 端点时不会自动改线，请切到可用的 ACP Server。',
            'This thread is pinned to ${selection.label}: $detail XWorkmate will not reroute to another external Agent ACP endpoint automatically. Switch to an available ACP Server.',
          );
  }
  if (controller.singleAgentNeedsAiGatewayConfigurationForSession(
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
