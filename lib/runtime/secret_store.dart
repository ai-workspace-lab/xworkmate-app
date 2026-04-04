import 'dart:convert';
import 'dart:io';

import 'file_store_support.dart';
import 'runtime_models.dart';

abstract class SecureStorageClient {
  Future<String?> read({required String key});

  Future<void> write({required String key, required String value});

  Future<void> delete({required String key});
}

class FileSecureStorageClient implements SecureStorageClient {
  FileSecureStorageClient(this._directoryResolver);

  final Future<Directory?> Function() _directoryResolver;

  @override
  Future<void> delete({required String key}) async {
    final file = await _fileForKey(key);
    if (file != null && await file.exists()) {
      await file.delete();
    }
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
      throw StateError('Secret directory unavailable for $key');
    }
    await atomicWriteString(file, '$value\n', ownerOnly: true);
  }

  Future<File?> _fileForKey(String key) async {
    final directory = await _directoryResolver();
    if (directory == null) {
      return null;
    }
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    await ensureOwnerOnlyDirectory(directory);
    return File('${directory.path}/${encodeStableFileKey(key)}.secret');
  }
}

class SecretStore {
  SecretStore({
    Future<String?> Function()? fallbackDirectoryPathResolver,
    Future<String?> Function()? databasePathResolver,
    Future<String?> Function()? defaultSupportDirectoryPathResolver,
    SecureStorageClient? secureStorage,
    bool enableSecureStorage = true,
    StoreLayoutResolver? layoutResolver,
  }) : _layoutResolver =
           layoutResolver ??
           StoreLayoutResolver(
             localRootPathResolver: databasePathResolver,
             secretRootPathResolver: fallbackDirectoryPathResolver,
             supportRootPathResolver: defaultSupportDirectoryPathResolver,
           ),
       _secureStorageOverride = secureStorage;

  static const String legacyLocalStateKey = 'xworkmate.local_state.key';

  static const String _legacyGatewayTokenKey = 'xworkmate.gateway.token';
  static const String _legacyGatewayPasswordKey = 'xworkmate.gateway.password';
  static const String _gatewayDeviceIdKey = 'xworkmate.gateway.device.id';
  static const String _gatewayDevicePublicKeyKey =
      'xworkmate.gateway.device.public_key';
  static const String _gatewayDevicePrivateKeyKey =
      'xworkmate.gateway.device.private_key';
  static const String _gatewayDeviceCreatedAtKey =
      'xworkmate.gateway.device.created_at_ms';
  static const String _ollamaCloudApiKeyKey = 'xworkmate.ollama.cloud.api_key';
  static const String _vaultTokenKey = 'xworkmate.vault.token';
  static const String _aiGatewayApiKeyKey = 'xworkmate.ai_gateway.api_key';
  static const String _accountSessionTokenKey =
      'xworkmate.account.session.token';
  static const String _accountSessionExpiresAtKey =
      'xworkmate.account.session.expires_at';
  static const String _accountSessionUserIdKey =
      'xworkmate.account.session.user_id';
  static const String _accountSessionIdentifierKey =
      'xworkmate.account.session.identifier';
  static const String _accountSessionSummaryKey =
      'xworkmate.account.session.summary';
  static const String _accountProfileKey = 'xworkmate.account.profile';
  static const String _customSecretRefRegistryKey =
      'xworkmate.secret.ref_registry';

  final StoreLayoutResolver _layoutResolver;
  final SecureStorageClient? _secureStorageOverride;
  final Map<String, String> _memorySecure = <String, String>{};
  StoreLayout? _layout;
  SecureStorageClient? _secureStorage;
  bool _initialized = false;
  PersistentWriteFailure? _secretsWriteFailure;

