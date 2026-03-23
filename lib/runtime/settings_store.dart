import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'runtime_models.dart';

typedef SecureConfigDatabaseOpener =
    FutureOr<sqlite.Database?> Function(String resolvedPath);

class SettingsStore {
  SettingsStore({
    Future<String?> Function()? fallbackDirectoryPathResolver,
    Future<String?> Function()? databasePathResolver,
    Future<String?> Function()? defaultSupportDirectoryPathResolver,
    SecureConfigDatabaseOpener? databaseOpener,
  }) : _fallbackDirectoryPathResolver = fallbackDirectoryPathResolver,
       _databasePathResolver = databasePathResolver,
       _defaultSupportDirectoryPathResolver =
           defaultSupportDirectoryPathResolver,
       _databaseOpener = databaseOpener;

  static const String settingsKey = 'xworkmate.settings.snapshot';
  static const String auditKey = 'xworkmate.secrets.audit';
  static const String assistantThreadsKey = 'xworkmate.assistant.threads';
  static const String databaseFileName = 'config-store.sqlite3';
  static const String databaseTableName = 'config_entries';

  final Future<String?> Function()? _fallbackDirectoryPathResolver;
  final Future<String?> Function()? _databasePathResolver;
  final Future<String?> Function()? _defaultSupportDirectoryPathResolver;
  final SecureConfigDatabaseOpener? _databaseOpener;
  sqlite.Database? _database;
  String? _resolvedDatabasePath;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    await _initializeDatabase();
    _initialized = true;
  }

  Future<SettingsSnapshot> loadSettingsSnapshot() async {
    await initialize();
    final raw = await _readStoredString(settingsKey);
    return _decodeSettingsSnapshot(raw) ?? SettingsSnapshot.defaults();
  }

  Future<void> saveSettingsSnapshot(SettingsSnapshot snapshot) async {
    await initialize();
    final encoded = snapshot.toJsonString();
    await _writeStoredString(settingsKey, encoded);
  }

  Future<List<AssistantThreadRecord>> loadAssistantThreadRecords() async {
    await initialize();
    final raw = await _readStoredString(assistantThreadsKey);
    return _decodeAssistantThreadRecords(raw) ??
        const <AssistantThreadRecord>[];
  }

  Future<void> saveAssistantThreadRecords(
    List<AssistantThreadRecord> records,
  ) async {
    await initialize();
    final encoded = jsonEncode(
      records.map((item) => item.toJson()).toList(growable: false),
    );
    await _writeStoredString(assistantThreadsKey, encoded);
  }

  Future<void> clearAssistantLocalState() async {
    await initialize();
    await _deleteStoredString(settingsKey);
    await _deleteStoredString(assistantThreadsKey);
  }

  Future<List<SecretAuditEntry>> loadAuditTrail() async {
    await initialize();
    final raw = await _readStoredString(auditKey);
    if (raw == null || raw.trim().isEmpty) {
      return const <SecretAuditEntry>[];
    }
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map(
            (item) => SecretAuditEntry.fromJson(
              (item as Map).cast<String, dynamic>(),
            ),
          )
          .toList(growable: false);
    } catch (_) {
      return const <SecretAuditEntry>[];
    }
  }

  Future<void> appendAudit(SecretAuditEntry entry) async {
    final items = (await loadAuditTrail()).toList(growable: true);
    items.insert(0, entry);
    if (items.length > 40) {
      items.removeRange(40, items.length);
    }
    await _writeStoredString(
      auditKey,
      jsonEncode(items.map((item) => item.toJson()).toList(growable: false)),
    );
  }

  void dispose() {
    final database = _database;
    _database = null;
    if (database != null) {
      try {
        database.dispose();
      } catch (_) {
        // Ignore close errors during teardown.
      }
    }
    _initialized = false;
    _resolvedDatabasePath = null;
  }

  Future<void> _initializeDatabase() async {
    final resolvedPath = await _resolveDatabasePath();
    try {
      _database = await _openDatabase(resolvedPath);
      _resolvedDatabasePath = resolvedPath;
    } catch (error) {
      throw StateError(
        'Durable settings storage unavailable: failed to open $resolvedPath. Cause: $error',
      );
    }
  }

  Future<sqlite.Database> _openDatabase(String resolvedPath) async {
    if (_databaseOpener != null) {
      final database = await _databaseOpener(resolvedPath);
      if (database == null) {
        throw StateError(
          'Durable settings storage unavailable: database opener returned null for $resolvedPath.',
        );
      }
      _configureDatabase(database);
      return database;
    }
    final file = File(resolvedPath);
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    final database = sqlite.sqlite3.open(file.path);
    _configureDatabase(database);
    return database;
  }

  void _configureDatabase(sqlite.Database database) {
    database.execute('''
      CREATE TABLE IF NOT EXISTS $databaseTableName (
        storage_key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at_ms INTEGER NOT NULL
      )
    ''');
  }

  Future<String> _resolveDatabasePath() async {
    final resolved = _resolvedDatabasePath?.trim() ?? '';
    if (resolved.isNotEmpty) {
      return resolved;
    }
    final explicitDatabasePath = await _resolvePath(_databasePathResolver);
    if (explicitDatabasePath != null) {
      return explicitDatabasePath;
    }
    final fallbackRoot = await _resolvePath(_fallbackDirectoryPathResolver);
    if (fallbackRoot != null) {
      return '$fallbackRoot/$databaseFileName';
    }
    final defaultSupportRoot = await _resolvePath(
      _defaultSupportDirectoryPathResolver,
    );
    if (defaultSupportRoot != null) {
      return '$defaultSupportRoot/$databaseFileName';
    }
    try {
      final supportDirectory = await getApplicationSupportDirectory();
      return '${supportDirectory.path}/xworkmate/$databaseFileName';
    } catch (_) {
      throw StateError(
        'Durable settings storage unavailable: cannot resolve $databaseFileName.',
      );
    }
  }

  Future<String?> _readStoredString(String key) async {
    if (_database == null) {
      throw StateError(
        'Durable settings storage unavailable: database not initialized.',
      );
    }
    try {
      final result = _database!.select(
        'SELECT value FROM $databaseTableName WHERE storage_key = ? LIMIT 1',
        <Object?>[key],
      );
      if (result.isEmpty) {
        return null;
      }
      final value = result.first['value'];
      return value is String && value.trim().isNotEmpty ? value : null;
    } catch (_) {
      throw StateError(
        'Durable settings storage unavailable: failed to read $key from $_resolvedDatabasePath.',
      );
    }
  }

  Future<void> _writeStoredString(String key, String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return;
    }
    if (_database == null) {
      throw StateError(
        'Durable settings storage unavailable: database not initialized.',
      );
    }
    try {
      _database!.execute(
        '''
        INSERT INTO $databaseTableName (storage_key, value, updated_at_ms)
        VALUES (?, ?, ?)
        ON CONFLICT(storage_key) DO UPDATE SET
          value = excluded.value,
          updated_at_ms = excluded.updated_at_ms
        ''',
        <Object?>[key, trimmed, DateTime.now().millisecondsSinceEpoch],
      );
    } catch (_) {
      throw StateError(
        'Durable settings storage unavailable: failed to write $key to $_resolvedDatabasePath.',
      );
    }
  }

  Future<void> _deleteStoredString(String key) async {
    if (_database == null) {
      throw StateError(
        'Durable settings storage unavailable: database not initialized.',
      );
    }
    try {
      _database!.execute(
        'DELETE FROM $databaseTableName WHERE storage_key = ?',
        <Object?>[key],
      );
    } catch (_) {
      throw StateError(
        'Durable settings storage unavailable: failed to delete $key from $_resolvedDatabasePath.',
      );
    }
  }

  SettingsSnapshot? _decodeSettingsSnapshot(String? raw) {
    final trimmed = raw?.trim() ?? '';
    if (trimmed.isEmpty) {
      return null;
    }
    try {
      final decodedValue = jsonDecode(trimmed);
      if (decodedValue is! Map) {
        return null;
      }
      final decoded = decodedValue.cast<String, dynamic>();
      if (!_looksLikeSettingsSnapshot(decoded)) {
        return null;
      }
      return SettingsSnapshot.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  List<AssistantThreadRecord>? _decodeAssistantThreadRecords(String? raw) {
    final trimmed = raw?.trim() ?? '';
    if (trimmed.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(trimmed) as List<dynamic>;
      return decoded
          .whereType<Map>()
          .map(
            (item) =>
                AssistantThreadRecord.fromJson(item.cast<String, dynamic>()),
          )
          .toList(growable: false);
    } catch (_) {
      return null;
    }
  }

  bool _looksLikeSettingsSnapshot(Map<String, dynamic> json) {
    return json.containsKey('appLanguage') ||
        json.containsKey('gateway') ||
        json.containsKey('gatewayProfiles') ||
        json.containsKey('aiGateway') ||
        json.containsKey('accountUsername') ||
        json.containsKey('assistantExecutionTarget');
  }

  Future<String?> _resolvePath(Future<String?> Function()? resolver) async {
    if (resolver == null) {
      return null;
    }
    try {
      final resolved = await resolver();
      final trimmed = resolved?.trim() ?? '';
      return trimmed.isEmpty ? null : trimmed;
    } catch (_) {
      return null;
    }
  }
}
