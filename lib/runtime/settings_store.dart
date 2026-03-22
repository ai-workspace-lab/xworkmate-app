import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'legacy_settings_recovery.dart';
import 'runtime_models.dart';

typedef SecureConfigDatabaseOpener =
    FutureOr<sqlite.Database?> Function(String resolvedPath);

class SettingsStore {
  SettingsStore({
    Future<String?> Function()? fallbackDirectoryPathResolver,
    Future<String?> Function()? databasePathResolver,
    SecureConfigDatabaseOpener? databaseOpener,
    Future<List<int>?> Function()? legacyLocalStateKeyLoader,
  }) : _fallbackDirectoryPathResolver = fallbackDirectoryPathResolver,
       _databasePathResolver = databasePathResolver,
       _databaseOpener = databaseOpener,
       _legacyLocalStateKeyLoader = legacyLocalStateKeyLoader;

  static const String settingsKey = 'xworkmate.settings.snapshot';
  static const String auditKey = 'xworkmate.secrets.audit';
  static const String assistantThreadsKey = 'xworkmate.assistant.threads';
  static const String databaseFileName = 'config-store.sqlite3';
  static const String databaseTableName = 'config_entries';
  static const String stateBackupFileName = 'assistant-state-backup.json';
  static const String sealedStateFormat = 'xworkmate.sealed.local-state.v1';

  static const Map<String, String> _durableStateFileNames = <String, String>{
    settingsKey: 'settings-snapshot.json',
    assistantThreadsKey: 'assistant-threads.json',
  };

  final Future<String?> Function()? _fallbackDirectoryPathResolver;
  final Future<String?> Function()? _databasePathResolver;
  final SecureConfigDatabaseOpener? _databaseOpener;
  final Future<List<int>?> Function()? _legacyLocalStateKeyLoader;
  final Cipher _legacyCipher = AesGcm.with256bits();
  final Map<String, String> _memoryStore = <String, String>{};
  SharedPreferences? _prefs;
  sqlite.Database? _database;
  bool _initialized = false;
  bool _recoveryAttempted = false;
  LegacyRecoveryReport _lastRecoveryReport = const LegacyRecoveryReport();

