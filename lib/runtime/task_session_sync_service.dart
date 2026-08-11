import 'session_sync_contract.dart';
import 'task_session_api_client.dart';
import 'task_session_binding.dart';

class TaskSessionBindingNotFound implements Exception {
  const TaskSessionBindingNotFound(this.taskThreadKey);

  final String taskThreadKey;

  @override
  String toString() => 'TaskSessionBindingNotFound($taskThreadKey)';
}

class TaskSessionBindingMismatch implements Exception {
  const TaskSessionBindingMismatch({required this.field});

  final String field;

  @override
  String toString() => 'TaskSessionBindingMismatch($field)';
}

class TaskSessionReplayFailed implements Exception {
  const TaskSessionReplayFailed(this.message);

  final String message;

  @override
  String toString() => 'TaskSessionReplayFailed($message)';
}

class TaskSessionSyncResult {
  const TaskSessionSyncResult({
    required this.binding,
    required this.snapshot,
    required this.events,
  });

  final TaskSessionBinding binding;
  final CloudSessionSnapshot snapshot;
  final List<SessionEvent> events;
}

/// Orchestrates snapshot-first recovery without mutating any UI/controller.
///
/// The server snapshot and ordered event stream are authoritative. A replay
/// gap discards the partial attempt, reloads a fresh snapshot once, and then
/// resumes from that snapshot's cursor.
class TaskSessionSyncService {
  TaskSessionSyncService({
    required TaskSessionGateway gateway,
    required TaskSessionBindingStore store,
  }) : _gateway = gateway,
       _store = store;

  static const int _maxReplayPages = 100;

  final TaskSessionGateway _gateway;
  final TaskSessionBindingStore _store;

  Future<TaskSessionBinding> createBinding({
    required String taskThreadKey,
    required String namespaceId,
    required String title,
  }) async {
    final snapshot = await _gateway.createSession(
      namespaceId: namespaceId,
      title: title,
    );
    if (snapshot.namespaceId != namespaceId.trim()) {
      throw const TaskSessionBindingMismatch(field: 'namespaceId');
    }
    final binding = TaskSessionBinding(
      taskThreadKey: taskThreadKey,
      cloudSessionId: snapshot.sessionId,
      namespaceId: snapshot.namespaceId,
      lastEventSeq: snapshot.lastEventSeq,
      snapshotVersion: snapshot.snapshotVersion,
    );
    await _store.save(binding);
    return binding;
  }

  Future<TaskSessionBinding> attachBinding({
    required String taskThreadKey,
    required String cloudSessionId,
    required String namespaceId,
  }) async {
    final snapshot = await _gateway.loadSnapshot(cloudSessionId);
    _validateIdentity(
      snapshot,
      cloudSessionId: cloudSessionId.trim(),
      namespaceId: namespaceId.trim(),
    );
    final binding = TaskSessionBinding(
      taskThreadKey: taskThreadKey,
      cloudSessionId: snapshot.sessionId,
      namespaceId: snapshot.namespaceId,
      lastEventSeq: snapshot.lastEventSeq,
      snapshotVersion: snapshot.snapshotVersion,
    );
    await _store.save(binding);
    return binding;
  }

  Future<TaskSessionSyncResult> synchronize(
    String taskThreadKey, {
    int pageLimit = 100,
  }) async {
    if (pageLimit <= 0 || pageLimit > 500) {
      throw ArgumentError.value(
        pageLimit,
        'pageLimit',
        'must be between 1 and 500',
      );
    }
    final binding = await _store.load(taskThreadKey);
    if (binding == null) {
      throw TaskSessionBindingNotFound(taskThreadKey);
    }

    _ReplayAttempt? attempt;
    for (var recoveryAttempt = 0; recoveryAttempt < 2; recoveryAttempt += 1) {
      attempt = await _loadSnapshotAndReplay(binding, pageLimit: pageLimit);
      if (!attempt.hasGap) {
        final updatedBinding = binding.copyWith(
          lastEventSeq: attempt.snapshot.lastEventSeq,
          snapshotVersion: attempt.snapshot.snapshotVersion,
        );
        await _store.save(updatedBinding);
        return TaskSessionSyncResult(
          binding: updatedBinding,
          snapshot: attempt.snapshot,
          events: List<SessionEvent>.unmodifiable(attempt.events),
        );
      }
    }
    throw TaskSessionReplayFailed(
      'server event sequence still has a gap after snapshot recovery '
      '(expected ${attempt!.expectedSeq}, received ${attempt.receivedSeq})',
    );
  }