  PersistentWriteFailure? get secretsWriteFailure => _secretsWriteFailure;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;
    if (_secureStorageOverride != null) {
      _secureStorage = _secureStorageOverride;
      return;
    }
    try {
      _layout = await _layoutResolver.resolve();
      _secureStorage = FileSecureStorageClient(
        () async => _layout?.secretDirectory,
      );
    } catch (_) {
      _layout = null;
      _secureStorage = null;
    }
  }

  Future<String?> loadGatewayToken({int? profileIndex}) async {
    if (profileIndex != null) {
      final scopedValue = await _readSecure(
        _gatewayTokenKeyForProfile(profileIndex),
      );
      if ((scopedValue ?? '').trim().isNotEmpty) {
        return scopedValue;
      }
      return _readSecure(_legacyGatewayTokenKey);
    }
    final legacyValue = await _readSecure(_legacyGatewayTokenKey);
    if ((legacyValue ?? '').trim().isNotEmpty) {
      return legacyValue;
    }
    for (final index in _gatewayProfileFallbackOrder) {
      final scopedValue = await _readSecure(_gatewayTokenKeyForProfile(index));
      if ((scopedValue ?? '').trim().isNotEmpty) {
        return scopedValue;
      }
    }
    return null;
  }

  Future<void> saveGatewayToken(String value, {int? profileIndex}) =>
      _writeSecure(
        profileIndex == null
            ? _legacyGatewayTokenKey
            : _gatewayTokenKeyForProfile(profileIndex),
        value,
      );

  Future<void> clearGatewayToken({int? profileIndex}) => _deleteSecure(
    profileIndex == null
        ? _legacyGatewayTokenKey
        : _gatewayTokenKeyForProfile(profileIndex),
  );

  Future<String?> loadGatewayPassword({int? profileIndex}) async {
    if (profileIndex != null) {
      final scopedValue = await _readSecure(
        _gatewayPasswordKeyForProfile(profileIndex),
      );
      if ((scopedValue ?? '').trim().isNotEmpty) {
        return scopedValue;
      }
      return _readSecure(_legacyGatewayPasswordKey);
    }
    final legacyValue = await _readSecure(_legacyGatewayPasswordKey);
    if ((legacyValue ?? '').trim().isNotEmpty) {
      return legacyValue;
    }
    for (final index in _gatewayProfileFallbackOrder) {
      final scopedValue = await _readSecure(
        _gatewayPasswordKeyForProfile(index),
      );
      if ((scopedValue ?? '').trim().isNotEmpty) {
        return scopedValue;
      }
    }
    return null;
  }

  Future<void> saveGatewayPassword(String value, {int? profileIndex}) =>
      _writeSecure(
        profileIndex == null
            ? _legacyGatewayPasswordKey
            : _gatewayPasswordKeyForProfile(profileIndex),
        value,
      );

  Future<void> clearGatewayPassword({int? profileIndex}) => _deleteSecure(
    profileIndex == null
        ? _legacyGatewayPasswordKey
        : _gatewayPasswordKeyForProfile(profileIndex),
  );

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

  Future<String?> loadAccountSessionToken() =>
      _readSecure(_accountSessionTokenKey);

  Future<void> saveAccountSessionToken(String value) =>
      _writeSecure(_accountSessionTokenKey, value);

  Future<void> clearAccountSessionToken() =>
      _deleteSecure(_accountSessionTokenKey);

  Future<int> loadAccountSessionExpiresAtMs() async {
    final raw = await _readSecure(_accountSessionExpiresAtKey);
    return int.tryParse((raw ?? '').trim()) ?? 0;
  }

  Future<void> saveAccountSessionExpiresAtMs(int value) =>
      _writeSecure(_accountSessionExpiresAtKey, value.toString());

  Future<void> clearAccountSessionExpiresAtMs() =>
      _deleteSecure(_accountSessionExpiresAtKey);

  Future<String?> loadAccountSessionUserId() =>
      _readSecure(_accountSessionUserIdKey);

  Future<void> saveAccountSessionUserId(String value) =>
      _writeSecure(_accountSessionUserIdKey, value);

  Future<void> clearAccountSessionUserId() =>
      _deleteSecure(_accountSessionUserIdKey);

  Future<String?> loadAccountSessionIdentifier() =>
      _readSecure(_accountSessionIdentifierKey);

  Future<void> saveAccountSessionIdentifier(String value) =>
      _writeSecure(_accountSessionIdentifierKey, value);

  Future<void> clearAccountSessionIdentifier() =>
      _deleteSecure(_accountSessionIdentifierKey);

  Future<AccountSessionSummary?> loadAccountSessionSummary() async {
    final raw = await _readSecure(_accountSessionSummaryKey);
    if ((raw ?? '').trim().isEmpty) {
      return null;
    }
    try {
      return AccountSessionSummary.fromJson(
        (jsonDecode(raw!) as Map).cast<String, dynamic>(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> saveAccountSessionSummary(AccountSessionSummary value) =>
      _writeSecure(_accountSessionSummaryKey, jsonEncode(value.toJson()));

  Future<void> clearAccountSessionSummary() =>
      _deleteSecure(_accountSessionSummaryKey);

  Future<AccountRemoteProfile?> loadAccountProfile() async {
    final raw = await _readSecure(_accountProfileKey);
    if ((raw ?? '').trim().isEmpty) {
      return null;
    }
    try {
      return AccountRemoteProfile.fromJson(
        (jsonDecode(raw!) as Map).cast<String, dynamic>(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> saveAccountProfile(AccountRemoteProfile value) =>
      _writeSecure(_accountProfileKey, jsonEncode(value.toJson()));

  Future<void> clearAccountProfile() => _deleteSecure(_accountProfileKey);

  Future<String?> loadAccountManagedSecret({required String target}) =>
      _readSecure(_accountManagedSecretKey(target));

  Future<void> saveAccountManagedSecret({
    required String target,
    required String value,
  }) => _writeSecure(_accountManagedSecretKey(target), value);

  Future<void> clearAccountManagedSecret({required String target}) =>
      _deleteSecure(_accountManagedSecretKey(target));

  Future<void> clearAccountManagedSecrets() async {
    for (final target in kAccountManagedSecretTargets) {
      await clearAccountManagedSecret(target: target);
    }
  }

  Future<String?> loadSecretValueByRef(String refName) async {
    final normalizedRef = refName.trim();
    if (normalizedRef.isEmpty) {
      return null;
    }
    return _readSecure(_secureStorageKeyForRef(normalizedRef));
  }

  Future<void> saveSecretValueByRef(String refName, String value) async {
    final normalizedRef = refName.trim();
    final trimmedValue = value.trim();
    if (normalizedRef.isEmpty || trimmedValue.isEmpty) {
      return;
    }
    final key = _secureStorageKeyForRef(normalizedRef);
    await _writeSecure(key, trimmedValue);
    if (_isCustomSecretRef(normalizedRef)) {
      await _saveCustomSecretRefRegistryInternal(<String>{
        ...await _loadCustomSecretRefRegistryInternal(),
        normalizedRef,
      });
    }
  }

  Future<void> clearSecretValueByRef(String refName) async {
    final normalizedRef = refName.trim();
    if (normalizedRef.isEmpty) {
      return;
    }
    await _deleteSecure(_secureStorageKeyForRef(normalizedRef));
    if (_isCustomSecretRef(normalizedRef)) {
      final refs = await _loadCustomSecretRefRegistryInternal();
      refs.remove(normalizedRef);
      await _saveCustomSecretRefRegistryInternal(refs);
    }
  }

  Future<Map<String, String>> loadSecureRefs() async {
    await initialize();
    final secureRefs = <String, String>{};
    final legacyGatewayToken = await _readSecure(_legacyGatewayTokenKey);
    final legacyGatewayPassword = await _readSecure(_legacyGatewayPasswordKey);
    if (legacyGatewayToken case final value?) {
      secureRefs['gateway_token'] = value;
    }
    if (legacyGatewayPassword case final value?) {
      secureRefs['gateway_password'] = value;
    }
    for (var index = 0; index < kGatewayProfileListLength; index += 1) {
      final scopedToken = await _readSecure(_gatewayTokenKeyForProfile(index));
      final scopedPassword = await _readSecure(
        _gatewayPasswordKeyForProfile(index),
      );
      if (scopedToken case final value?) {
        secureRefs[_gatewayTokenRefKey(index)] = value;
      }
      if (scopedPassword case final value?) {
        secureRefs[_gatewayPasswordRefKey(index)] = value;
      }
    }
    final deviceIdentity = await loadDeviceIdentity();
    if (deviceIdentity != null) {
      final deviceToken = await loadDeviceToken(
        deviceId: deviceIdentity.deviceId,
        role: 'operator',
      );
      if (deviceToken case final value?) {
        secureRefs['gateway_device_token_operator'] = value;
      }
    }
    final ollamaKey = await loadOllamaCloudApiKey();
    final vaultToken = await loadVaultToken();
    final aiGatewayApiKey = await loadAiGatewayApiKey();
    if (ollamaKey case final value?) {
      secureRefs['ollama_cloud_api_key'] = value;
    }
    if (vaultToken case final value?) {
      secureRefs['vault_token'] = value;
    }
    if (aiGatewayApiKey case final value?) {
      secureRefs['ai_gateway_api_key'] = value;
    }
    for (final target in kAccountManagedSecretTargets) {
      final managedValue = await loadAccountManagedSecret(target: target);
      if (managedValue case final value?) {
        secureRefs[target] = value;
      }
    }
    for (final refName in await _loadCustomSecretRefRegistryInternal()) {
      final customValue = await loadSecretValueByRef(refName);
      if (customValue case final value?) {
        secureRefs[refName] = value;
      }
    }
    return secureRefs;
  }

  static String gatewayTokenRefKey(int profileIndex) =>
      _gatewayTokenRefKey(profileIndex);

  static String gatewayPasswordRefKey(int profileIndex) =>
      _gatewayPasswordRefKey(profileIndex);

  Future<LocalDeviceIdentity?> loadDeviceIdentity() async {
    await initialize();
    final deviceId = await _readSecure(_gatewayDeviceIdKey);
    final publicKey = await _readSecure(_gatewayDevicePublicKeyKey);
    final privateKey = await _readSecure(_gatewayDevicePrivateKeyKey);
    if (deviceId == null || publicKey == null || privateKey == null) {
      return null;
    }
    final createdAtMs =
        int.tryParse(await _readSecure(_gatewayDeviceCreatedAtKey) ?? '') ?? 0;
    return LocalDeviceIdentity(
      deviceId: deviceId,
      publicKeyBase64Url: publicKey,
      privateKeyBase64Url: privateKey,
      createdAtMs: createdAtMs,
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
    await _writeSecure(
      _gatewayDeviceCreatedAtKey,
      identity.createdAtMs.toString(),
    );
  }

  Future<String?> loadDeviceToken({
    required String deviceId,
    required String role,
  }) => _readSecure(_deviceTokenKey(deviceId, role));

  Future<void> saveDeviceToken({
    required String deviceId,
    required String role,
    required String token,
  }) => _writeSecure(_deviceTokenKey(deviceId, role), token);

  Future<void> clearDeviceToken({
    required String deviceId,
    required String role,
  }) => _deleteSecure(_deviceTokenKey(deviceId, role));

  Future<List<int>?> loadLegacyLocalStateKeyBytes() async {
    final encoded = await _readSecure(legacyLocalStateKey);
    final trimmed = encoded?.trim() ?? '';
    if (trimmed.isEmpty) {
      return null;
    }
    return _base64UrlDecode(trimmed);
  }

  Future<void> dispose() async {
    _memorySecure.clear();
    _secureStorage = null;
    _layout = null;
    _initialized = false;
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

  static String _gatewayTokenRefKey(int profileIndex) =>
      'gateway_token_$profileIndex';

  static String _gatewayPasswordRefKey(int profileIndex) =>
      'gateway_password_$profileIndex';

  static const List<int> _gatewayProfileFallbackOrder = <int>[
    kGatewayRemoteProfileIndex,
    kGatewayLocalProfileIndex,
    2,
    3,
    4,
  ];

  static String _accountManagedSecretKey(String target) =>
      'xworkmate.account.managed.${target.trim()}';

  static String _customSecretRefKey(String refName) =>
      'xworkmate.secret.ref.${refName.trim()}';

  static bool _looksLikeGatewayProfileRef(String refName, String prefix) {
    final normalized = refName.trim();
    if (!normalized.startsWith(prefix)) {
      return false;
    }
    final suffix = normalized.substring(prefix.length);
    return int.tryParse(suffix) != null;
  }

  static bool _isCustomSecretRef(String refName) {
    final normalized = refName.trim();
    if (normalized.isEmpty ||
        normalized == 'gateway_token' ||
        normalized == 'gateway_password' ||
        normalized == 'vault_token' ||
        normalized == 'ai_gateway_api_key' ||
        normalized == 'ollama_cloud_api_key' ||
        isSupportedAccountManagedSecretTarget(normalized) ||
        _looksLikeGatewayProfileRef(normalized, 'gateway_token_') ||
        _looksLikeGatewayProfileRef(normalized, 'gateway_password_')) {
      return false;
    }
    return true;
  }

  static String _secureStorageKeyForRef(String refName) {
    final normalized = refName.trim();
    if (normalized == 'gateway_token') {
      return _legacyGatewayTokenKey;
    }
    if (normalized == 'gateway_password') {
      return _legacyGatewayPasswordKey;
    }
    if (_looksLikeGatewayProfileRef(normalized, 'gateway_token_')) {
      final index = int.parse(normalized.substring('gateway_token_'.length));
      return _gatewayTokenKeyForProfile(index);
    }
    if (_looksLikeGatewayProfileRef(normalized, 'gateway_password_')) {
      final index = int.parse(normalized.substring('gateway_password_'.length));
      return _gatewayPasswordKeyForProfile(index);
    }
    if (normalized == 'vault_token') {
      return _vaultTokenKey;
    }
    if (normalized == 'ai_gateway_api_key') {
      return _aiGatewayApiKeyKey;
    }
    if (normalized == 'ollama_cloud_api_key') {
      return _ollamaCloudApiKeyKey;
    }
    if (isSupportedAccountManagedSecretTarget(normalized)) {
      return _accountManagedSecretKey(normalized);
    }
    return _customSecretRefKey(normalized);
  }

  Future<Set<String>> _loadCustomSecretRefRegistryInternal() async {
    final raw = await _readSecure(_customSecretRefRegistryKey);
    if ((raw ?? '').trim().isEmpty) {
      return <String>{};
    }
    try {
      final decoded = jsonDecode(raw!);
      if (decoded is! List) {
        return <String>{};
      }
      return decoded
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toSet();
    } catch (_) {
      return <String>{};
    }
  }

  Future<void> _saveCustomSecretRefRegistryInternal(Set<String> refs) async {
    final normalized =
        refs
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList(growable: false)
          ..sort();
    if (normalized.isEmpty) {
      await _deleteSecure(_customSecretRefRegistryKey);
      return;
    }
    await _writeSecure(_customSecretRefRegistryKey, jsonEncode(normalized));
  }

  Future<String?> _readSecure(String key) async {
    await initialize();
    final client = _secureStorage;
    if (client != null) {
      try {
        final value = (await client.read(key: key))?.trim();
        if (value != null && value.isNotEmpty) {
          _memorySecure[key] = value;
          return value;
        }
      } catch (_) {
        // Fall back to memory only when the secret path is unavailable.
      }
    }
    final memoryValue = _memorySecure[key]?.trim() ?? '';
    return memoryValue.isEmpty ? null : memoryValue;
  }

  Future<void> _writeSecure(String key, String value) async {
    await initialize();
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return;
    }
    _memorySecure[key] = trimmed;
    final client = _secureStorage;
    if (client == null) {
      _secretsWriteFailure = _buildWriteFailure(
        'writeSecret',
        StateError('Persistent secret path unavailable; using memory only.'),
      );
      return;
    }
    try {
      await client.write(key: key, value: trimmed);
      _secretsWriteFailure = null;
    } catch (error) {
      _secretsWriteFailure = _buildWriteFailure('writeSecret', error);
    }
  }

  Future<void> _deleteSecure(String key) async {
    await initialize();
    _memorySecure.remove(key);
    final client = _secureStorage;
    if (client == null) {
      _secretsWriteFailure = _buildWriteFailure(
        'deleteSecret',
        StateError(
          'Persistent secret path unavailable; clear applied in memory only.',
        ),
      );
      return;
    }
    try {
      await client.delete(key: key);
      _secretsWriteFailure = null;
    } catch (error) {
      _secretsWriteFailure = _buildWriteFailure('deleteSecret', error);
    }
  }

  static String _deviceTokenKey(String deviceId, String role) {
    final safeRole = role.trim().isEmpty ? 'operator' : role.trim();
    return 'xworkmate.gateway.device_token.$deviceId.$safeRole';
  }

  static String _gatewayTokenKeyForProfile(int profileIndex) =>
      'xworkmate.gateway.profile.$profileIndex.token';

  static String _gatewayPasswordKeyForProfile(int profileIndex) =>
      'xworkmate.gateway.profile.$profileIndex.password';

  static List<int> _base64UrlDecode(String value) {
    final normalized = value.replaceAll('-', '+').replaceAll('_', '/');
    final padded = normalized + '=' * ((4 - normalized.length % 4) % 4);
    return base64.decode(padded);
  }

  PersistentWriteFailure _buildWriteFailure(String operation, Object error) {
    return PersistentWriteFailure(
      scope: PersistentStoreScope.secrets,
      operation: operation,
      message: error.toString(),
      timestampMs: DateTime.now().millisecondsSinceEpoch,
    );
  }
}
