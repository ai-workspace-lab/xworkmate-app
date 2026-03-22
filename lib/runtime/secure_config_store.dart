import 'dart:convert';
import 'dart:io';

import '../app/app_metadata.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'runtime_models.dart';

class SecureConfigStore {
  SecureConfigStore({
    Future<String?> Function()? fallbackDirectoryPathResolver,
    Future<String?> Function()? databasePathResolver,
    bool enableSecureStorage = true,
  }) : _fallbackDirectoryPathResolver = fallbackDirectoryPathResolver,
       _databasePathResolver = databasePathResolver,
       _enableSecureStorage = enableSecureStorage;

  static const _settingsKey = 'xworkmate.settings.snapshot';
  static const _auditKey = 'xworkmate.secrets.audit';
  static const _assistantThreadsKey = 'xworkmate.assistant.threads';
  static const _databaseFileName = 'config-store.sqlite3';
  static const _databaseTableName = 'config_entries';
  static const _stateBackupFileName = 'assistant-state-backup.json';
  static const _backupSchemaVersion = 1;
  static const _secureStorageTimeout = Duration(milliseconds: 400);

  static const _gatewayTokenKey = 'xworkmate.gateway.token';
  static const _gatewayPasswordKey = 'xworkmate.gateway.password';
  static const _gatewayDeviceIdKey = 'xworkmate.gateway.device.id';
  static const _gatewayDevicePublicKeyKey =
      'xworkmate.gateway.device.public_key';
  static const _gatewayDevicePrivateKeyKey =
      'xworkmate.gateway.device.private_key';
  static const _deviceIdentityFallbackFileName = 'gateway-device-identity.json';
  static const _ollamaCloudApiKeyKey = 'xworkmate.ollama.cloud.api_key';
  static const _vaultTokenKey = 'xworkmate.vault.token';
  static const _aiGatewayApiKeyKey = 'xworkmate.ai_gateway.api_key';