  LegacyRecoveryReport get lastRecoveryReport => _lastRecoveryReport;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    try {
      _prefs = await SharedPreferences.getInstance();
    } catch (_) {
      _prefs = null;
    }
    await _initializeDatabase();
    _initialized = true;
  }

  Future<SettingsSnapshot> loadSettingsSnapshot() async {
    await initialize();
    await _ensureLegacyRecoveryIfNeeded();
    final raw = await _readStoredString(settingsKey);
    return _decodeSettingsSnapshot(raw) ?? SettingsSnapshot.defaults();
  }

  Future<void> saveSettingsSnapshot(SettingsSnapshot snapshot) async {
    await initialize();
    final encoded = snapshot.toJsonString();
    await _writeStoredString(settingsKey, encoded);
    await _writeDurableStateFile(settingsKey, encoded);
    _lastRecoveryReport = const LegacyRecoveryReport();
  }

  Future<List<AssistantThreadRecord>> loadAssistantThreadRecords() async {
    await initialize();
    await _ensureLegacyRecoveryIfNeeded();
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
    await _writeDurableStateFile(assistantThreadsKey, encoded);
  }

  Future<void> clearAssistantLocalState() async {
    await initialize();
    await _deleteStoredString(settingsKey);
    await _deleteStoredString(assistantThreadsKey);
    await _deleteDurableStateFile(settingsKey);
    await _deleteDurableStateFile(assistantThreadsKey);
    await _deleteLegacyBackupFile();
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
    _prefs = null;
    _initialized = false;
    _memoryStore.clear();
  }

  Future<void> _initializeDatabase() async {
    final resolvedPath = await _resolveDatabasePath();
    if (resolvedPath != null && resolvedPath.trim().isNotEmpty) {
      try {
        _database = await _openDatabase(resolvedPath);
      } catch (_) {
        _database = null;
      }
    }
    if (_database == null) {
      try {
        final database = sqlite.sqlite3.openInMemory();
        _configureDatabase(database);
        _database = database;
      } catch (_) {
        _database = null;
      }
    }
    await _migrateLegacyPrefs();
  }

  Future<sqlite.Database?> _openDatabase(String resolvedPath) async {
    if (_databaseOpener != null) {
      final database = await _databaseOpener(resolvedPath);
      if (database != null) {
        _configureDatabase(database);
      }
      return database;
    }
    final file = File(resolvedPath);
    await file.parent.create(recursive: true);
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

  Future<void> _migrateLegacyPrefs() async {
    if (_database == null || _prefs == null) {
      return;
    }
    await _migrateLegacyPrefEntry(settingsKey);
    await _migrateLegacyPrefEntry(auditKey);
    await _migrateLegacyPrefEntry(assistantThreadsKey);
  }

  Future<void> _migrateLegacyPrefEntry(String key) async {
    if (_database == null || _prefs == null) {
      return;
    }
    final legacyValue = _prefs!.getString(key);
    if (legacyValue == null || legacyValue.trim().isEmpty) {
      return;
    }
    final existing = _database!.select(
      'SELECT value FROM $databaseTableName WHERE storage_key = ? LIMIT 1',
      <Object?>[key],
    );
    if (existing.isEmpty) {
      await _writeStoredString(key, legacyValue);
      if (_durableStateFileNames.containsKey(key)) {
        await _writeDurableStateFile(key, legacyValue);
      }
    }
    await _prefs!.remove(key);
  }

  Future<void> _ensureLegacyRecoveryIfNeeded() async {
    if (_recoveryAttempted) {
      return;
    }
    _recoveryAttempted = true;

    final currentSettingsRaw = await _readStoredString(settingsKey);
    final currentThreadsRaw = await _readStoredString(assistantThreadsKey);
    final hasReadableCurrentState =
        _decodeSettingsSnapshot(currentSettingsRaw) != null ||
        _decodeAssistantThreadRecords(currentThreadsRaw) != null;
    if (hasReadableCurrentState) {
      _lastRecoveryReport = const LegacyRecoveryReport();
      return;
    }

    final recovery = await _attemptLegacyRecovery(
      currentSettingsRaw: currentSettingsRaw,
      currentThreadsRaw: currentThreadsRaw,
    );
    _lastRecoveryReport = recovery;
  }

  Future<LegacyRecoveryReport> _attemptLegacyRecovery({
    required String? currentSettingsRaw,
    required String? currentThreadsRaw,
  }) async {
    final lockedSources = <String>[];
    final candidates = await _legacyCandidateDirectories();
    for (final directory in candidates) {
      final source = await _readLegacySource(directory);
      if (source.locked) {
        lockedSources.add(source.sourcePath);
      }
      if (source.settings != null || source.threads != null) {
        final recoveredSettings =
            source.settings ?? SettingsSnapshot.defaults();
        final recoveredThreads =
            source.threads ?? const <AssistantThreadRecord>[];
        await _writeStoredString(settingsKey, recoveredSettings.toJsonString());
        await _writeStoredString(
          assistantThreadsKey,
          jsonEncode(
            recoveredThreads
                .map((item) => item.toJson())
                .toList(growable: false),
          ),
        );
        await _writeDurableStateFile(
          settingsKey,
          recoveredSettings.toJsonString(),
        );
        await _writeDurableStateFile(
          assistantThreadsKey,
          jsonEncode(
            recoveredThreads
                .map((item) => item.toJson())
                .toList(growable: false),
          ),
        );
        return LegacyRecoveryReport(
          status: LegacyRecoveryStatus.migrated,
          sourcePath: source.sourcePath,
          details:
              'Recovered legacy settings into the new plain settings store.',
        );
      }
    }

    final currentLocked =
        _isSealedLocalState(currentSettingsRaw) ||
        _isSealedLocalState(currentThreadsRaw);
    if (currentLocked || lockedSources.isNotEmpty) {
      return LegacyRecoveryReport(
        status: LegacyRecoveryStatus.lockedLegacyState,
        sourcePath: lockedSources.isNotEmpty ? lockedSources.first : null,
        details:
            'Detected legacy encrypted state but could not restore the local-state key.',
      );
    }
    return const LegacyRecoveryReport();
  }

  Future<List<String>> _legacyCandidateDirectories() async {
    final results = <String>{};
    final databasePath = await _resolveDatabasePath();
    final fallbackRoot = await _fallbackDirectoryPathResolver?.call();
    String? supportPath;
    try {
      supportPath = (await getApplicationSupportDirectory()).path;
    } catch (_) {
      supportPath = null;
    }

    void addPath(String? path) {
      final trimmed = path?.trim() ?? '';
      if (trimmed.isEmpty) {
        return;
      }
      results.add(trimmed);
    }

    if (databasePath != null && databasePath.trim().isNotEmpty) {
      final directory = File(databasePath).parent.path;
      addPath(directory);
      addPath(Directory(directory).parent.path);
    }
    addPath(fallbackRoot);
    addPath(fallbackRoot == null ? null : '$fallbackRoot/xworkmate');
    addPath(supportPath);
    addPath(supportPath == null ? null : '$supportPath/xworkmate');
    return results.toList(growable: false);
  }

  Future<_LegacySourceResult> _readLegacySource(String directoryPath) async {
    final settingsFromDatabase = await _readLegacyDatabaseEntry(
      directoryPath,
      settingsKey,
    );
    final threadsFromDatabase = await _readLegacyDatabaseEntry(
      directoryPath,
      assistantThreadsKey,
    );
    final settingsFromFile = await _readLegacyDurableState(
      directoryPath,
      settingsKey,
    );
    final threadsFromFile = await _readLegacyDurableState(
      directoryPath,
      assistantThreadsKey,
    );
    final backup = await _readLegacyBackup(directoryPath);

    final settings =
        settingsFromDatabase.snapshot ??
        settingsFromFile.snapshot ??
        backup.snapshot?.settings;
    final threads =
        threadsFromDatabase.threads ??
        threadsFromFile.threads ??
        backup.snapshot?.assistantThreads;
    final locked =
        settingsFromDatabase.locked ||
        threadsFromDatabase.locked ||
        settingsFromFile.locked ||
        threadsFromFile.locked ||
        backup.locked;
    return _LegacySourceResult(
      sourcePath: directoryPath,
      settings: settings,
      threads: threads,
      locked: locked,
    );
  }

  Future<_LegacyStateReadResult> _readLegacyDatabaseEntry(
    String directoryPath,
    String key,
  ) async {
    final databaseFile = File('$directoryPath/$databaseFileName');
    if (!await databaseFile.exists()) {
      return const _LegacyStateReadResult();
    }
    try {
      final database =
          (_database != null &&
              await _resolveDatabasePath() == databaseFile.path)
          ? _database
          : sqlite.sqlite3.open(databaseFile.path);
      final result = database!.select(
        'SELECT value FROM $databaseTableName WHERE storage_key = ? LIMIT 1',
        <Object?>[key],
      );
      if (!identical(database, _database)) {
        database.dispose();
      }
      if (result.isEmpty) {
        return const _LegacyStateReadResult();
      }
      final raw = result.first['value'] as String?;
      return _decodeLegacyValue(raw, key);
    } catch (_) {
      return const _LegacyStateReadResult();
    }
  }

  Future<_LegacyStateReadResult> _readLegacyDurableState(
    String directoryPath,
    String key,
  ) async {
    final fileName = _durableStateFileNames[key];
    if (fileName == null) {
      return const _LegacyStateReadResult();
    }
    final file = File('$directoryPath/$fileName');
    if (!await file.exists()) {
      return const _LegacyStateReadResult();
    }
    try {
      final raw = await file.readAsString();
      return _decodeLegacyValue(raw, key);
    } catch (_) {
      return const _LegacyStateReadResult();
    }
  }

  Future<_LegacyBackupReadResult> _readLegacyBackup(
    String directoryPath,
  ) async {
    final file = File('$directoryPath/$stateBackupFileName');
    if (!await file.exists()) {
      return const _LegacyBackupReadResult();
    }
    try {
      final decoded =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final sealedState = decoded['sealedState'];
      if (sealedState is String && sealedState.trim().isNotEmpty) {
        final plaintext = await _decryptLegacyValue(
          '_assistant_state_backup',
          sealedState,
        );
        if (plaintext == null) {
          return const _LegacyBackupReadResult(locked: true);
        }
        final payload = jsonDecode(plaintext) as Map<String, dynamic>;
        return _LegacyBackupReadResult(
          snapshot: _AssistantStateSnapshot(
            settings: SettingsSnapshot.fromJson(
              (payload['settings'] as Map?)?.cast<String, dynamic>() ??
                  const {},
            ),
            assistantThreads:
                ((payload['assistantThreads'] as List?) ?? const [])
                    .whereType<Map>()
                    .map(
                      (item) => AssistantThreadRecord.fromJson(
                        item.cast<String, dynamic>(),
                      ),
                    )
                    .toList(growable: false),
          ),
        );
      }
      final settings = SettingsSnapshot.fromJson(
        (decoded['settings'] as Map?)?.cast<String, dynamic>() ?? const {},
      );
      final threads = ((decoded['assistantThreads'] as List?) ?? const [])
          .whereType<Map>()
          .map(
            (item) =>
                AssistantThreadRecord.fromJson(item.cast<String, dynamic>()),
          )
          .toList(growable: false);
      return _LegacyBackupReadResult(
        snapshot: _AssistantStateSnapshot(
          settings: settings,
          assistantThreads: threads,
        ),
      );
    } catch (_) {
      return const _LegacyBackupReadResult();
    }
  }

  Future<_LegacyStateReadResult> _decodeLegacyValue(
    String? raw,
    String key,
  ) async {
    final trimmed = raw?.trim() ?? '';
    if (trimmed.isEmpty) {
      return const _LegacyStateReadResult();
    }
    final plainSettings = key == settingsKey
        ? _decodeSettingsSnapshot(trimmed)
        : null;
    final plainThreads = key == assistantThreadsKey
        ? _decodeAssistantThreadRecords(trimmed)
        : null;
    if (plainSettings != null || plainThreads != null) {
      return _LegacyStateReadResult(
        snapshot: plainSettings,
        threads: plainThreads,
      );
    }
    if (!_isSealedLocalState(trimmed)) {
      return const _LegacyStateReadResult();
    }
    final decrypted = await _decryptLegacyValue(key, trimmed);
    if (decrypted == null) {
      return const _LegacyStateReadResult(locked: true);
    }
    return _LegacyStateReadResult(
      snapshot: key == settingsKey ? _decodeSettingsSnapshot(decrypted) : null,
      threads: key == assistantThreadsKey
          ? _decodeAssistantThreadRecords(decrypted)
          : null,
    );
  }

  Future<String?> _decryptLegacyValue(String key, String persisted) async {
    final keyBytes = await _legacyLocalStateKeyLoader?.call();
    if (keyBytes == null || keyBytes.isEmpty) {
      return null;
    }
    try {
      final envelope = jsonDecode(persisted) as Map<String, dynamic>;
      final secretBox = SecretBox(
        _base64UrlDecode(envelope['cipherText'] as String? ?? ''),
        nonce: _base64UrlDecode(envelope['nonce'] as String? ?? ''),
        mac: Mac(_base64UrlDecode(envelope['mac'] as String? ?? '')),
      );
      final clearText = await _legacyCipher.decrypt(
        secretBox,
        secretKey: SecretKey(keyBytes),
        aad: utf8.encode(key),
      );
      return utf8.decode(clearText);
    } catch (_) {
      return null;
    }
  }

  Future<String?> _resolveDatabasePath() async {
    try {
      final resolvedPath = await _databasePathResolver?.call();
      final trimmed = resolvedPath?.trim() ?? '';
      if (trimmed.isNotEmpty) {
        return trimmed;
      }
    } catch (_) {
      // Fall through to the default locations.
    }
    try {
      final supportDirectory = await getApplicationSupportDirectory();
      return '${supportDirectory.path}/xworkmate/$databaseFileName';
    } catch (_) {
      final fallbackRoot = await _fallbackDirectoryPathResolver?.call();
      final trimmed = fallbackRoot?.trim() ?? '';
      if (trimmed.isEmpty) {
        return null;
      }
      return '$trimmed/$databaseFileName';
    }
  }

  Future<String?> _readStoredString(String key) async {
    final memoryValue = _memoryStore[key];
    if (memoryValue != null) {
      return memoryValue;
    }
    if (_database != null) {
      try {
        final result = _database!.select(
          'SELECT value FROM $databaseTableName WHERE storage_key = ? LIMIT 1',
          <Object?>[key],
        );
        if (result.isNotEmpty) {
          final value = result.first['value'];
          if (value is String && value.trim().isNotEmpty) {
            return value;
          }
        }
      } catch (_) {
        // Fall through to durable fallback.
      }
    }
    final durable = await _readDurableStateFile(key);
    if (durable != null) {
      return durable;
    }
    try {
      final prefValue = _prefs?.getString(key);
      if (prefValue != null && prefValue.trim().isNotEmpty) {
        return prefValue;
      }
    } catch (_) {
      // Ignore.
    }
    return null;
  }

  Future<void> _writeStoredString(String key, String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return;
    }
    _memoryStore[key] = trimmed;
    if (_database != null) {
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
        return;
      } catch (_) {
        // Fall through to durable file fallback.
      }
    }
  }

  Future<void> _deleteStoredString(String key) async {
    _memoryStore.remove(key);
    if (_database != null) {
      try {
        _database!.execute(
          'DELETE FROM $databaseTableName WHERE storage_key = ?',
          <Object?>[key],
        );
      } catch (_) {
        // Ignore.
      }
    }
    try {
      await _prefs?.remove(key);
    } catch (_) {
      // Ignore.
    }
  }

  Future<File?> _durableStateFile(String key) async {
    final fileName = _durableStateFileNames[key];
    if (fileName == null) {
      return null;
    }
    final databasePath = await _resolveDatabasePath();
    if (databasePath == null || databasePath.trim().isEmpty) {
      return null;
    }
    final directory = File(databasePath).parent;
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return File('${directory.path}/$fileName');
  }

  Future<String?> _readDurableStateFile(String key) async {
    final file = await _durableStateFile(key);
    if (file == null || !await file.exists()) {
      return null;
    }
    final value = await file.readAsString();
    return value.trim().isEmpty ? null : value;
  }

  Future<void> _writeDurableStateFile(String key, String value) async {
    final file = await _durableStateFile(key);
    if (file == null) {
      return;
    }
    await file.writeAsString(value, flush: true);
  }

  Future<void> _deleteDurableStateFile(String key) async {
    final file = await _durableStateFile(key);
    if (file == null || !await file.exists()) {
      return;
    }
    await file.delete();
  }

  Future<void> _deleteLegacyBackupFile() async {
    final databasePath = await _resolveDatabasePath();
    if (databasePath == null || databasePath.trim().isEmpty) {
      return;
    }
    final file = File('${File(databasePath).parent.path}/$stateBackupFileName');
    if (await file.exists()) {
      await file.delete();
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
      if (decoded['storageFormat'] == sealedStateFormat ||
          !_looksLikeSettingsSnapshot(decoded)) {
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

  bool _isSealedLocalState(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return false;
    }
    try {
      final decoded = jsonDecode(trimmed);
      return decoded is Map<String, dynamic> &&
          decoded['storageFormat'] == sealedStateFormat;
    } catch (_) {
      return false;
    }
  }

  static List<int> _base64UrlDecode(String value) {
    final normalized = value.replaceAll('-', '+').replaceAll('_', '/');
    final padded = normalized + '=' * ((4 - normalized.length % 4) % 4);
    return base64.decode(padded);
  }

  bool _looksLikeSettingsSnapshot(Map<String, dynamic> json) {
    return json.containsKey('appLanguage') ||
        json.containsKey('gateway') ||
        json.containsKey('aiGateway') ||
        json.containsKey('accountUsername') ||
        json.containsKey('assistantExecutionTarget');
  }
}

class _LegacySourceResult {
  const _LegacySourceResult({
    required this.sourcePath,
    this.settings,
    this.threads,
    this.locked = false,
  });

  final String sourcePath;
  final SettingsSnapshot? settings;
  final List<AssistantThreadRecord>? threads;
  final bool locked;
}

class _LegacyStateReadResult {
  const _LegacyStateReadResult({
    this.snapshot,
    this.threads,
    this.locked = false,
  });

  final SettingsSnapshot? snapshot;
  final List<AssistantThreadRecord>? threads;
  final bool locked;
}

class _AssistantStateSnapshot {
  const _AssistantStateSnapshot({
    required this.settings,
    required this.assistantThreads,
  });

  final SettingsSnapshot settings;
  final List<AssistantThreadRecord> assistantThreads;
}

class _LegacyBackupReadResult {
  const _LegacyBackupReadResult({this.snapshot, this.locked = false});

  final _AssistantStateSnapshot? snapshot;
  final bool locked;
}
