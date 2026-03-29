import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'file_store_support.dart';
import 'runtime_models.dart';

typedef SecureConfigDatabaseOpener =
    FutureOr<Object?> Function(String resolvedPath);

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

class SettingsStore {
  SettingsStore({
    Future<String?> Function()? fallbackDirectoryPathResolver,
    Future<String?> Function()? databasePathResolver,
    Future<String?> Function()? defaultSupportDirectoryPathResolver,
    SecureConfigDatabaseOpener? databaseOpener,
    StoreLayoutResolver? layoutResolver,
  }) : _layoutResolver =
           layoutResolver ??
           StoreLayoutResolver(
             localRootPathResolver: databasePathResolver,
             supportRootPathResolver: defaultSupportDirectoryPathResolver,
           ),
       _enableUserSettingsMirror =
           databasePathResolver == null &&
           defaultSupportDirectoryPathResolver == null;

  static const String settingsKey = 'xworkmate.settings.snapshot';
  static const String auditKey = 'xworkmate.secrets.audit';
  static const String assistantThreadsKey = 'xworkmate.assistant.threads';
  static const String databaseFileName = 'config-store.sqlite3';
  static const String databaseTableName = 'config_entries';

  final StoreLayoutResolver _layoutResolver;
  final bool _enableUserSettingsMirror;
  bool _initialized = false;
  StoreLayout? _layout;
  List<File> _settingsFiles = const <File>[];
  List<Directory> _settingsWatchDirectories = const <Directory>[];
  SettingsSnapshot _settingsSnapshot = SettingsSnapshot.defaults();
  List<TaskThread> _threadRecords = const <TaskThread>[];
  List<SecretAuditEntry> _auditTrail = const <SecretAuditEntry>[];
  PersistentWriteFailure? _settingsWriteFailure;
  PersistentWriteFailure? _tasksWriteFailure;
  PersistentWriteFailure? _auditWriteFailure;
  bool _taskThreadStateResetRequired = false;

  PersistentWriteFailure? get settingsWriteFailure => _settingsWriteFailure;
  PersistentWriteFailure? get tasksWriteFailure => _tasksWriteFailure;
  PersistentWriteFailure? get auditWriteFailure => _auditWriteFailure;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;
    try {
      _layout = await _layoutResolver.resolve();
      _settingsFiles = _resolveSettingsFiles(_layout!);
      _settingsWatchDirectories = _resolveSettingsWatchDirectories(
        _settingsFiles,
      );
    } catch (_) {
      _layout = null;
      _settingsFiles = const <File>[];
      _settingsWatchDirectories = const <Directory>[];
      return;
    }
    _settingsSnapshot = await _readSettingsSnapshot();
    _threadRecords = await _readTaskThreads();
    if (_taskThreadStateResetRequired) {
      _settingsSnapshot = _settingsSnapshot.copyWith(
        assistantCustomTaskTitles: const <String, String>{},
        assistantArchivedTaskKeys: const <String>[],
        assistantLastSessionKey: '',
      );
      final layout = _layout;
      if (layout != null) {
        try {
          final contents = encodeYamlDocument(_settingsSnapshot.toJson());
          for (final file
              in _settingsFiles.isEmpty
                  ? <File>[layout.settingsFile]
                  : _settingsFiles) {
            await atomicWriteString(file, contents);
          }
          _settingsWriteFailure = null;
        } catch (error) {
          _settingsWriteFailure = _buildWriteFailure(
            PersistentStoreScope.settings,
            'resetTaskThreadState',
            error,
          );
        }
      }
    }
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

  Future<List<File>> resolvedSettingsFiles() async {
    await initialize();
    return List<File>.from(_settingsFiles);
  }

