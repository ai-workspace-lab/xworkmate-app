import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import 'runtime_models.dart';

abstract class SecureStorageClient {
  Future<String?> read({required String key});

  Future<void> write({required String key, required String value});

  Future<void> delete({required String key});
}

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

class SecretStore {
  SecretStore({
    Future<String?> Function()? fallbackDirectoryPathResolver,
    Future<String?> Function()? databasePathResolver,
    SecureStorageClient? secureStorage,
    bool enableSecureStorage = true,
  }) : _fallbackDirectoryPathResolver = fallbackDirectoryPathResolver,
       _databasePathResolver = databasePathResolver,
       _secureStorageOverride = secureStorage,
       _enableSecureStorage = enableSecureStorage;

  static const Duration _secureStorageTimeout = Duration(seconds: 5);
  static const String legacyLocalStateKey = 'xworkmate.local_state.key';
  static const String _gatewayTokenKey = 'xworkmate.gateway.token';
  static const String _gatewayPasswordKey = 'xworkmate.gateway.password';
  static const String _gatewayDeviceIdKey = 'xworkmate.gateway.device.id';
  static const String _gatewayDevicePublicKeyKey =
      'xworkmate.gateway.device.public_key';
  static const String _gatewayDevicePrivateKeyKey =
      'xworkmate.gateway.device.private_key';
  static const String _ollamaCloudApiKeyKey = 'xworkmate.ollama.cloud.api_key';
  static const String _vaultTokenKey = 'xworkmate.vault.token';
  static const String _aiGatewayApiKeyKey = 'xworkmate.ai_gateway.api_key';

  static const Map<String, String> _legacyFallbackFileNames = <String, String>{
    _gatewayTokenKey: 'gateway-token.txt',
    _gatewayPasswordKey: 'gateway-password.txt',
    _ollamaCloudApiKeyKey: 'ollama-cloud-api-key.txt',
    _vaultTokenKey: 'vault-token.txt',
    _aiGatewayApiKeyKey: 'ai-gateway-api-key.txt',
  };

