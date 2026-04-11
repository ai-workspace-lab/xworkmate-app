import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'file_store_support.dart';
import 'runtime_models.dart';

enum SettingsSnapshotReloadStatus { applied, invalid }

class SettingsSnapshotReloadResult {
  const SettingsSnapshotReloadResult({
    required this.snapshot,
    required this.status,
  });

  final SettingsSnapshot snapshot;
  final SettingsSnapshotReloadStatus status;

  bool get applied => status == SettingsSnapshotReloadStatus.applied;
}

enum SkippedTaskThreadReason {
  incompleteWorkspaceBinding,
  removedAutoExecutionMode,
  invalidPersistedThreadData,
}

class SkippedTaskThreadRecord {
  const SkippedTaskThreadRecord({required this.threadId, required this.reason});

  final String threadId;
  final SkippedTaskThreadReason reason;
}

class SettingsStore {
  SettingsStore({
    Future<String?> Function()? appDataRootPathResolver,
    Future<String?> Function()? supportRootPathResolver,
    StoreLayoutResolver? layoutResolver,
  }) : _layoutResolver =
           layoutResolver ??
           StoreLayoutResolver(
             appDataRootPathResolver: appDataRootPathResolver,
             supportRootPathResolver: supportRootPathResolver,
           );

  final StoreLayoutResolver _layoutResolver;
  bool _initialized = false;
  StoreLayout? _layout;
  File? _settingsFile;
  Directory? _settingsWatchDirectory;
  SettingsSnapshot _settingsSnapshot = SettingsSnapshot.defaults();
  List<TaskThread> _threadRecords = const <TaskThread>[];
  List<SecretAuditEntry> _auditTrail = const <SecretAuditEntry>[];
  PersistentWriteFailure? _settingsWriteFailure;
  PersistentWriteFailure? _tasksWriteFailure;
  PersistentWriteFailure? _auditWriteFailure;
  List<SkippedTaskThreadRecord> _lastSkippedInvalidTaskThreadRecords =
      const <SkippedTaskThreadRecord>[];

