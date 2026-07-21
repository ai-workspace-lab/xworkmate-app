import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'file_store_support.dart';
import 'runtime_models.dart';
import 'task_thread_store.dart';

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
  const SkippedTaskThreadRecord({required this.threadId, required this.reason});

  final String threadId;
  final SkippedTaskThreadReason reason;
}

class SettingsStore {
  SettingsStore(
    this._layoutResolver, {
    TaskThreadStore? taskThreadStore,
    TaskThreadStoreRegistry? taskThreadStoreRegistry,
  }) : _taskThreadStoreOverride = taskThreadStore,
       _taskThreadStoreRegistry =
           taskThreadStoreRegistry ?? TaskThreadStoreRegistry();

  final StoreLayoutResolver _layoutResolver;
  final TaskThreadStore? _taskThreadStoreOverride;
  final TaskThreadStoreRegistry _taskThreadStoreRegistry;
  TaskThreadStore? _taskThreadStore;

  static const String _mobileSettingsKey = 'xworkmate.settings.yaml';
  static const String _mobileAuditKey = 'xworkmate.audit.json';

  PersistentWriteFailure? _settingsWriteFailure;
  PersistentWriteFailure? get settingsWriteFailure => _settingsWriteFailure;

  PersistentWriteFailure? _tasksWriteFailure;
  PersistentWriteFailure? get tasksWriteFailure => _tasksWriteFailure;

  PersistentWriteFailure? _auditWriteFailure;
  PersistentWriteFailure? get auditWriteFailure => _auditWriteFailure;

  final List<SkippedTaskThreadRecord> _lastSkippedInvalidTaskThreadRecords = [];
  List<SkippedTaskThreadRecord> get lastSkippedInvalidTaskThreadRecords =>
      List.unmodifiable(_lastSkippedInvalidTaskThreadRecords);

  static bool get _useMobilePreferences =>
      !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  TaskThreadStore _resolveTaskThreadStore() {
    return _taskThreadStore ??=
        _taskThreadStoreOverride ??
        _taskThreadStoreRegistry.resolveForPlatform().open(
          layoutResolver: _layoutResolver,
          onSkippedRecord: _recordSkippedTaskThread,
        );
  }

  Future<void> initialize() async {
    // Basic connectivity check.
    try {
      await _layoutResolver.resolve();
    } catch (e) {
      _settingsWriteFailure = _wrapFailure(
        'initialize',
        PersistentStoreScope.settings,
        e,
      );
    }
  }

  Future<SettingsSnapshot> loadSnapshot() async {
    try {
      if (_useMobilePreferences) {
        final prefs = await SharedPreferences.getInstance();
        final content = prefs.getString(_mobileSettingsKey);
        if (content != null) {
          return SettingsSnapshot.fromJsonString(content);
        }
        return SettingsSnapshot.defaults();
      }
      final layout = await _layoutResolver.resolve();
      final file = File('${layout.configDirectory.path}/settings.yaml');
      if (await file.exists()) {
        final content = await file.readAsString();
        return SettingsSnapshot.fromJsonString(content);
      }
    } catch (e) {
      _settingsWriteFailure = _wrapFailure(
        'loadSnapshot',
        PersistentStoreScope.settings,
        e,
      );
    }
    return SettingsSnapshot.defaults();
  }

  Future<void> saveSnapshot(SettingsSnapshot snapshot) async {
    try {
      if (_useMobilePreferences) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_mobileSettingsKey, snapshot.toJsonString());
        _settingsWriteFailure = null;
        return;
      }
      final layout = await _layoutResolver.resolve();
      final file = File('${layout.configDirectory.path}/settings.yaml');
      await file.writeAsString(snapshot.toJsonString(), flush: true);
      _settingsWriteFailure = null;
    } catch (e) {
      _settingsWriteFailure = _wrapFailure(
        'saveSnapshot',
        PersistentStoreScope.settings,
        e,
      );
    }
  }

  Future<SettingsSnapshotReloadResult> reloadSnapshotResult() async {
    final next = await loadSnapshot();
    return SettingsSnapshotReloadResult(applied: true, snapshot: next);
  }

  Future<List<TaskThread>> loadTaskThreads() async {
    _lastSkippedInvalidTaskThreadRecords.clear();
    try {
      return await _resolveTaskThreadStore().load();
    } catch (e) {
      _tasksWriteFailure = _wrapFailure(
        'loadTaskThreads',
        PersistentStoreScope.tasks,
        e,
      );
    }
    return const [];
  }

  Future<void> saveTaskThreads(List<TaskThread> threads) async {
    try {
      await _resolveTaskThreadStore().save(threads);
      _tasksWriteFailure = null;
    } catch (e) {
      _tasksWriteFailure = _wrapFailure(
        'saveTaskThreads',
        PersistentStoreScope.tasks,
        e,
      );
    }
  }

  Future<void> clearAssistantLocalState() async {
    try {
      await _resolveTaskThreadStore().clear();
      if (_useMobilePreferences) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_mobileSettingsKey);
        return;
      }
      final layout = await _layoutResolver.resolve();
      await deleteIfExists(File('${layout.configDirectory.path}/settings.yaml'));
    } catch (e, stackTrace) {
      debugPrint('Error: $e\n$stackTrace');
      // Ignore errors for secondary persistence.
    }
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

  Future<List<SecretAuditEntry>> loadAuditTrail() async {
    try {
      if (_useMobilePreferences) {
        final prefs = await SharedPreferences.getInstance();
        final content = prefs.getString(_mobileAuditKey);
        if (content != null) {
          final decoded = jsonDecode(content);
          if (decoded is List) {
            return decoded.map((e) => SecretAuditEntry.fromJson(e)).toList();
          }
        }
        return const [];
      }
      final layout = await _layoutResolver.resolve();
      final file = File('${layout.configDirectory.path}/audit.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final decoded = jsonDecode(content);
        if (decoded is List) {
          return decoded.map((e) => SecretAuditEntry.fromJson(e)).toList();
        }
      }
    } catch (e, stackTrace) {
      debugPrint('Error: $e\n$stackTrace');
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
      if (_useMobilePreferences) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_mobileAuditKey, jsonEncode(items));
        _auditWriteFailure = null;
        return;
      }
      final layout = await _layoutResolver.resolve();
      final file = File('${layout.configDirectory.path}/audit.json');
      await file.writeAsString(jsonEncode(items), flush: true);
      _auditWriteFailure = null;
    } catch (e) {
      _auditWriteFailure = _wrapFailure(
        'appendAudit',
        PersistentStoreScope.audit,
        e,
      );
    }
  }

  PersistentWriteFailure _wrapFailure(
    String operation,
    PersistentStoreScope scope,
    Object error,
  ) {
    return PersistentWriteFailure(
      scope: scope,
      operation: operation,
      message: error.toString(),
      timestampMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  void dispose() {}
}
