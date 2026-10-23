import 'dart:async';

import 'package:uuid/uuid.dart';

import '../../runtime/task_session_client.dart';
import 'bot_team_models.dart';

/// Runs one role task on DS Bot to its end, for callers that want the answer
/// now rather than a background thread: it opens or reuses a session, sends the task
/// with the role, and polls the session's events until the run is terminal.
class RoleTaskRunner {
  RoleTaskRunner({
    required TaskSessionClient client,
    this.pollInterval = const Duration(milliseconds: 1500),
    this.timeout = const Duration(minutes: 15),
    String Function()? newRequestId,
  }) : _client = client,
       _newRequestId = newRequestId ?? (() => const Uuid().v4());

  final TaskSessionClient _client;
  final Duration pollInterval;
  final Duration timeout;
  final String Function() _newRequestId;

  /// Returns the finished run. A run still going after [timeout] comes back
  /// non-terminal; it keeps running and stays visible in the Bot team page.
  Future<BotTaskView> run({
    required String text,
    required String role,
    TaskSessionSummary? existingSession,
    Future<void> Function(String namespaceId, TaskSessionSummary session)?
    onSessionReady,
    void Function(BotTaskView view)? onProgress,
  }) async {
    final namespaceId = await _client.personalNamespaceId();
    final session =
        existingSession ??
        await _client.createSession(
          namespaceId: namespaceId,
          title: botTaskTitle(text),
        );
    await onSessionReady?.call(namespaceId, session);
    final receipt = await _client.appendMessage(
      sessionId: session.sessionId,
      clientRequestId: _newRequestId(),
      text: text,
      routing: botRoleRouting(role: role),
    );
    final events = <TaskSessionEvent>[];
    // Older turns may exceed a page. Start with this append's event rather
    // than replaying the session history and skipping the current run.
    var afterSeq = receipt.eventSeq > 0 ? receipt.eventSeq - 1 : 0;
    final deadline = DateTime.now().add(timeout);
    while (true) {
      final page = await _client.listEvents(
        sessionId: session.sessionId,
        afterSeq: afterSeq,
      );
      events.addAll(page.events);
      if (page.events.isNotEmpty && page.events.last.seq > afterSeq) {
        afterSeq = page.events.last.seq;
      }
      final view = foldBotTasks(events).firstWhere(
        (task) => task.runId == receipt.taskRunId,
        orElse: () => BotTaskView(runId: receipt.taskRunId),
      );
      onProgress?.call(view);
      if (!view.active || !DateTime.now().isBefore(deadline)) {
        return view;
      }
      await Future<void>.delayed(pollInterval);
    }
  }
}