  final Map<String, String> _memorySecure = <String, String>{};
  final Future<String?> Function()? _fallbackDirectoryPathResolver;
  final Future<String?> Function()? _databasePathResolver;
  final SecureStorageClient? _secureStorageOverride;
  final bool _enableSecureStorage;
  SecureStorageClient? _secureStorage;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) {
      return;
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
    _initialized = true;
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
    final secureRefs = <String, String>{};
    if (gatewayToken case final value?) {
      secureRefs['gateway_token'] = value;
    }
    if (gatewayPassword case final value?) {
      secureRefs['gateway_password'] = value;
    }
    if (deviceToken case final value?) {
      secureRefs['gateway_device_token_operator'] = value;
    }
    if (ollamaKey case final value?) {
      secureRefs['ollama_cloud_api_key'] = value;
    }
    if (vaultToken case final value?) {
      secureRefs['vault_token'] = value;
    }
    if (aiGatewayApiKey case final value?) {
      secureRefs['ai_gateway_api_key'] = value;
    }
    return secureRefs;
  }

  Future<LocalDeviceIdentity?> loadDeviceIdentity() async {
    await initialize();
    final deviceId = await _readSecure(_gatewayDeviceIdKey);
    final publicKey = await _readSecure(_gatewayDevicePublicKeyKey);
    final privateKey = await _readSecure(_gatewayDevicePrivateKeyKey);
    if (deviceId == null || publicKey == null || privateKey == null) {
      return null;
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
  }

  Future<String?> loadDeviceToken({
    required String deviceId,
    required String role,
  }) async {
    await initialize();
    return _readSecure(_deviceTokenKey(deviceId, role));
  }

  Future<void> saveDeviceToken({
    required String deviceId,
    required String role,
    required String token,
  }) async {
    await initialize();
    await _writeSecure(_deviceTokenKey(deviceId, role), token);
  }

  Future<void> clearDeviceToken({
    required String deviceId,
    required String role,
  }) async {
    await initialize();
    await _deleteSecure(_deviceTokenKey(deviceId, role));
  }

  Future<List<int>?> loadLegacyLocalStateKeyBytes() async {
    await initialize();
    final current = (await _readSecureRaw(legacyLocalStateKey))?.trim() ?? '';
    if (current.isNotEmpty) {
      return _base64UrlDecode(current);
    }
    final file = await _legacyLocalStateKeyFile();
    if (file == null || !await file.exists()) {
      return null;
    }
    final value = (await file.readAsString()).trim();
    if (value.isEmpty) {
      return null;
    }
    if (_secureStorage != null) {
      try {
        await _writeSecureValue(_secureStorage!, legacyLocalStateKey, value);
        await file.delete();
      } catch (_) {
        // Keep the fallback file available for future recovery attempts.
      }
    }
    return _base64UrlDecode(value);
  }

  Future<void> dispose() async {
    _secureStorage = null;
    _initialized = false;
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

  Future<String?> _readSecure(String key) async {
    await initialize();
    final direct = await _readSecureRaw(key);
    if (direct != null && direct.trim().isNotEmpty) {
      return direct.trim();
    }
    final migrated = await _migrateLegacyFallbackFile(key);
    if (migrated != null && migrated.trim().isNotEmpty) {
      return migrated.trim();
    }
    return _memorySecure[key];
  }

  Future<String?> _readSecureRaw(String key) async {
    if (_secureStorage != null) {
      try {
        final value = await _readSecureValue(_secureStorage!, key);
        if (value != null && value.trim().isNotEmpty) {
          _memorySecure[key] = value.trim();
          return value.trim();
        }
      } catch (_) {
        if (await _promoteToFileSecureStorageForTests()) {
          try {
            final value = await _readSecureValue(_secureStorage!, key);
            if (value != null && value.trim().isNotEmpty) {
              _memorySecure[key] = value.trim();
              return value.trim();
            }
          } catch (_) {
            // Fall through to in-memory cache.
          }
        }
      }
    }
    return _memorySecure[key];
  }

  Future<void> _writeSecure(String key, String value) async {
    await initialize();
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return;
    }
    if (_secureStorage == null &&
        !await _promoteToFileSecureStorageForTests()) {
      _memorySecure[key] = trimmed;
      return;
    }
    if (_secureStorage != null) {
      await _writeSecureValue(_secureStorage!, key, trimmed);
      _memorySecure[key] = trimmed;
      final file = await _legacyFallbackFile(key);
      if (file != null && await file.exists()) {
        await file.delete();
      }
    }
  }

  Future<void> _deleteSecure(String key) async {
    await initialize();
    if (_secureStorage != null) {
      try {
        await _deleteSecureValue(_secureStorage!, key);
      } catch (_) {
        // Best effort.
      }
    }
    _memorySecure.remove(key);
    final file = await _legacyFallbackFile(key);
    if (file != null && await file.exists()) {
      await file.delete();
    }
  }

  Future<String?> _migrateLegacyFallbackFile(String key) async {
    final file = await _legacyFallbackFile(key);
    if (file == null || !await file.exists()) {
      return null;
    }
    final value = (await file.readAsString()).trim();
    if (value.isEmpty) {
      return null;
    }
    if (_secureStorage != null) {
      try {
        await _writeSecureValue(_secureStorage!, key, value);
        await file.delete();
      } catch (_) {
        // Leave the fallback file in place if migration fails.
      }
    }
    _memorySecure[key] = value;
    return value;
  }

  Future<File?> _legacyFallbackFile(String key) async {
    final fileName = _legacyFallbackFileNames[key];
    if (fileName == null) {
      return null;
    }
    final directory = await _resolveFallbackDirectory();
    if (directory == null) {
      return null;
    }
    return File('${directory.path}/$fileName');
  }

  Future<File?> _legacyLocalStateKeyFile() async {
    final directory = await _resolveFallbackDirectory();
    if (directory == null) {
      return null;
    }
    return File('${directory.path}/local-state-key.txt');
  }

  Future<Directory?> _resolveFallbackDirectory() async {
    final explicit = await _fallbackDirectoryPathResolver?.call();
    final explicitTrimmed = explicit?.trim() ?? '';
    if (explicitTrimmed.isNotEmpty) {
      return _ensureDirectory(explicitTrimmed);
    }
    final databasePath = await _databasePathResolver?.call();
    final databaseTrimmed = databasePath?.trim() ?? '';
    if (databaseTrimmed.isNotEmpty) {
      return _ensureDirectory(File(databaseTrimmed).parent.path);
    }
    try {
      final supportDirectory = await getApplicationSupportDirectory();
      return _ensureDirectory(
        '${supportDirectory.path}/xworkmate/gateway-auth',
      );
    } catch (_) {
      return null;
    }
  }

  Future<Directory> _ensureDirectory(String path) async {
    final directory = Directory(path);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
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

  static String _deviceTokenKey(String deviceId, String role) {
    final safeRole = role.trim().isEmpty ? 'operator' : role.trim();
    return 'xworkmate.gateway.device_token.$deviceId.$safeRole';
  }

  static List<int> _base64UrlDecode(String value) {
    final normalized = value.replaceAll('-', '+').replaceAll('_', '/');
    final padded = normalized + '=' * ((4 - normalized.length % 4) % 4);
    return base64.decode(padded);
  }
}
