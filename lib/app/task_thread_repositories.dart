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

  /// 启动恢复完成前为 true。此时 `_records` 只是「部分视图」——持久化线程
  /// 还没灌进来,任何写盘都会把尚未恢复的历史会话当作已删除清掉
  /// (iOS 重启只剩「新对话」的根因)。期间的写请求只记待办,等
  /// [resumePersistence] 拿到完整视图后再落一次盘。
  bool _persistSuspended = false;
  bool _persistRequestedWhileSuspended = false;

  void suspendPersistence() {
    _persistSuspended = true;
  }

  void resumePersistence({bool flushPending = true}) {
    if (!_persistSuspended) {
      return;
    }
    _persistSuspended = false;
    final hadPending = _persistRequestedWhileSuspended;
    _persistRequestedWhileSuspended = false;
    if (hadPending && flushPending) {
      _schedulePersist();
    }
  }

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
        records.map(
          (record) => MapEntry<String, TaskThread>(record.threadId, record),
        ),
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
    if (_persistSuspended) {
      _persistRequestedWhileSuspended = true;
      return;
    }
    final snapshot = this.snapshot();
    _persistQueue = _persistQueue.catchError((_) {}).then((_) async {
      await _saveRecords(snapshot);
    });
    unawaited(_persistQueue);
  }
}
