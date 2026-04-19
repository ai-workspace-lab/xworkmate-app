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
    try {
      final layout = await _layoutResolver.resolve();
      final file = File('${layout.tasksDirectory.path}/threads.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final decoded = jsonDecode(content);
        if (decoded is List) {
          return decoded.map((e) => TaskThread.fromJson(e)).toList();
        }
      }
    } catch (e) {
      _tasksWriteFailure = _wrapFailure('loadTaskThreads', PersistentStoreScope.tasks, e);
    }
    return const [];
  }

  Future<void> saveTaskThreads(List<TaskThread> threads) async {
    try {
      final layout = await _layoutResolver.resolve();
      final file = File('${layout.tasksDirectory.path}/threads.json');
      await file.writeAsString(jsonEncode(threads), flush: true);
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
    } catch (_) {
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
    } catch (_) {
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
