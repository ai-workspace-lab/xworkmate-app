import 'package:xworkmate/runtime/task_session_client.dart';

/// In-memory Accounts stand-in: sessions, ordered events, and a scripted
/// orchestrator the test drives by appending events.
class FakeTaskSessionClient implements TaskSessionClient {
  final List<TaskSessionSummary> sessions = <TaskSessionSummary>[];
  final Map<String, List<TaskSessionEvent>> events = <String, List<TaskSessionEvent>>{};
  final List<Map<String, Object?>> appended = <Map<String, Object?>>[];
  final List<String> cancelled = <String>[];
  int _runs = 0;
  Object? failNextAppend;

  int _nextSeq(String sessionId) => (events[sessionId]?.length ?? 0) + 1;

  void addEvent(String sessionId, String type, Map<String, dynamic> payload) {
    events.putIfAbsent(sessionId, () => <TaskSessionEvent>[]).add(
      TaskSessionEvent(seq: _nextSeq(sessionId), type: type, payload: payload, createdAt: null),
    );
  }

  @override
  Future<String> personalNamespaceId() async => 'ns-personal';

  @override
  Future<List<TaskSessionSummary>> listSessions(String namespaceId) async =>
      List<TaskSessionSummary>.of(sessions);

  @override
  Future<TaskSessionSummary> createSession({required String namespaceId, required String title}) async {
    final summary = TaskSessionSummary(
      sessionId: 's-${sessions.length + 1}',
      title: title,
      lastEventSeq: 0,
      updatedAt: null,
      lastRunState: '',
    );
    sessions.insert(0, summary);
    return summary;
  }

  @override
  Future<TaskMessageReceipt> appendMessage({
    required String sessionId,
    required String clientRequestId,
    required String text,
    Map<String, Object?> routing = const <String, Object?>{},
  }) async {
    if (failNextAppend != null) {
      final failure = failNextAppend!;
      failNextAppend = null;
      throw failure;
    }
    final runId = 'run-${++_runs}';
    appended.add(<String, Object?>{'sessionId': sessionId, 'clientRequestId': clientRequestId, 'text': text, 'routing': routing});
    addEvent(sessionId, 'message.created', {'taskRunId': runId, 'text': text});
    addEvent(sessionId, 'run.queued', {'taskRunId': runId});
    return TaskMessageReceipt(taskRunId: runId, eventSeq: _nextSeq(sessionId) - 2);
  }

  @override
  Future<TaskEventPage> listEvents({required String sessionId, int afterSeq = 0, int limit = 100}) async {
    final all = events[sessionId] ?? const <TaskSessionEvent>[];
    final page = all.where((event) => event.seq > afterSeq).take(limit).toList();
    return TaskEventPage(events: page, lastEventSeq: all.isEmpty ? 0 : all.last.seq);
  }

  @override
  Future<void> cancelRun({required String sessionId, required String taskRunId, required String clientRequestId}) async {
    cancelled.add(taskRunId);
    addEvent(sessionId, 'run.cancel_requested', {'taskRunId': taskRunId});
  }
}