  Future<List<Directory>> resolvedSettingsWatchDirectories() async {
    await initialize();
    return List<Directory>.from(_settingsWatchDirectories);
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
      for (final file
          in _settingsFiles.isEmpty
              ? <File>[layout.settingsFile]
              : _settingsFiles) {
        await atomicWriteString(file, contents);
      }
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

  Future<void> saveTaskThreads(
    List<TaskThread> records,
  ) async {
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
    final nextSnapshot = _settingsSnapshot.copyWith(
      assistantCustomTaskTitles: const <String, String>{},
      assistantArchivedTaskKeys: const <String>[],
      assistantLastSessionKey: '',
    );
    _settingsSnapshot = nextSnapshot;
    _threadRecords = const <TaskThread>[];
    final layout = _layout;
    if (layout == null) {
      _settingsWriteFailure = _buildWriteFailure(
        PersistentStoreScope.settings,
        'clearAssistantLocalState',
        StateError(
          'Persistent settings path unavailable; reset kept in memory.',
        ),
      );
      _tasksWriteFailure = _buildWriteFailure(
        PersistentStoreScope.tasks,
        'clearAssistantLocalState',
        StateError('Persistent task path unavailable; reset kept in memory.'),
      );
      return;
    }
    try {
      final settingsFiles = _settingsFiles.isEmpty
          ? <File>[layout.settingsFile]
          : _settingsFiles;
      for (final file in settingsFiles) {
        await atomicWriteString(file, encodeYamlDocument(nextSnapshot.toJson()));
      }
      _settingsWriteFailure = null;
    } catch (error) {
      _settingsWriteFailure = _buildWriteFailure(
        PersistentStoreScope.settings,
        'clearAssistantLocalState',
        error,
      );
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
    if (_settingsFiles.isEmpty) {
      return SettingsSnapshotReloadResult(
        snapshot: SettingsSnapshot.defaults(),
        status: SettingsSnapshotReloadStatus.applied,
      );
    }
    var sawExistingFile = false;
    var sawInvalidFile = false;
    for (final file in _settingsFiles) {
      if (!await file.exists()) {
        continue;
      }
      sawExistingFile = true;
      try {
        final raw = await file.readAsString();
        final decoded = decodeYamlDocument(raw);
        if (decoded is Map) {
          return SettingsSnapshotReloadResult(
            snapshot: SettingsSnapshot.fromJson(
              decoded.cast<String, dynamic>(),
            ),
            status: SettingsSnapshotReloadStatus.applied,
          );
        }
        sawInvalidFile = true;
      } catch (_) {
        sawInvalidFile = true;
      }
    }
    return SettingsSnapshotReloadResult(
      snapshot: SettingsSnapshot.defaults(),
      status: sawExistingFile && sawInvalidFile
          ? SettingsSnapshotReloadStatus.invalid
          : SettingsSnapshotReloadStatus.applied,
    );
  }

  List<File> _resolveSettingsFiles(StoreLayout layout) {
    final resolved = <File>[];
    final seen = <String>{};

    void addPath(String path) {
      final normalized = path.trim();
      if (normalized.isEmpty || !seen.add(normalized)) {
        return;
      }
      resolved.add(File(normalized));
    }

    final userPath = _enableUserSettingsMirror
        ? defaultUserSettingsFilePath()
        : null;
    if ((userPath ?? '').isNotEmpty) {
      addPath(userPath!);
    }
    addPath(layout.settingsFile.path);
    return List<File>.unmodifiable(resolved);
  }

  List<Directory> _resolveSettingsWatchDirectories(List<File> files) {
    final directories = <Directory>[];
    final seen = <String>{};
    for (final file in files) {
      final path = file.parent.path.trim();
      if (path.isEmpty || !seen.add(path)) {
        continue;
      }
      directories.add(Directory(path));
    }
    return List<Directory>.unmodifiable(directories);
  }

  Future<List<TaskThread>> _readTaskThreads() async {
    final layout = _layout;
    if (layout == null) {
      return const <TaskThread>[];
    }
    final index = await _readThreadIndex(layout);
    if (index.resetRequired) {
      await _resetTaskThreadState(layout);
      _taskThreadStateResetRequired = true;
      return const <TaskThread>[];
    }
    _taskThreadStateResetRequired = false;
    final orderedKeys = index.sessions;
    final recordsByKey = <String, TaskThread>{};
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
              _taskThreadStateResetRequired = true;
              return const <TaskThread>[];
            }
            final record = TaskThread.fromJson(decoded);
            if (record.threadId.trim().isNotEmpty) {
              recordsByKey[record.threadId] = record;
            }
          }
        } catch (_) {
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
    return ordered;
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