  PersistentWriteFailure? get settingsWriteFailure => _settingsWriteFailure;
  PersistentWriteFailure? get tasksWriteFailure => _tasksWriteFailure;
  PersistentWriteFailure? get auditWriteFailure => _auditWriteFailure;
  List<SkippedTaskThreadRecord> get lastSkippedInvalidTaskThreadRecords =>
      List<SkippedTaskThreadRecord>.unmodifiable(
        _lastSkippedInvalidTaskThreadRecords,
      );
  List<String> get lastSkippedInvalidTaskThreadIds => List<String>.unmodifiable(
    _lastSkippedInvalidTaskThreadRecords
        .map((item) => item.threadId)
        .toList(growable: false),
  );

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;
    try {
      _layout = await _layoutResolver.resolve();
      _settingsFile = _layout!.settingsFile;
      _settingsWatchDirectory = _settingsFile!.parent;
    } catch (_) {
      _layout = null;
      _settingsFile = null;
      _settingsWatchDirectory = null;
      return;
    }
    _settingsSnapshot = await _readSettingsSnapshot();
    _threadRecords = await _readTaskThreads();
    _auditTrail = await _readAuditTrail();
  }

  Future<SettingsSnapshot> loadSettingsSnapshot() async {
    await initialize();
    return _settingsSnapshot;
  }

  Future<SettingsSnapshot> reloadSettingsSnapshot() async {
    final result = await reloadSettingsSnapshotResult();
    return result.snapshot;
  }

  Future<SettingsSnapshotReloadResult> reloadSettingsSnapshotResult() async {
    await initialize();
    final result = await _readSettingsSnapshotResult();
    if (result.status == SettingsSnapshotReloadStatus.invalid) {
      return SettingsSnapshotReloadResult(
        snapshot: _settingsSnapshot,
        status: SettingsSnapshotReloadStatus.invalid,
      );
    }
    _settingsSnapshot = result.snapshot;
    return SettingsSnapshotReloadResult(
      snapshot: _settingsSnapshot,
      status: SettingsSnapshotReloadStatus.applied,
    );
  }

  Future<File?> resolvedSettingsFile() async {
    await initialize();
    return _settingsFile;
  }

  Future<Directory?> resolvedSettingsWatchDirectory() async {
    await initialize();
    return _settingsWatchDirectory;
  }

  Future<void> saveSettingsSnapshot(SettingsSnapshot snapshot) async {
    await initialize();
    _settingsSnapshot = snapshot;
    final layout = _layout;
    if (layout == null) {
      _settingsWriteFailure = _buildWriteFailure(
        PersistentStoreScope.settings,
        'saveSettingsSnapshot',
        StateError('Persistent settings path unavailable; using memory only.'),
      );
      return;
    }
    try {
      final contents = encodeYamlDocument(snapshot.toJson());
      await atomicWriteString(layout.settingsFile, contents);
      _settingsWriteFailure = null;
    } catch (error) {
      _settingsWriteFailure = _buildWriteFailure(
        PersistentStoreScope.settings,
        'saveSettingsSnapshot',
        error,
      );
    }
  }

  Future<List<TaskThread>> loadTaskThreads() async {
    await initialize();
    return List<TaskThread>.from(_threadRecords);
  }

  Future<void> saveTaskThreads(List<TaskThread> records) async {
    await initialize();
    final normalized = records
        .where((item) => item.threadId.trim().isNotEmpty)
        .toList(growable: false);
    _threadRecords = normalized;
    final layout = _layout;
    if (layout == null) {
      _tasksWriteFailure = _buildWriteFailure(
        PersistentStoreScope.tasks,
        'saveTaskThreads',
        StateError('Persistent task path unavailable; using memory only.'),
      );
      return;
    }
    final keptPaths = <String>{};
    try {
      for (final record in normalized) {
        final taskFile = layout.taskFileForSessionKey(record.threadId);
        keptPaths.add(taskFile.path);
        await atomicWriteString(taskFile, jsonEncode(record.toJson()));
      }
      await atomicWriteString(
        layout.taskIndexFile,
        jsonEncode(<String, dynamic>{
          'version': taskThreadSchemaVersion,
          'sessions': normalized
              .map((item) => item.threadId)
              .toList(growable: false),
        }),
      );
      await for (final entity in layout.tasksDirectory.list()) {
        if (entity is! File) {
          continue;
        }
        if (entity.path == layout.taskIndexFile.path) {
          continue;
        }
        if (!entity.path.endsWith('.json')) {
          continue;
        }
        if (!keptPaths.contains(entity.path)) {
          await entity.delete();
        }
      }
      _tasksWriteFailure = null;
    } catch (error) {
      _tasksWriteFailure = _buildWriteFailure(
        PersistentStoreScope.tasks,
        'saveTaskThreads',
        error,
      );
    }
  }

  Future<void> clearAssistantLocalState() async {
    await initialize();
    _threadRecords = const <TaskThread>[];
    final layout = _layout;
    if (layout == null) {
      _tasksWriteFailure = _buildWriteFailure(
        PersistentStoreScope.tasks,
        'clearAssistantLocalState',
        StateError('Persistent task path unavailable; reset kept in memory.'),
      );
      return;
    }
    try {
      await deleteIfExists(layout.taskIndexFile);
      await for (final entity in layout.tasksDirectory.list()) {
        if (entity is File && entity.path.endsWith('.json')) {
          await entity.delete();
        }
      }
      _tasksWriteFailure = null;
    } catch (error) {
      _tasksWriteFailure = _buildWriteFailure(
        PersistentStoreScope.tasks,
        'clearAssistantLocalState',
        error,
      );
    }
  }

  Future<List<SecretAuditEntry>> loadAuditTrail() async {
    await initialize();
    return List<SecretAuditEntry>.from(_auditTrail);
  }

  Future<void> appendAudit(SecretAuditEntry entry) async {
    await initialize();
    final next = <SecretAuditEntry>[entry, ..._auditTrail];
    if (next.length > 40) {
      next.removeRange(40, next.length);
    }
    _auditTrail = next;
    final layout = _layout;
    if (layout == null) {
      _auditWriteFailure = _buildWriteFailure(
        PersistentStoreScope.audit,
        'appendAudit',
        StateError('Persistent audit path unavailable; audit kept in memory.'),
      );
      return;
    }
    try {
      await atomicWriteString(
        layout.auditFile,
        jsonEncode(next.map((item) => item.toJson()).toList(growable: false)),
      );
      _auditWriteFailure = null;
    } catch (error) {
      _auditWriteFailure = _buildWriteFailure(
        PersistentStoreScope.audit,
        'appendAudit',
        error,
      );
    }
  }

  void dispose() {}

  Future<SettingsSnapshot> _readSettingsSnapshot() async {
    final result = await _readSettingsSnapshotResult();
    return result.status == SettingsSnapshotReloadStatus.invalid
        ? SettingsSnapshot.defaults()
        : result.snapshot;
  }

  Future<SettingsSnapshotReloadResult> _readSettingsSnapshotResult() async {
    final settingsFile = _settingsFile;
    if (settingsFile == null) {
      return SettingsSnapshotReloadResult(
        snapshot: SettingsSnapshot.defaults(),
        status: SettingsSnapshotReloadStatus.applied,
      );
    }
    if (!await settingsFile.exists()) {
      return SettingsSnapshotReloadResult(
        snapshot: SettingsSnapshot.defaults(),
        status: SettingsSnapshotReloadStatus.applied,
      );
    }
    try {
      final raw = await settingsFile.readAsString();
      final decoded = decodeYamlDocument(raw);
      if (decoded is Map<String, dynamic>) {
        return SettingsSnapshotReloadResult(
          snapshot: SettingsSnapshot.fromJson(decoded),
          status: SettingsSnapshotReloadStatus.applied,
        );
      }
      if (decoded is Map) {
        return SettingsSnapshotReloadResult(
          snapshot: SettingsSnapshot.fromJson(decoded.cast<String, dynamic>()),
          status: SettingsSnapshotReloadStatus.applied,
        );
      }
    } catch (_) {
      return SettingsSnapshotReloadResult(
        snapshot: SettingsSnapshot.defaults(),
        status: SettingsSnapshotReloadStatus.invalid,
      );
    }
    return SettingsSnapshotReloadResult(
      snapshot: SettingsSnapshot.defaults(),
      status: SettingsSnapshotReloadStatus.invalid,
    );
  }

  Future<List<TaskThread>> _readTaskThreads() async {
    final layout = _layout;
    if (layout == null) {
      _lastSkippedInvalidTaskThreadRecords = const <SkippedTaskThreadRecord>[];
      return const <TaskThread>[];
    }
    _lastSkippedInvalidTaskThreadRecords = const <SkippedTaskThreadRecord>[];
    final index = await _readThreadIndex(layout);
    if (index.resetRequired) {
      await _resetTaskThreadState(layout);
      return const <TaskThread>[];
    }
    final orderedKeys = index.sessions;
    final recordsByKey = <String, TaskThread>{};
    final skippedRecords = <SkippedTaskThreadRecord>[];

    String inferThreadIdFromTaskFile(File file) {
      final name = file.uri.pathSegments.isEmpty
          ? file.path
          : file.uri.pathSegments.last;
      final encoded = name.endsWith('.json')
          ? name.substring(0, name.length - 5)
          : name;
      try {
        return utf8.decode(base64Url.decode(base64Url.normalize(encoded)));
      } catch (_) {
        return encoded;
      }
    }

    try {
      await for (final entity in layout.tasksDirectory.list()) {
        if (entity is! File ||
            entity.path == layout.taskIndexFile.path ||
            !entity.path.endsWith('.json')) {
          continue;
        }
        try {
          final raw = await entity.readAsString();
          final decoded = jsonDecode(raw);
          if (decoded is Map<String, dynamic>) {
            final schemaVersion = decoded['schemaVersion'];
            if (schemaVersion is! int ||
                schemaVersion != taskThreadSchemaVersion) {
              await _resetTaskThreadState(layout);
              return const <TaskThread>[];
            }
            final record = TaskThread.fromJson(decoded);
            if (record.threadId.trim().isNotEmpty) {
              recordsByKey[record.threadId] = record;
            }
          }
        } catch (error) {
          skippedRecords.add(
            SkippedTaskThreadRecord(
              threadId: inferThreadIdFromTaskFile(entity),
              reason: _classifySkippedTaskThreadReason(error),
            ),
          );
          continue;
        }
      }
    } catch (_) {
      return const <TaskThread>[];
    }
    final ordered = <TaskThread>[];
    for (final sessionKey in orderedKeys) {
      final record = recordsByKey.remove(sessionKey);
      if (record != null) {
        ordered.add(record);
      }
    }
    final leftovers = recordsByKey.keys.toList()..sort();
    for (final sessionKey in leftovers) {
      final record = recordsByKey[sessionKey];
      if (record != null) {
        ordered.add(record);
      }
    }
    skippedRecords.sort(
      (left, right) => left.threadId.compareTo(right.threadId),
    );
    _lastSkippedInvalidTaskThreadRecords = skippedRecords;
    return ordered;
  }

  SkippedTaskThreadReason _classifySkippedTaskThreadReason(Object error) {
    final message = error.toString();
    if (message.contains('"auto" is no longer supported')) {
      return SkippedTaskThreadReason.removedAutoExecutionMode;
    }
    if (message.contains('workspaceBinding')) {
      return SkippedTaskThreadReason.incompleteWorkspaceBinding;
    }
    return SkippedTaskThreadReason.invalidPersistedThreadData;
  }

  Future<_ThreadIndexReadResult> _readThreadIndex(StoreLayout layout) async {
    if (!await layout.taskIndexFile.exists()) {
      return const _ThreadIndexReadResult(
        sessions: <String>[],
        resetRequired: false,
      );
    }
    try {
      final raw = await layout.taskIndexFile.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final version = decoded['version'];
        if (version is! int || version != taskThreadSchemaVersion) {
          return const _ThreadIndexReadResult(
            sessions: <String>[],
            resetRequired: true,
          );
        }
        final sessions = decoded['sessions'];
        if (sessions is List) {
          return _ThreadIndexReadResult(
            sessions: sessions
                .map((item) => item.toString().trim())
                .where((item) => item.isNotEmpty)
                .toList(growable: false),
            resetRequired: false,
          );
        }
      }
    } catch (_) {}
    return const _ThreadIndexReadResult(
      sessions: <String>[],
      resetRequired: true,
    );
  }

  Future<void> _resetTaskThreadState(StoreLayout layout) async {
    try {
      await deleteIfExists(layout.taskIndexFile);
      await for (final entity in layout.tasksDirectory.list()) {
        if (entity is File && entity.path.endsWith('.json')) {
          await entity.delete();
        }
      }
    } catch (_) {
      // Best effort. A later save will normalize the directory.
    }
  }

  Future<List<SecretAuditEntry>> _readAuditTrail() async {
    final layout = _layout;
    if (layout == null || !await layout.auditFile.exists()) {
      return const <SecretAuditEntry>[];
    }
    try {
      final raw = await layout.auditFile.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map(
              (item) => SecretAuditEntry.fromJson(item.cast<String, dynamic>()),
            )
            .toList(growable: false);
      }
    } catch (_) {}
    return const <SecretAuditEntry>[];
  }

  PersistentWriteFailure _buildWriteFailure(
    PersistentStoreScope scope,
    String operation,
    Object error,
  ) {
    return PersistentWriteFailure(
      scope: scope,
      operation: operation,
      message: error.toString(),
      timestampMs: DateTime.now().millisecondsSinceEpoch,
    );
  }
}

class _ThreadIndexReadResult {
  const _ThreadIndexReadResult({
    required this.sessions,
    required this.resetRequired,
  });

  final List<String> sessions;
  final bool resetRequired;
}
