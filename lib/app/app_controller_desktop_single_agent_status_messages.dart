// ignore_for_file: unused_import, unnecessary_import

import 'package:flutter/material.dart';
import '../i18n/app_language.dart';
import '../runtime/runtime_models.dart';
import 'app_controller_desktop_core.dart';
import 'app_controller_desktop_runtime_helpers.dart';
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

String singleAgentUnavailableLabelDesktopInternal(
  AppController controller,
  String sessionKey,
  String? reason,
) {
  final normalizedSessionKey = controller.normalizedAssistantSessionKeyInternal(
    sessionKey,
  );
  final detail = reason?.trim() ?? '';
  final selection =
      controller.currentSingleAgentResolvedProvider ??
      controller.singleAgentProviderForSession(normalizedSessionKey);
  if (controller.singleAgentShouldSuggestAcpSwitchForSession(
    normalizedSessionKey,
  )) {
    return detail.isEmpty
        ? appText(
            '当前线程固定为 ${selection.label}，但它在这台设备上不可用。检测到其他 Bridge Provider 时不会自动改线，请手动切到可用 Provider。',
            'This thread is pinned to ${selection.label}, but it is unavailable on this device. XWorkmate will not reroute to another bridge provider automatically. Switch to an available provider manually.',
          )
        : appText(
            '当前线程固定为 ${selection.label}：$detail 检测到其他 Bridge Provider 时不会自动改线，请手动切到可用 Provider。',
            'This thread is pinned to ${selection.label}: $detail XWorkmate will not reroute to another bridge provider automatically. Switch to an available provider manually.',
          );
  }
  if (controller.singleAgentNeedsBridgeProviderForSession(
    normalizedSessionKey,
  )) {
    return detail.isEmpty
        ? appText(
            'Bridge 当前没有可用 Provider。',
            'The bridge does not currently advertise any available providers.',
          )
        : appText(
            '$detail Bridge 当前没有可用 Provider。',
            '$detail The bridge does not currently advertise any available providers.',
          );
  }
  return detail.isEmpty
      ? appText(
          '当前线程的 Bridge Provider 尚未就绪。',
          'The bridge provider for this thread is not ready yet.',
        )
      : appText(
          '当前线程的 Bridge Provider 尚未就绪：$detail',
          'The bridge provider for this thread is not ready yet: $detail',
        );
}
