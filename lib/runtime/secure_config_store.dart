import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../app/app_metadata.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'runtime_models.dart';

class SecureConfigStore {
  SecureConfigStore({
    Future<String?> Function()? fallbackDirectoryPathResolver,
    Future<String?> Function()? databasePathResolver,
    SecureConfigDatabaseOpener? databaseOpener,
    SecureStorageClient? secureStorage,
    bool enableSecureStorage = true,
  }) : _fallbackDirectoryPathResolver = fallbackDirectoryPathResolver,
       _databasePathResolver = databasePathResolver,
       _databaseOpener = databaseOpener,
       _secureStorageOverride = secureStorage,
       _enableSecureStorage = enableSecureStorage;

  static const _settingsKey = 'xworkmate.settings.snapshot';
  static const _auditKey = 'xworkmate.secrets.audit';
  static const _assistantThreadsKey = 'xworkmate.assistant.threads';
  static const _databaseFileName = 'config-store.sqlite3';
  static const _databaseTableName = 'config_entries';
  static const _stateBackupFileName = 'assistant-state-backup.json';
  static const _backupSchemaVersion = 2;
  static const _secureStorageTimeout = Duration(seconds: 5);
  static const _localStateKeyKey = 'xworkmate.local_state.key';
  static const _sealedStateFormat = 'xworkmate.sealed.local-state.v1';
  static const _assistantStateBackupStorageKey =
      'xworkmate.assistant.state.backup';

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
  SecureStorageClient? _secureStorage;
  final Map<String, String> _memoryStore = <String, String>{};
  final Map<String, String> _memorySecure = <String, String>{};
  final Future<String?> Function()? _fallbackDirectoryPathResolver;
  final Future<String?> Function()? _databasePathResolver;
  final SecureConfigDatabaseOpener? _databaseOpener;
  final SecureStorageClient? _secureStorageOverride;
  final bool _enableSecureStorage;
  bool _initialized = false;
  final Cipher _localStateCipher = AesGcm.with256bits();
  final Random _random = Random.secure();
  Future<void> _localStateWriteQueue = Future<void>.value();

  static const Map<String, String> _durableStateFileNames = <String, String>{
    _settingsKey: 'settings-snapshot.json',
    _assistantThreadsKey: 'assistant-threads.json',
  };

