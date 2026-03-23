import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'file_store_support.dart';
import 'runtime_models.dart';

typedef SecureConfigDatabaseOpener =
    FutureOr<Object?> Function(String resolvedPath);

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
           );

  static const String settingsKey = 'xworkmate.settings.snapshot';
  static const String auditKey = 'xworkmate.secrets.audit';
  static const String assistantThreadsKey = 'xworkmate.assistant.threads';
  static const String databaseFileName = 'config-store.sqlite3';
  static const String databaseTableName = 'config_entries';

  final StoreLayoutResolver _layoutResolver;
  bool _initialized = false;
  StoreLayout? _layout;
  SettingsSnapshot _settingsSnapshot = SettingsSnapshot.defaults();
  List<AssistantThreadRecord> _threadRecords = const <AssistantThreadRecord>[];
  List<SecretAuditEntry> _auditTrail = const <SecretAuditEntry>[];
  PersistentWriteFailure? _settingsWriteFailure;
  PersistentWriteFailure? _tasksWriteFailure;
  PersistentWriteFailure? _auditWriteFailure;

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
    } catch (_) {
      _layout = null;
      return;
    }
    _settingsSnapshot = await _readSettingsSnapshot();
    _threadRecords = await _readAssistantThreadRecords();
    _auditTrail = await _readAuditTrail();
  }

  Future<SettingsSnapshot> loadSettingsSnapshot() async {
    await initialize();
    return _settingsSnapshot;
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
      await atomicWriteString(
        layout.settingsFile,
        encodeYamlDocument(snapshot.toJson()),
      );
      _settingsWriteFailure = null;
    } catch (error) {
      _settingsWriteFailure = _buildWriteFailure(
        PersistentStoreScope.settings,
        'saveSettingsSnapshot',
        error,
      );
    }
  }

  Future<List<AssistantThreadRecord>> loadAssistantThreadRecords() async {
    await initialize();
    return List<AssistantThreadRecord>.from(_threadRecords);
  }

  Future<void> saveAssistantThreadRecords(
    List<AssistantThreadRecord> records,
  ) async {
    await initialize();
    final normalized = records
        .where((item) => item.sessionKey.trim().isNotEmpty)
        .toList(growable: false);
    _threadRecords = normalized;
    final layout = _layout;
    if (layout == null) {
      _tasksWriteFailure = _buildWriteFailure(
        PersistentStoreScope.tasks,
        'saveAssistantThreadRecords',
        StateError('Persistent task path unavailable; using memory only.'),
      );
      return;
    }
    final keptPaths = <String>{};
    try {
      for (final record in normalized) {
        final taskFile = layout.taskFileForSessionKey(record.sessionKey);
        keptPaths.add(taskFile.path);
        await atomicWriteString(taskFile, jsonEncode(record.toJson()));
      }
      await atomicWriteString(
        layout.taskIndexFile,
        jsonEncode(<String, dynamic>{
          'version': 1,
          'sessions': normalized
              .map((item) => item.sessionKey)
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
        'saveAssistantThreadRecords',
        error,
      );
    }
  }

  Future<void> clearAssistantLocalState() async {
    await initialize();
    _settingsSnapshot = SettingsSnapshot.defaults();
    _threadRecords = const <AssistantThreadRecord>[];
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
      await deleteIfExists(layout.settingsFile);
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
    final layout = _layout;
    if (layout == null || !await layout.settingsFile.exists()) {
      return SettingsSnapshot.defaults();
    }
    try {
      final raw = await layout.settingsFile.readAsString();
      final decoded = decodeYamlDocument(raw);
      if (decoded is Map) {
        return SettingsSnapshot.fromJson(decoded.cast<String, dynamic>());
      }
    } catch (_) {}
    return SettingsSnapshot.defaults();
  }

  Future<List<AssistantThreadRecord>> _readAssistantThreadRecords() async {
    final layout = _layout;
    if (layout == null) {
      return const <AssistantThreadRecord>[];
    }
    final orderedKeys = await _readThreadIndex(layout);
    final recordsByKey = <String, AssistantThreadRecord>{};
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
            final record = AssistantThreadRecord.fromJson(decoded);
            if (record.sessionKey.trim().isNotEmpty) {
              recordsByKey[record.sessionKey] = record;
            }
          }
        } catch (_) {
          continue;
        }
      }
    } catch (_) {
      return const <AssistantThreadRecord>[];
    }
    final ordered = <AssistantThreadRecord>[];
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

  Future<List<String>> _readThreadIndex(StoreLayout layout) async {
    if (!await layout.taskIndexFile.exists()) {
      return const <String>[];
    }
    try {
      final raw = await layout.taskIndexFile.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final sessions = decoded['sessions'];
        if (sessions is List) {
          return sessions
              .map((item) => item.toString().trim())
              .where((item) => item.isNotEmpty)
              .toList(growable: false);
        }
      }
    } catch (_) {}
    return const <String>[];
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
