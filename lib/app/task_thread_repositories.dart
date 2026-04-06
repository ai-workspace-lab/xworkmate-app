import 'dart:async';
import 'dart:collection';

import '../runtime/runtime_models.dart';

class DesktopTaskThreadRepository {
  DesktopTaskThreadRepository({
    required Future<void> Function(List<TaskThread> records) saveRecords,
  }) : _saveRecords = saveRecords;

  final Future<void> Function(List<TaskThread> records) _saveRecords;
  final Map<String, TaskThread> _records = <String, TaskThread>{};
  Future<void> _persistQueue = Future<void>.value();

  Map<String, TaskThread> get recordsView => UnmodifiableMapView(_records);
  Iterable<TaskThread> get values => _records.values;

  bool containsKey(String sessionKey) => _records.containsKey(sessionKey);

  TaskThread? taskThreadForSession(String sessionKey) => _records[sessionKey];

  TaskThread requireTaskThreadForSession(String sessionKey) {
    final record = taskThreadForSession(sessionKey);
    if (record == null) {
      throw StateError('Missing TaskThread for session $sessionKey.');
    }
    return record;
  }

  void replace(TaskThread record, {bool persist = true}) {
    _records[record.threadId] = record;
    if (persist) {
      _schedulePersist();
    }
  }

  void replaceAll(Iterable<TaskThread> records, {bool persist = false}) {
    _records
      ..clear()
      ..addEntries(
        records.map((record) => MapEntry<String, TaskThread>(record.threadId, record)),
      );
    if (persist) {
      _schedulePersist();
    }
  }

  void clear({bool persist = false}) {
    _records.clear();
    if (persist) {
      _schedulePersist();
    }
  }

  void removeWhere(
    bool Function(String sessionKey, TaskThread record) predicate, {
    bool persist = true,
  }) {
    _records.removeWhere(predicate);
    if (persist) {
      _schedulePersist();
    }
  }

  List<TaskThread> snapshot() => values.toList(growable: false);

  Future<void> flush() => _persistQueue.catchError((_) {});

  void _schedulePersist() {
    final snapshot = this.snapshot();
    _persistQueue = _persistQueue.catchError((_) {}).then((_) async {
      await _saveRecords(snapshot);
    });
    unawaited(_persistQueue);
  }
}

class WebTaskThreadRepository {
  final Map<String, TaskThread> _records = <String, TaskThread>{};

  Map<String, TaskThread> get recordsView => UnmodifiableMapView(_records);
  Iterable<TaskThread> get values => _records.values;

  bool containsKey(String sessionKey) => _records.containsKey(sessionKey);

  TaskThread? taskThreadForSession(String sessionKey) => _records[sessionKey];

  TaskThread requireTaskThreadForSession(String sessionKey) {
    final record = taskThreadForSession(sessionKey);
    if (record == null) {
      throw StateError('Missing TaskThread for session $sessionKey.');
    }
    return record;
  }

  void replace(TaskThread record) {
    _records[record.threadId] = record;
  }

  void replaceAll(Iterable<TaskThread> records) {
    _records
      ..clear()
      ..addEntries(
        records.map((record) => MapEntry<String, TaskThread>(record.threadId, record)),
      );
  }

  void clear() {
    _records.clear();
  }

  void removeWhere(bool Function(String sessionKey, TaskThread record) predicate) {
    _records.removeWhere(predicate);
  }

  List<TaskThread> snapshot() => values.toList(growable: false);
}