  static const Map<String, String> _secureFallbackFileNames = <String, String>{
    _gatewayTokenKey: 'gateway-token.txt',
    _gatewayPasswordKey: 'gateway-password.txt',
    _ollamaCloudApiKeyKey: 'ollama-cloud-api-key.txt',
    _vaultTokenKey: 'vault-token.txt',
    _aiGatewayApiKeyKey: 'ai-gateway-api-key.txt',
  };

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    try {
      _prefs = await SharedPreferences.getInstance();
    } catch (_) {
      _prefs = null;
    }
    if (_enableSecureStorage) {
      if (_secureStorageOverride != null) {
        _secureStorage = _secureStorageOverride;
      } else if (_useDebugSecureStorageFallback()) {
        _secureStorage = _buildDebugSecureStorageClient();
      } else {
        try {
          _secureStorage = FlutterSecureStorageClient(
            const FlutterSecureStorage(),
          );
        } catch (_) {
          _secureStorage = null;
        }
      }
    }
    await _initializeDatabase();
    _initialized = true;
  }

  Future<SettingsSnapshot> loadSettingsSnapshot() async {
    await initialize();
    final state = await _loadAssistantStateFromPrimaryOrBackup();
    return state?.settings ?? SettingsSnapshot.defaults();
  }

  Future<void> saveSettingsSnapshot(SettingsSnapshot snapshot) async {
    await _enqueueLocalStateWrite(() async {
      await initialize();
      final encoded = snapshot.toJsonString();
      await _writeStoredString(_settingsKey, encoded);
      await _writeDurableStateFile(_settingsKey, encoded);
      await _persistAssistantStateBackup(settings: snapshot);
    });
  }

  Future<List<AssistantThreadRecord>> loadAssistantThreadRecords() async {
    await initialize();
    final state = await _loadAssistantStateFromPrimaryOrBackup();
    return state?.assistantThreads ?? const <AssistantThreadRecord>[];
  }

  Future<void> saveAssistantThreadRecords(
    List<AssistantThreadRecord> records,
  ) async {
    await _enqueueLocalStateWrite(() async {
      await initialize();
      final encoded = jsonEncode(
        records.map((item) => item.toJson()).toList(growable: false),
      );
      await _writeStoredString(_assistantThreadsKey, encoded);
      await _writeDurableStateFile(_assistantThreadsKey, encoded);
      await _persistAssistantStateBackup(assistantThreads: records);
    });
  }

  Future<void> clearAssistantLocalState() async {
    await _enqueueLocalStateWrite(() async {
      await initialize();
      await _deleteStoredString(_settingsKey);
      await _deleteStoredString(_assistantThreadsKey);
      await _deleteDurableStateFile(_settingsKey);
      await _deleteDurableStateFile(_assistantThreadsKey);
      await _deleteAssistantStateBackup();
    });
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
      final legacyValue = _prefs!.getString(key);
      if (legacyValue == null || legacyValue.trim().isEmpty) {
        return;
      }
      final existing = _database!.select(
        'SELECT value FROM $_databaseTableName WHERE storage_key = ? LIMIT 1',
        <Object?>[key],
      );
      if (existing.isEmpty) {
        await _writeStoredString(key, legacyValue);
        if (_durableStateFileNames.containsKey(key)) {
          await _writeDurableStateFile(key, legacyValue);
        }
      }
      await _prefs!.remove(key);
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
    final memoryValue = _memoryStore[key];
    if (memoryValue != null) {
      final restored = await _restorePersistedValue(key, memoryValue);
      if (restored != null) {
        return restored;
      }
    }
    if (_database != null) {
      try {
        final result = _database!.select(
          'SELECT value FROM $_databaseTableName WHERE storage_key = ? LIMIT 1',
          <Object?>[key],
        );
        if (result.isNotEmpty) {
          final value = result.first['value'];
          if (value is String) {
            final restored = await _restorePersistedValue(key, value);
            if (restored != null) {
              return restored;
            }
          }
        }
      } catch (_) {
        // Fall through to durable and in-memory fallback.
      }
    }
    final durableValue = await _readDurableStateFile(key);
    if (durableValue != null) {
      return durableValue;
    }
    return null;
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
    await _deleteDurableStateFile(key);
    try {
      await _prefs?.remove(key);
    } catch (_) {
      // Ignore preference cleanup failures.
    }
  }

  Future<void> _writeStoredString(String key, String value) async {
    final persistedValue = await _preparePersistedValue(key, value);
    if (persistedValue == null) {
      return;
    }
    _memoryStore[key] = persistedValue;
    if (_database != null) {
      try {
        _writeStoredStringInternal(key, persistedValue);
        return;
      } catch (_) {
        // Fall through to durable and in-memory fallback.
      }
    }
    await _writeDurableStateFile(key, value);
  }

  Future<_AssistantStateSnapshot?>
  _loadAssistantStateFromPrimaryOrBackup() async {
    final rawSettings = await _readStoredString(_settingsKey);
    final rawThreads = await _readStoredString(_assistantThreadsKey);
    final rawSettingsSealed = _isSealedLocalState(rawSettings);
    final rawThreadsSealed = _isSealedLocalState(rawThreads);
    final decodedSettings = _decodeSettingsSnapshot(rawSettings);
    final decodedThreads = _decodeAssistantThreadRecords(rawThreads);
    final backupRead = await _readAssistantStateBackup();
    final backup = backupRead?.snapshot;
    final backupWasSealed = backupRead?.sealed ?? false;
    final resolvedSettings =
        decodedSettings ?? backup?.settings ?? SettingsSnapshot.defaults();
    final resolvedThreads =
        decodedThreads ??
        backup?.assistantThreads ??
        const <AssistantThreadRecord>[];
    final defaultSettings = SettingsSnapshot.defaults();
    final encodedSettings = resolvedSettings.toJsonString();
    final defaultEncodedSettings = defaultSettings.toJsonString();
    final encodedThreads = jsonEncode(
      resolvedThreads.map((item) => item.toJson()).toList(growable: false),
    );
    final hasMeaningfulState =
        rawSettings != null ||
        rawThreads != null ||
        backup != null ||
        encodedSettings != defaultEncodedSettings ||
        resolvedThreads.isNotEmpty;

    if (hasMeaningfulState &&
        (rawSettings == null ||
            !rawSettingsSealed ||
            decodedSettings == null)) {
      await _writeStoredString(_settingsKey, encodedSettings);
    }
    if (hasMeaningfulState &&
        (rawThreads == null || !rawThreadsSealed || decodedThreads == null)) {
      await _writeStoredString(_assistantThreadsKey, encodedThreads);
    }
    if (hasMeaningfulState) {
      await _writeDurableStateFile(_settingsKey, encodedSettings);
      await _writeDurableStateFile(_assistantThreadsKey, encodedThreads);
    }

    if (hasMeaningfulState &&
        (backup == null ||
            !backupWasSealed ||
            jsonEncode(backup.settings.toJson()) !=
                jsonEncode(resolvedSettings.toJson()) ||
            jsonEncode(
                  backup.assistantThreads
                      .map((item) => item.toJson())
                      .toList(growable: false),
                ) !=
                encodedThreads)) {
      await _persistAssistantStateBackup(
        settings: resolvedSettings,
        assistantThreads: resolvedThreads,
      );
    }
    return _AssistantStateSnapshot(
      settings: resolvedSettings,
      assistantThreads: resolvedThreads,
    );
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
      final plaintext = jsonEncode(<String, dynamic>{
        'settings': payload.settings.toJson(),
        'assistantThreads': payload.assistantThreads
            .map((item) => item.toJson())
            .toList(growable: false),
      });
      final sealedPayload = await _sealLocalState(
        _assistantStateBackupStorageKey,
        plaintext,
      );
      await file.writeAsString(
        jsonEncode(<String, dynamic>{
          'schemaVersion': _backupSchemaVersion,
          'appVersion': kAppVersion,
          'backupCreatedAtMs': DateTime.now().millisecondsSinceEpoch,
          'sealedState': sealedPayload,
        }),
        flush: true,
      );
    } catch (_) {
      return;
    }
  }

  Future<_AssistantStateBackupReadResult?> _readAssistantStateBackup() async {
    try {
      final file = await _assistantStateBackupFile();
      if (file == null || !await file.exists()) {
        return null;
      }
      final decoded =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final sealedState = decoded['sealedState'];
      if (sealedState is String && sealedState.trim().isNotEmpty) {
        final plaintext = await _restoreLocalState(
          _assistantStateBackupStorageKey,
          sealedState,
        );
        if (plaintext == null || plaintext.trim().isEmpty) {
          return null;
        }
        final payload = jsonDecode(plaintext) as Map<String, dynamic>;
        final settings = SettingsSnapshot.fromJson(
          (payload['settings'] as Map?)?.cast<String, dynamic>() ?? const {},
        );
        final threads = ((payload['assistantThreads'] as List?) ?? const [])
            .whereType<Map>()
            .map(
              (item) =>
                  AssistantThreadRecord.fromJson(item.cast<String, dynamic>()),
            )
            .toList(growable: false);
        return _AssistantStateBackupReadResult(
          snapshot: _AssistantStateSnapshot(
            settings: settings,
            assistantThreads: threads,
          ),
          sealed: true,
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
      return _AssistantStateBackupReadResult(
        snapshot: _AssistantStateSnapshot(
          settings: settings,
          assistantThreads: threads,
        ),
        sealed: false,
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

  Future<File?> _durableStateFile(String key) async {
    final fileName = _durableStateFileNames[key];
    if (fileName == null) {
      return null;
    }
    try {
      final resolvedPath = await _resolveDatabasePath();
      if (resolvedPath == null || resolvedPath.trim().isEmpty) {
        return null;
      }
      final directory = File(resolvedPath).parent;
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      return File('${directory.path}/$fileName');
    } catch (_) {
      return null;
    }
  }

  Future<String?> _readDurableStateFile(String key) async {
    try {
      final file = await _durableStateFile(key);
      if (file == null || !await file.exists()) {
        return null;
      }
      final value = await file.readAsString();
      if (value.trim().isEmpty) {
        return null;
      }
      return _restorePersistedValue(key, value);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeDurableStateFile(String key, String value) async {
    try {
      final file = await _durableStateFile(key);
      if (file == null) {
        return;
      }
      final persistedValue = await _preparePersistedValue(key, value);
      if (persistedValue == null) {
        return;
      }
      await file.writeAsString(persistedValue, flush: true);
    } catch (_) {
      return;
    }
  }

  Future<void> _deleteDurableStateFile(String key) async {
    try {
      final file = await _durableStateFile(key);
      if (file == null || !await file.exists()) {
        return;
      }
      await file.delete();
    } catch (_) {
      return;
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

  bool _shouldSealLocalState(String key) {
    return key == _settingsKey || key == _assistantThreadsKey;
  }

  bool _isSealedLocalState(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return false;
    }
    try {
      final decoded = jsonDecode(trimmed);
      return decoded is Map<String, dynamic> &&
          decoded['storageFormat'] == _sealedStateFormat;
    } catch (_) {
      return false;
    }
  }

  Future<String?> _preparePersistedValue(String key, String value) async {
    if (!_shouldSealLocalState(key)) {
      return value;
    }
    return _sealLocalState(key, value);
  }

  Future<String?> _restorePersistedValue(String key, String value) async {
    if (!_shouldSealLocalState(key)) {
      return value;
    }
    return _restoreLocalState(key, value);
  }

  Future<String> _sealLocalState(String key, String plaintext) async {
    final keyBytes = await _loadOrCreateLocalStateKey();
    final secretBox = await _localStateCipher.encrypt(
      utf8.encode(plaintext),
      secretKey: SecretKey(keyBytes),
      nonce: _randomBytes(12),
      aad: utf8.encode(key),
    );
    return jsonEncode(<String, dynamic>{
      'storageFormat': _sealedStateFormat,
      'nonce': _base64UrlEncode(secretBox.nonce),
      'cipherText': _base64UrlEncode(secretBox.cipherText),
      'mac': _base64UrlEncode(secretBox.mac.bytes),
    });
  }

  Future<String?> _restoreLocalState(String key, String persisted) async {
    final trimmed = persisted.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    Map<String, dynamic>? envelope;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic> &&
          decoded['storageFormat'] == _sealedStateFormat) {
        envelope = decoded;
      }
    } catch (_) {
      return trimmed;
    }
    if (envelope == null) {
      return trimmed;
    }
    final keyBytes = await _loadLocalStateKey(createIfMissing: false);
    if (keyBytes == null) {
      return null;
    }
    try {
      final secretBox = SecretBox(
        _base64UrlDecode(envelope['cipherText'] as String? ?? ''),
        nonce: _base64UrlDecode(envelope['nonce'] as String? ?? ''),
        mac: Mac(_base64UrlDecode(envelope['mac'] as String? ?? '')),
      );
      final clearText = await _localStateCipher.decrypt(
        secretBox,
        secretKey: SecretKey(keyBytes),
        aad: utf8.encode(key),
      );
      return utf8.decode(clearText);
    } catch (_) {
      return null;
    }
  }

  Future<List<int>> _loadOrCreateLocalStateKey() async {
    final existing = await _loadLocalStateKey(createIfMissing: false);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final generated = _randomBytes(32);
    await _writeSecure(_localStateKeyKey, _base64UrlEncode(generated));
    final persisted = await _loadLocalStateKey(createIfMissing: false);
    if (persisted != null && persisted.isNotEmpty) {
      return persisted;
    }
    throw StateError('Local state encryption key unavailable');
  }

  Future<List<int>?> _loadLocalStateKey({required bool createIfMissing}) async {
    final encoded = (await _readSecure(_localStateKeyKey))?.trim() ?? '';
    if (encoded.isNotEmpty) {
      return _base64UrlDecode(encoded);
    }
    if (!createIfMissing) {
      return null;
    }
    return _loadOrCreateLocalStateKey();
  }

  List<int> _randomBytes(int length) {
    return List<int>.generate(length, (_) => _random.nextInt(256));
  }

  String _base64UrlEncode(List<int> bytes) {
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  List<int> _base64UrlDecode(String value) {
    final normalized = value.replaceAll('-', '+').replaceAll('_', '/');
    final padded = normalized + '=' * ((4 - normalized.length % 4) % 4);
    return base64.decode(padded);
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
        final value = await _readSecureValue(_secureStorage!, key);
        if (value != null && value.trim().isNotEmpty) {
          await _deleteGenericSecureFallback(key);
          return value;
        }
      } catch (_) {
        // Keep the primary secure store available for future retries and use
        // the persistent fallback only for this operation.
      }
    }
    if (await _promoteToFileSecureStorageForTests()) {
      try {
        final value = await _readSecureValue(_secureStorage!, key);
        if (value != null && value.trim().isNotEmpty) {
          return value;
        }
      } catch (_) {
        // Fall through to the standard fallback handling below.
      }
    }
    if (_requiresPrimarySecureStorage(key)) {
      final migratedValue = await _migrateLegacyPrimarySecureFallback(key);
      if (migratedValue != null && migratedValue.trim().isNotEmpty) {
        return migratedValue;
      }
      return _memorySecure[key];
    }
    final persistedFallback = await _loadGenericSecureFallback(key);
    if (persistedFallback != null && persistedFallback.trim().isNotEmpty) {
      return persistedFallback;
    }
    return _memorySecure[key];
  }

  Future<void> _enqueueLocalStateWrite(Future<void> Function() action) {
    final next = _localStateWriteQueue.catchError((_) {}).then((_) => action());
    _localStateWriteQueue = next.catchError((_) {});
    return next;
  }

  Future<void> _writeSecure(String key, String value) async {
    if (_secureStorage != null) {
      try {
        await _writeSecureValue(_secureStorage!, key, value);
        await _deleteGenericSecureFallback(key);
        if (_requiresPrimarySecureStorage(key)) {
          await _deleteLegacyPrimarySecureFallback(key);
        }
        _memorySecure[key] = value;
        return;
      } catch (_) {
        if (await _promoteToFileSecureStorageForTests()) {
          try {
            await _writeSecureValue(_secureStorage!, key, value);
            await _deleteGenericSecureFallback(key);
            if (_requiresPrimarySecureStorage(key)) {
              await _deleteLegacyPrimarySecureFallback(key);
            }
            _memorySecure[key] = value;
            return;
          } catch (_) {
            // Fall through to the normal handling below.
          }
        }
        // Keep the primary secure store available for future retries and fall
        // back to a durable local file instead of session-only memory.
      }
    }
    if (_requiresPrimarySecureStorage(key)) {
      throw StateError('Primary secure storage unavailable for $key');
    }
    _memorySecure[key] = value;
    await _saveGenericSecureFallback(key, value);
  }

  Future<void> _deleteSecure(String key) async {
    if (_secureStorage != null) {
      try {
        await _deleteSecureValue(_secureStorage!, key);
      } catch (_) {
        // Best effort. Still clear fallback copies below.
      }
    }
    _memorySecure.remove(key);
    await _deleteGenericSecureFallback(key);
    if (_requiresPrimarySecureStorage(key)) {
      await _deleteLegacyPrimarySecureFallback(key);
    }
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

  Future<File?> _genericSecureFallbackFile(String key) async {
    final fileName = _secureFallbackFileNames[key];
    if (fileName == null) {
      return null;
    }
    final directory = await _resolveFallbackDirectory();
    if (directory == null) {
      return null;
    }
    return File('${directory.path}/$fileName');
  }

  Future<String?> _loadGenericSecureFallback(String key) async {
    try {
      final file = await _genericSecureFallbackFile(key);
      if (file == null || !await file.exists()) {
        return null;
      }
      final value = (await file.readAsString()).trim();
      return value.isEmpty ? null : value;
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveGenericSecureFallback(String key, String value) async {
    try {
      final file = await _genericSecureFallbackFile(key);
      if (file == null) {
        return;
      }
      await file.writeAsString(value, flush: true);
    } catch (_) {
      return;
    }
  }

  Future<void> _deleteGenericSecureFallback(String key) async {
    try {
      final file = await _genericSecureFallbackFile(key);
      if (file == null || !await file.exists()) {
        return;
      }
      await file.delete();
    } catch (_) {
      return;
    }
  }

  bool _requiresPrimarySecureStorage(String key) {
    return key == _localStateKeyKey;
  }

  Future<File?> _legacyPrimarySecureFallbackFile(String key) async {
    if (key != _localStateKeyKey) {
      return null;
    }
    final directory = await _resolveFallbackDirectory();
    if (directory == null) {
      return null;
    }
    return File('${directory.path}/local-state-key.txt');
  }

  Future<String?> _migrateLegacyPrimarySecureFallback(String key) async {
    try {
      final file = await _legacyPrimarySecureFallbackFile(key);
      if (file == null || !await file.exists()) {
        return null;
      }
      final value = (await file.readAsString()).trim();
      if (value.isEmpty || _secureStorage == null) {
        return null;
      }
      await _writeSecureValue(_secureStorage!, key, value);
      _memorySecure[key] = value;
      await file.delete();
      return value;
    } catch (_) {
      return null;
    }
  }

  Future<void> _deleteLegacyPrimarySecureFallback(String key) async {
    try {
      final file = await _legacyPrimarySecureFallbackFile(key);
      if (file == null || !await file.exists()) {
        return;
      }
      await file.delete();
    } catch (_) {
      return;
    }
  }

  Future<bool> _promoteToFileSecureStorageForTests() async {
    if (_secureStorageOverride != null ||
        (_databasePathResolver == null &&
            _fallbackDirectoryPathResolver == null)) {
      return false;
    }
    _secureStorage = FileSecureStorageClient(() => _resolveFallbackDirectory());
    return true;
  }

  Future<String?> _readSecureValue(SecureStorageClient client, String key) {
    final future = client.read(key: key);
    if (client is FlutterSecureStorageClient) {
      return future.timeout(_secureStorageTimeout);
    }
    return future;
  }

  Future<void> _writeSecureValue(
    SecureStorageClient client,
    String key,
    String value,
  ) {
    final future = client.write(key: key, value: value);
    if (client is FlutterSecureStorageClient) {
      return future.timeout(_secureStorageTimeout);
    }
    return future;
  }

  Future<void> _deleteSecureValue(SecureStorageClient client, String key) {
    final future = client.delete(key: key);
    if (client is FlutterSecureStorageClient) {
      return future.timeout(_secureStorageTimeout);
    }
    return future;
  }

  bool _useDebugSecureStorageFallback() {
    var enabled = false;
    assert(() {
      enabled = true;
      return true;
    }());
    return enabled;
  }

  SecureStorageClient _buildDebugSecureStorageClient() {
    if (_databasePathResolver != null ||
        _fallbackDirectoryPathResolver != null) {
      return FileSecureStorageClient(() => _resolveFallbackDirectory());
    }
    return MemorySecureStorageClient();
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

class _AssistantStateBackupReadResult {
  const _AssistantStateBackupReadResult({
    required this.snapshot,
    required this.sealed,
  });

  final _AssistantStateSnapshot snapshot;
  final bool sealed;
}

abstract class SecureStorageClient {
  Future<String?> read({required String key});

  Future<void> write({required String key, required String value});

  Future<void> delete({required String key});
}

typedef SecureConfigDatabaseOpener =
    FutureOr<sqlite.Database?> Function(String resolvedPath);

class FlutterSecureStorageClient implements SecureStorageClient {
  const FlutterSecureStorageClient(this._storage);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read({required String key}) {
    return _storage.read(key: key);
  }

  @override
  Future<void> write({required String key, required String value}) {
    return _storage.write(key: key, value: value);
  }

  @override
  Future<void> delete({required String key}) {
    return _storage.delete(key: key);
  }
}

class FileSecureStorageClient implements SecureStorageClient {
  FileSecureStorageClient(this._directoryResolver);

  final Future<Directory?> Function() _directoryResolver;

  @override
  Future<void> delete({required String key}) async {
    final file = await _fileForKey(key);
    if (file == null || !await file.exists()) {
      return;
    }
    await file.delete();
  }

  @override
  Future<String?> read({required String key}) async {
    final file = await _fileForKey(key);
    if (file == null || !await file.exists()) {
      return null;
    }
    final value = (await file.readAsString()).trim();
    return value.isEmpty ? null : value;
  }

  @override
  Future<void> write({required String key, required String value}) async {
    final file = await _fileForKey(key);
    if (file == null) {
      throw StateError('Secure storage directory unavailable for $key');
    }
    await file.writeAsString(value, flush: true);
  }

  Future<File?> _fileForKey(String key) async {
    final directory = await _directoryResolver();
    if (directory == null) {
      return null;
    }
    final secureDirectory = Directory('${directory.path}/secure-storage');
    if (!await secureDirectory.exists()) {
      await secureDirectory.create(recursive: true);
    }
    final safeKey = base64Url.encode(utf8.encode(key)).replaceAll('=', '');
    return File('${secureDirectory.path}/$safeKey.txt');
  }
}

class MemorySecureStorageClient implements SecureStorageClient {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<void> delete({required String key}) async {
    _values.remove(key);
  }

  @override
  Future<String?> read({required String key}) async {
    return _values[key];
  }

  @override
  Future<void> write({required String key, required String value}) async {
    _values[key] = value;
  }
}
