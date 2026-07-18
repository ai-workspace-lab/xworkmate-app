import 'package:flutter/foundation.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'file_store_support.dart';
import 'runtime_models.dart';

enum SettingsSnapshotReloadStatus { applied, invalid }

class SettingsSnapshotReloadResult {
  const SettingsSnapshotReloadResult({
    required this.applied,
    required this.snapshot,
  });

  final bool applied;
  final SettingsSnapshot snapshot;
}

enum SkippedTaskThreadReason {
  removedAutoExecutionMode,
  incompleteWorkspaceBinding,
  invalidPersistedThreadData,
}

class SkippedTaskThreadRecord {
  const SkippedTaskThreadRecord({
    required this.threadId,
    required this.reason,
  });

  final String threadId;
  final SkippedTaskThreadReason reason;
}

class SettingsStore {
  SettingsStore(this._layoutResolver);

  final StoreLayoutResolver _layoutResolver;
  
  PersistentWriteFailure? _settingsWriteFailure;
  PersistentWriteFailure? get settingsWriteFailure => _settingsWriteFailure;

  PersistentWriteFailure? _tasksWriteFailure;
  PersistentWriteFailure? get tasksWriteFailure => _tasksWriteFailure;

  PersistentWriteFailure? _auditWriteFailure;
  PersistentWriteFailure? get auditWriteFailure => _auditWriteFailure;

  final List<SkippedTaskThreadRecord> _lastSkippedInvalidTaskThreadRecords = [];
  List<SkippedTaskThreadRecord> get lastSkippedInvalidTaskThreadRecords => List.unmodifiable(_lastSkippedInvalidTaskThreadRecords);

  Future<void> initialize() async {
    // Basic connectivity check.
    try {
      await _layoutResolver.resolve();
    } catch (e) {
      _settingsWriteFailure = _wrapFailure('initialize', PersistentStoreScope.settings, e);
    }
  }

  Future<SettingsSnapshot> loadSnapshot() async {
    try {
      final layout = await _layoutResolver.resolve();
      final file = File('${layout.configDirectory.path}/settings.yaml');
      if (await file.exists()) {
        final content = await file.readAsString();
        return SettingsSnapshot.fromJsonString(content);
      }
    } catch (e) {
       _settingsWriteFailure = _wrapFailure('loadSnapshot', PersistentStoreScope.settings, e);
    }
    return SettingsSnapshot.defaults();
  }

  Future<void> saveSnapshot(SettingsSnapshot snapshot) async {
    try {
      final layout = await _layoutResolver.resolve();
      final file = File('${layout.configDirectory.path}/settings.yaml');
      await file.writeAsString(snapshot.toJsonString(), flush: true);
      _settingsWriteFailure = null;
    } catch (e) {
      _settingsWriteFailure = _wrapFailure('saveSnapshot', PersistentStoreScope.settings, e);
    }
  }

  Future<SettingsSnapshotReloadResult> reloadSnapshotResult() async {
    final next = await loadSnapshot();
    return SettingsSnapshotReloadResult(applied: true, snapshot: next);
  }

  Future<List<TaskThread>> loadTaskThreads() async {
    _lastSkippedInvalidTaskThreadRecords.clear();
    File? file;
    try {
      final layout = await _layoutResolver.resolve();
      file = File('${layout.tasksDirectory.path}/threads.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final decoded = jsonDecode(content);
        if (decoded is List) {
          // One bad record must never wipe the whole list: a legacy or
          // corrupted entry used to throw out of the shared try and the caller
          // then treated every persisted session as gone — the next save made
          // that loss permanent. Decode per record and keep the valid rest.
          final threads = <TaskThread>[];
          for (final entry in decoded) {
            if (entry is! Map) {
              _recordSkippedTaskThread('unknown', const FormatException('not-a-map'));
              continue;
            }
            final map = entry.cast<String, dynamic>();
            try {
              threads.add(TaskThread.fromJson(map));
            } catch (error) {
              _recordSkippedTaskThread(
                map['threadId']?.toString().trim().isNotEmpty == true
                    ? map['threadId'].toString().trim()
                    : 'unknown',
                error,
              );
            }
          }
          if (_lastSkippedInvalidTaskThreadRecords.isNotEmpty) {
            await _backupUnreadableTaskThreads(file);
          }
          return threads;
        }
      }
    } catch (e) {
      _tasksWriteFailure = _wrapFailure('loadTaskThreads', PersistentStoreScope.tasks, e);
      if (file != null) {
        await _backupUnreadableTaskThreads(file);
      }
    }
    return const [];
  }

