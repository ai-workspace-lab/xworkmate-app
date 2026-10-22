import 'dart:async';

import '../models/app_models.dart';
import '../runtime/runtime_models.dart';
import 'app_controller.dart';

extension AppControllerDesktopScheduledTasks on AppController {
  Future<void> createOrUpdateAggregatedSession({
    required String sessionKey,
    required String title,
    required String ownerName,
    required String modelName,
    required String initialUserPrompt,
    required String initialAssistantMarkdown,
    bool selectAfterCreate = false,
  }) async {
    final normalizedKey = normalizedAssistantSessionKeyInternal(sessionKey);
    if (normalizedKey.isEmpty) {
      return;
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch.toDouble();

    if (!assistantThreadRecordsInternal.containsKey(normalizedKey)) {
      initializeAssistantThreadContext(
        normalizedKey,
        title: title,
        executionTarget: AssistantExecutionTarget.gateway,
      );
    }

    final userMessage = GatewayChatMessage(
      id: 'msg-user-$normalizedKey-${nowMs.toInt()}',
      role: 'user',
      text: initialUserPrompt,
      timestampMs: nowMs - 1000,
      toolCallId: null,
      toolName: null,
      stopReason: null,
      pending: false,
      error: false,
    );

    final assistantMessage = GatewayChatMessage(
      id: 'msg-assistant-$normalizedKey-${nowMs.toInt()}',
      role: 'assistant',
      text: initialAssistantMarkdown,
      timestampMs: nowMs,
      toolCallId: null,
      toolName: null,
      stopReason: null,
      pending: false,
      error: false,
    );

    appendLocalSessionMessageInternal(
      normalizedKey,
      userMessage,
      persistInThreadContext: true,
    );
    appendLocalSessionMessageInternal(
      normalizedKey,
      assistantMessage,
      persistInThreadContext: true,
    );

    upsertTaskThreadInternal(
      normalizedKey,
      title: title,
      assistantModelId: modelName,
      lifecycleStatus: 'completed',
      updatedAtMs: nowMs,
    );

    recomputeTasksInternal();
    notifyIfActiveInternal();

    if (selectAfterCreate) {
      navigateTo(WorkspaceDestination.assistant);
      await switchSession(normalizedKey);
    }
  }
}