  Future<_ReplayAttempt> _loadSnapshotAndReplay(
    TaskSessionBinding binding, {
    required int pageLimit,
  }) async {
    final snapshot = await _gateway.loadSnapshot(binding.cloudSessionId);
    _validateIdentity(
      snapshot,
      cloudSessionId: binding.cloudSessionId,
      namespaceId: binding.namespaceId,
    );
    final coordinator = SessionSyncCoordinator()..attach(snapshot);
    final acceptedEvents = <SessionEvent>[];

    for (var page = 0; page < _maxReplayPages; page += 1) {
      final afterSeq = coordinator.snapshot!.lastEventSeq;
      final events = await _gateway.loadEvents(
        binding.cloudSessionId,
        afterSeq: afterSeq,
        limit: pageLimit,
      );
      if (events.isEmpty) {
        return _ReplayAttempt.complete(
          snapshot: coordinator.snapshot!,
          events: acceptedEvents,
        );
      }
      for (final event in events) {
        final accepted = coordinator.accept(event);
        if (coordinator.needsReplay) {
          return _ReplayAttempt.gap(
            snapshot: coordinator.snapshot!,
            expectedSeq: coordinator.replayFromSeq,
            receivedSeq: event.seq,
          );
        }
        if (accepted) {
          acceptedEvents.add(event);
        }
      }
      if (events.length < pageLimit) {
        return _ReplayAttempt.complete(
          snapshot: coordinator.snapshot!,
          events: acceptedEvents,
        );
      }
      if (coordinator.snapshot!.lastEventSeq == afterSeq) {
        return _ReplayAttempt.gap(
          snapshot: coordinator.snapshot!,
          expectedSeq: afterSeq + 1,
          receivedSeq: events.last.seq,
        );
      }
    }
    throw const TaskSessionReplayFailed('event replay exceeded 100 pages');
  }

  void _validateIdentity(
    CloudSessionSnapshot snapshot, {
    required String cloudSessionId,
    required String namespaceId,
  }) {
    if (snapshot.sessionId != cloudSessionId) {
      throw const TaskSessionBindingMismatch(field: 'sessionId');
    }
    if (snapshot.namespaceId != namespaceId) {
      throw const TaskSessionBindingMismatch(field: 'namespaceId');
    }
  }
}

class _ReplayAttempt {
  const _ReplayAttempt._({
    required this.snapshot,
    required this.events,
    required this.hasGap,
    required this.expectedSeq,
    required this.receivedSeq,
  });

  factory _ReplayAttempt.complete({
    required CloudSessionSnapshot snapshot,
    required List<SessionEvent> events,
  }) => _ReplayAttempt._(
    snapshot: snapshot,
    events: events,
    hasGap: false,
    expectedSeq: 0,
    receivedSeq: 0,
  );

  factory _ReplayAttempt.gap({
    required CloudSessionSnapshot snapshot,
    required int expectedSeq,
    required int receivedSeq,
  }) => _ReplayAttempt._(
    snapshot: snapshot,
    events: const <SessionEvent>[],
    hasGap: true,
    expectedSeq: expectedSeq,
    receivedSeq: receivedSeq,
  );

  final CloudSessionSnapshot snapshot;
  final List<SessionEvent> events;
  final bool hasGap;
  final int expectedSeq;
  final int receivedSeq;
}