  void _recordSkippedTaskThread(String threadId, Object error) {
    // Reason mapping keys off the throw sites in TaskThread: the legacy
    // "auto" execution mode raises FormatException("... no longer supported")
    // and an incomplete workspace binding raises StateError mentioning
    // workspaceBinding. Anything else counts as invalid persisted data.
    final message = error.toString();
    final SkippedTaskThreadReason reason;
    if (message.contains('no longer supported')) {
      reason = SkippedTaskThreadReason.removedAutoExecutionMode;
    } else if (message.contains('workspaceBinding')) {
      reason = SkippedTaskThreadReason.incompleteWorkspaceBinding;
    } else {
      reason = SkippedTaskThreadReason.invalidPersistedThreadData;
    }
    _lastSkippedInvalidTaskThreadRecords.add(
      SkippedTaskThreadRecord(threadId: threadId, reason: reason),
    );
  }

  Future<void> _backupUnreadableTaskThreads(File file) async {
    // Keep the original bytes recoverable before any later save rewrites
    // threads.json with only the surviving subset.
    try {
      if (!await file.exists()) {
        return;
      }
      final stamp = DateTime.now().millisecondsSinceEpoch;
      await file.copy('${file.path}.invalid-$stamp.bak');
    } catch (e, stackTrace) {
      debugPrint('Task thread backup failed: $e\n$stackTrace');
    }
  }

  Future<void> saveTaskThreads(List<TaskThread> threads) async {
    try {
      final layout = await _layoutResolver.resolve();
      final file = File('${layout.tasksDirectory.path}/threads.json');
      await atomicWriteString(file, jsonEncode(threads));
      _tasksWriteFailure = null;
    } catch (e) {
      _tasksWriteFailure = _wrapFailure('saveTaskThreads', PersistentStoreScope.tasks, e);
    }
  }

  Future<void> clearAssistantLocalState() async {
    try {
      final layout = await _layoutResolver.resolve();
      await deleteIfExists(File('${layout.tasksDirectory.path}/threads.json'));
      await deleteIfExists(File('${layout.configDirectory.path}/settings.yaml'));
    } catch (e, stackTrace) { debugPrint('Error: $e\n$stackTrace');
      // Ignore errors for secondary persistence.
    }
  }

  Future<List<SecretAuditEntry>> loadAuditTrail() async {
    try {
      final layout = await _layoutResolver.resolve();
      final file = File('${layout.configDirectory.path}/audit.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final decoded = jsonDecode(content);
        if (decoded is List) {
          return decoded.map((e) => SecretAuditEntry.fromJson(e)).toList();
        }
      }
    } catch (e, stackTrace) { debugPrint('Error: $e\n$stackTrace');
      // Ignore errors for secondary persistence.
    }
    return const [];
  }

  Future<void> appendAudit(SecretAuditEntry entry) async {
    try {
      final items = (await loadAuditTrail()).toList(growable: true);
      items.insert(0, entry);
      if (items.length > 40) {
        items.removeRange(40, items.length);
      }
      final layout = await _layoutResolver.resolve();
      final file = File('${layout.configDirectory.path}/audit.json');
      await file.writeAsString(jsonEncode(items), flush: true);
      _auditWriteFailure = null;
    } catch (e) {
      _auditWriteFailure = _wrapFailure('appendAudit', PersistentStoreScope.audit, e);
    }
  }

  PersistentWriteFailure _wrapFailure(String operation, PersistentStoreScope scope, Object error) {
    return PersistentWriteFailure(
      scope: scope,
      operation: operation,
      message: error.toString(),
      timestampMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  void dispose() {}
}