  SharedPreferences? _prefs;
  sqlite.Database? _database;
  FlutterSecureStorage? _secureStorage;
  final Map<String, String> _memoryStore = <String, String>{};
  final Map<String, String> _memorySecure = <String, String>{};
  final Future<String?> Function()? _fallbackDirectoryPathResolver;
  final Future<String?> Function()? _databasePathResolver;
  final bool _enableSecureStorage;
  bool _initialized = false;

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
    if (_enableSecureStorage) {
      try {
        _secureStorage = const FlutterSecureStorage();
      } catch (_) {
        _secureStorage = null;
      }
    }
    _initialized = true;
  }

  Future<SettingsSnapshot> loadSettingsSnapshot() async {
    await initialize();
    final state = await _loadAssistantStateFromPrimaryOrBackup();
    return state?.settings ?? SettingsSnapshot.defaults();
  }

  Future<void> saveSettingsSnapshot(SettingsSnapshot snapshot) async {
    await initialize();
    await _writeStoredString(_settingsKey, snapshot.toJsonString());
    await _persistAssistantStateBackup(settings: snapshot);
  }

  Future<List<AssistantThreadRecord>> loadAssistantThreadRecords() async {
    await initialize();
    final state = await _loadAssistantStateFromPrimaryOrBackup();
    return state?.assistantThreads ?? const <AssistantThreadRecord>[];
  }

  Future<void> saveAssistantThreadRecords(
    List<AssistantThreadRecord> records,
  ) async {
    await initialize();
    await _writeStoredString(
      _assistantThreadsKey,
      jsonEncode(records.map((item) => item.toJson()).toList(growable: false)),
    );
    await _persistAssistantStateBackup(assistantThreads: records);
  }

  Future<void> clearAssistantLocalState() async {
    await initialize();
    await _deleteStoredString(_settingsKey);
    await _deleteStoredString(_assistantThreadsKey);
    await _deleteAssistantStateBackup();
  }

  Future<List<SecretAuditEntry>> loadAuditTrail() async {
    await initialize();
    final raw = await _readStoredString(_auditKey);
    if (raw == null || raw.trim().isEmpty) {
      return const [];
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
      return const [];
    }
  }

  Future<void> appendAudit(SecretAuditEntry entry) async {
    final items = (await loadAuditTrail()).toList(growable: true);
    items.insert(0, entry);
    if (items.length > 40) {
      items.removeRange(40, items.length);
    }
    await _writeStoredString(
      _auditKey,
      jsonEncode(items.map((item) => item.toJson()).toList(growable: false)),
    );
  }

  Future<String?> loadGatewayToken() => _readSecure(_gatewayTokenKey);

  Future<void> saveGatewayToken(String value) =>
      _writeSecure(_gatewayTokenKey, value);

  Future<void> clearGatewayToken() => _deleteSecure(_gatewayTokenKey);

  Future<String?> loadGatewayPassword() => _readSecure(_gatewayPasswordKey);

  Future<void> saveGatewayPassword(String value) =>
      _writeSecure(_gatewayPasswordKey, value);

  Future<void> clearGatewayPassword() => _deleteSecure(_gatewayPasswordKey);

  Future<String?> loadOllamaCloudApiKey() => _readSecure(_ollamaCloudApiKeyKey);

  Future<void> saveOllamaCloudApiKey(String value) =>
      _writeSecure(_ollamaCloudApiKeyKey, value);

  Future<String?> loadVaultToken() => _readSecure(_vaultTokenKey);

  Future<void> saveVaultToken(String value) =>
      _writeSecure(_vaultTokenKey, value);

  Future<String?> loadAiGatewayApiKey() => _readSecure(_aiGatewayApiKeyKey);

  Future<void> saveAiGatewayApiKey(String value) =>
      _writeSecure(_aiGatewayApiKeyKey, value);

  Future<void> clearAiGatewayApiKey() => _deleteSecure(_aiGatewayApiKeyKey);

  Future<LocalDeviceIdentity?> loadDeviceIdentity() async {
    await initialize();
    final deviceId = await _readSecure(_gatewayDeviceIdKey);
    final publicKey = await _readSecure(_gatewayDevicePublicKeyKey);
    final privateKey = await _readSecure(_gatewayDevicePrivateKeyKey);
    if (deviceId == null || publicKey == null || privateKey == null) {
      final fallbackIdentity = await _loadDeviceIdentityFallback();
      if (fallbackIdentity != null) {
        await saveDeviceIdentity(fallbackIdentity);
      }
      return fallbackIdentity;
    }
    return LocalDeviceIdentity(
      deviceId: deviceId,
      publicKeyBase64Url: publicKey,
      privateKeyBase64Url: privateKey,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<void> saveDeviceIdentity(LocalDeviceIdentity identity) async {
    await initialize();
    await _writeSecure(_gatewayDeviceIdKey, identity.deviceId);
    await _writeSecure(_gatewayDevicePublicKeyKey, identity.publicKeyBase64Url);
    await _writeSecure(
      _gatewayDevicePrivateKeyKey,
      identity.privateKeyBase64Url,
    );
    await _saveDeviceIdentityFallback(identity);
  }

  Future<String?> loadDeviceToken({
    required String deviceId,
    required String role,
  }) async {
    await initialize();
    final secureValue = await _readSecure(_deviceTokenKey(deviceId, role));
    if (secureValue != null && secureValue.trim().isNotEmpty) {
      return secureValue;
    }
    final fallbackValue = await _loadDeviceTokenFallback(
      deviceId: deviceId,
      role: role,
    );
    if (fallbackValue != null && fallbackValue.trim().isNotEmpty) {
      await saveDeviceToken(
        deviceId: deviceId,
        role: role,
        token: fallbackValue,
      );
      return fallbackValue;
    }
    return null;
  }

  Future<void> saveDeviceToken({
    required String deviceId,
    required String role,
    required String token,
  }) async {
    await initialize();
    await _writeSecure(_deviceTokenKey(deviceId, role), token);
    await _saveDeviceTokenFallback(
      deviceId: deviceId,
      role: role,
      token: token,
    );
  }

  Future<void> clearDeviceToken({
    required String deviceId,
    required String role,
  }) async {
    await initialize();
    await _deleteSecure(_deviceTokenKey(deviceId, role));
    await _deleteDeviceTokenFallback(deviceId: deviceId, role: role);
  }

  Future<Map<String, String>> loadSecureRefs() async {
    await initialize();
    final gatewayToken = await loadGatewayToken();
    final gatewayPassword = await loadGatewayPassword();
    final deviceIdentity = await loadDeviceIdentity();
    final deviceToken = deviceIdentity == null
        ? null
        : await loadDeviceToken(
            deviceId: deviceIdentity.deviceId,
            role: 'operator',
          );
    final ollamaKey = await loadOllamaCloudApiKey();
    final vaultToken = await loadVaultToken();
    final aiGatewayApiKey = await loadAiGatewayApiKey();
    return {
      ...?gatewayToken == null
          ? null
          : <String, String>{'gateway_token': gatewayToken},
      ...?gatewayPassword == null
          ? null
          : <String, String>{'gateway_password': gatewayPassword},
      ...?deviceToken == null
          ? null
          : <String, String>{'gateway_device_token_operator': deviceToken},
      ...?ollamaKey == null
          ? null
          : <String, String>{'ollama_cloud_api_key': ollamaKey},
      ...?vaultToken == null
          ? null
          : <String, String>{'vault_token': vaultToken},
      ...?aiGatewayApiKey == null
          ? null
          : <String, String>{'ai_gateway_api_key': aiGatewayApiKey},
    };
  }

  Future<void> _initializeDatabase() async {
    final resolvedPath = await _resolveDatabasePath();
    if (resolvedPath != null && resolvedPath.trim().isNotEmpty) {
      try {
        final file = File(resolvedPath);
        await file.parent.create(recursive: true);
        final database = sqlite.sqlite3.open(file.path);
        _configureDatabase(database);
        _database = database;
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

  void _configureDatabase(sqlite.Database database) {
    database.execute('''
      CREATE TABLE IF NOT EXISTS $_databaseTableName (
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
    await _migrateLegacyPrefEntry(_settingsKey);
    await _migrateLegacyPrefEntry(_auditKey);
    await _migrateLegacyPrefEntry(_assistantThreadsKey);
  }

  Future<void> _migrateLegacyPrefEntry(String key) async {
    if (_database == null || _prefs == null) {
      return;
    }
    try {
      final existing = _database!.select(
        'SELECT value FROM $_databaseTableName WHERE storage_key = ? LIMIT 1',
        <Object?>[key],
      );
      if (existing.isNotEmpty) {
        return;
      }
      final legacyValue = _prefs!.getString(key);
      if (legacyValue == null || legacyValue.trim().isEmpty) {
        return;
      }
      _writeStoredStringInternal(key, legacyValue);
    } catch (_) {
      return;
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
      return '${supportDirectory.path}/xworkmate/$_databaseFileName';
    } catch (_) {
      final fallbackRoot = await _fallbackDirectoryPathResolver?.call();
      final trimmed = fallbackRoot?.trim() ?? '';
      if (trimmed.isEmpty) {
        return null;
      }
      return '$trimmed/$_databaseFileName';
    }
  }

  Future<String?> _readStoredString(String key) async {
    if (_database != null) {
      try {
        final result = _database!.select(
          'SELECT value FROM $_databaseTableName WHERE storage_key = ? LIMIT 1',
          <Object?>[key],
        );
        if (result.isNotEmpty) {
          final value = result.first['value'];
          if (value is String) {
            return value;
          }
        }
      } catch (_) {
        // Fall through to the in-memory fallback.
      }
    }
    return _memoryStore[key];
  }

  Future<void> _deleteStoredString(String key) async {
    if (_database != null) {
      try {
        _database!.execute(
          'DELETE FROM $_databaseTableName WHERE storage_key = ?',
          <Object?>[key],
        );
      } catch (_) {
        // Fall through to in-memory cleanup.
      }
    }
    _memoryStore.remove(key);
    try {
      await _prefs?.remove(key);
    } catch (_) {
      // Ignore preference cleanup failures.
    }
  }

  Future<void> _writeStoredString(String key, String value) async {
    if (_database != null) {
      try {
        _writeStoredStringInternal(key, value);
        return;
      } catch (_) {
        // Fall through to the in-memory fallback.
      }
    }
    _memoryStore[key] = value;
  }

  Future<_AssistantStateSnapshot?>
  _loadAssistantStateFromPrimaryOrBackup() async {
    final rawSettings = await _readStoredString(_settingsKey);
    final rawThreads = await _readStoredString(_assistantThreadsKey);
    final decodedSettings = _decodeSettingsSnapshot(rawSettings);
    final decodedThreads = _decodeAssistantThreadRecords(rawThreads);
    final primaryHasSettings = rawSettings != null;
    final primaryHasThreads = rawThreads != null;
    final primaryValid =
        decodedSettings != null &&
        decodedThreads != null &&
        primaryHasSettings &&
        primaryHasThreads;
    if (primaryValid) {
      return _AssistantStateSnapshot(
        settings: decodedSettings,
        assistantThreads: decodedThreads,
      );
    }
    final backup = await _readAssistantStateBackup();
    if (backup == null) {
      return _AssistantStateSnapshot(
        settings: decodedSettings ?? SettingsSnapshot.defaults(),
        assistantThreads: decodedThreads ?? const <AssistantThreadRecord>[],
      );
    }
    await _writeStoredString(_settingsKey, backup.settings.toJsonString());
    await _writeStoredString(
      _assistantThreadsKey,
      jsonEncode(
        backup.assistantThreads
            .map((item) => item.toJson())
            .toList(growable: false),
      ),
    );
    return backup;
  }

  SettingsSnapshot? _decodeSettingsSnapshot(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return SettingsSnapshot.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  List<AssistantThreadRecord>? _decodeAssistantThreadRecords(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
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

  Future<void> _persistAssistantStateBackup({
    SettingsSnapshot? settings,
    List<AssistantThreadRecord>? assistantThreads,
  }) async {
    final resolvedSettings = settings ?? await loadSettingsSnapshot();
    final resolvedThreads =
        assistantThreads ?? await loadAssistantThreadRecords();
    final payload = _AssistantStateSnapshot(
      settings: resolvedSettings,
      assistantThreads: resolvedThreads,
    );
    try {
      final file = await _assistantStateBackupFile();
      if (file == null) {
        return;
      }
      await file.writeAsString(
        jsonEncode(<String, dynamic>{
          'schemaVersion': _backupSchemaVersion,
          'appVersion': kAppVersion,
          'backupCreatedAtMs': DateTime.now().millisecondsSinceEpoch,
          'settings': payload.settings.toJson(),
          'assistantThreads': payload.assistantThreads
              .map((item) => item.toJson())
              .toList(growable: false),
        }),
        flush: true,
      );
    } catch (_) {
      return;
    }
  }

  Future<_AssistantStateSnapshot?> _readAssistantStateBackup() async {
    try {
      final file = await _assistantStateBackupFile();
      if (file == null || !await file.exists()) {
        return null;
      }
      final decoded =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
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
      return _AssistantStateSnapshot(
        settings: settings,
        assistantThreads: threads,
      );
    } catch (_) {
      return null;
    }
  }

  Future<File?> _assistantStateBackupFile() async {
    try {
      final resolvedPath = await _resolveDatabasePath();
      if (resolvedPath == null || resolvedPath.trim().isEmpty) {
        return null;
      }
      final directory = File(resolvedPath).parent;
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      return File('${directory.path}/$_stateBackupFileName');
    } catch (_) {
      return null;
    }
  }

  Future<void> _deleteAssistantStateBackup() async {
    try {
      final file = await _assistantStateBackupFile();
      if (file == null || !await file.exists()) {
        return;
      }
      await file.delete();
    } catch (_) {
      return;
    }
  }

  void _writeStoredStringInternal(String key, String value) {
    if (_database == null) {
      _memoryStore[key] = value;
      return;
    }
    _database!.execute(
      '''
      INSERT INTO $_databaseTableName (storage_key, value, updated_at_ms)
      VALUES (?, ?, ?)
      ON CONFLICT(storage_key) DO UPDATE SET
        value = excluded.value,
        updated_at_ms = excluded.updated_at_ms
      ''',
      <Object?>[key, value, DateTime.now().millisecondsSinceEpoch],
    );
  }

  Future<String?> _readSecure(String key) async {
    if (_secureStorage != null) {
      try {
        return await _secureStorage!
            .read(key: key)
            .timeout(_secureStorageTimeout);
      } catch (_) {
        _secureStorage = null;
        // Fall back to in-memory storage for tests and unsupported runners.
      }
    }
    return _memorySecure[key];
  }

  Future<void> _writeSecure(String key, String value) async {
    if (_secureStorage != null) {
      try {
        await _secureStorage!
            .write(key: key, value: value)
            .timeout(_secureStorageTimeout);
        return;
      } catch (_) {
        _secureStorage = null;
        // Fall back to in-memory storage for tests and unsupported runners.
      }
    }
    _memorySecure[key] = value;
  }

  Future<void> _deleteSecure(String key) async {
    if (_secureStorage != null) {
      try {
        await _secureStorage!.delete(key: key).timeout(_secureStorageTimeout);
      } catch (_) {
        _secureStorage = null;
        // Keep the in-memory fallback in sync.
      }
    }
    _memorySecure.remove(key);
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
    _secureStorage = null;
    _initialized = false;
    _memoryStore.clear();
    _memorySecure.clear();
  }

  static String maskValue(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return 'Not set';
    }
    if (trimmed.length <= 6) {
      return '••••••';
    }
    return '${trimmed.substring(0, 3)}••••${trimmed.substring(trimmed.length - 3)}';
  }

  static String _deviceTokenKey(String deviceId, String role) {
    final safeRole = role.trim().isEmpty ? 'operator' : role.trim();
    return 'xworkmate.gateway.device_token.$deviceId.$safeRole';
  }

  static String _deviceTokenFallbackFileName(String deviceId, String role) {
    final safeRole = role.trim().isEmpty ? 'operator' : role.trim();
    return 'gateway-device-token.$deviceId.$safeRole.txt';
  }

  Future<Directory?> _resolveFallbackDirectory() async {
    try {
      final resolvedPath =
          await _fallbackDirectoryPathResolver?.call() ??
          await _defaultFallbackDirectoryPath();
      final trimmed = resolvedPath?.trim() ?? '';
      if (trimmed.isEmpty) {
        return null;
      }
      final directory = Directory(trimmed);
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      return directory;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _defaultFallbackDirectoryPath() async {
    try {
      final supportDirectory = await getApplicationSupportDirectory();
      return '${supportDirectory.path}/xworkmate/gateway-auth';
    } catch (_) {
      return null;
    }
  }

  Future<File?> _deviceIdentityFallbackFile() async {
    final directory = await _resolveFallbackDirectory();
    if (directory == null) {
      return null;
    }
    return File('${directory.path}/$_deviceIdentityFallbackFileName');
  }

  Future<File?> _deviceTokenFallbackFile({
    required String deviceId,
    required String role,
  }) async {
    final directory = await _resolveFallbackDirectory();
    if (directory == null) {
      return null;
    }
    return File(
      '${directory.path}/${_deviceTokenFallbackFileName(deviceId, role)}',
    );
  }

  Future<LocalDeviceIdentity?> _loadDeviceIdentityFallback() async {
    try {
      final file = await _deviceIdentityFallbackFile();
      if (file == null || !await file.exists()) {
        return null;
      }
      final decoded =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final identity = LocalDeviceIdentity.fromJson(decoded);
      if (identity.deviceId.trim().isEmpty ||
          identity.publicKeyBase64Url.trim().isEmpty ||
          identity.privateKeyBase64Url.trim().isEmpty) {
        return null;
      }
      return identity;
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveDeviceIdentityFallback(LocalDeviceIdentity identity) async {
    try {
      final file = await _deviceIdentityFallbackFile();
      if (file == null) {
        return;
      }
      await file.writeAsString(jsonEncode(identity.toJson()), flush: true);
    } catch (_) {
      return;
    }
  }

  Future<String?> _loadDeviceTokenFallback({
    required String deviceId,
    required String role,
  }) async {
    try {
      final file = await _deviceTokenFallbackFile(
        deviceId: deviceId,
        role: role,
      );
      if (file == null || !await file.exists()) {
        return null;
      }
      final value = (await file.readAsString()).trim();
      return value.isEmpty ? null : value;
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveDeviceTokenFallback({
    required String deviceId,
    required String role,
    required String token,
  }) async {
    try {
      final file = await _deviceTokenFallbackFile(
        deviceId: deviceId,
        role: role,
      );
      if (file == null) {
        return;
      }
      await file.writeAsString(token, flush: true);
    } catch (_) {
      return;
    }
  }

  Future<void> _deleteDeviceTokenFallback({
    required String deviceId,
    required String role,
  }) async {
    try {
      final file = await _deviceTokenFallbackFile(
        deviceId: deviceId,
        role: role,
      );
      if (file == null || !await file.exists()) {
        return;
      }
      await file.delete();
    } catch (_) {
      return;
    }
  }
}

class _AssistantStateSnapshot {
  const _AssistantStateSnapshot({
    required this.settings,
    required this.assistantThreads,
  });

  final SettingsSnapshot settings;
  final List<AssistantThreadRecord> assistantThreads;
}
