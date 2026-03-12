import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'runtime_models.dart';

class SecureConfigStore {
  SecureConfigStore({Future<String?> Function()? fallbackDirectoryPathResolver})
    : _fallbackDirectoryPathResolver = fallbackDirectoryPathResolver;

  static const _settingsKey = 'xworkmate.settings.snapshot';
  static const _auditKey = 'xworkmate.secrets.audit';

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

  SharedPreferences? _prefs;
  FlutterSecureStorage? _secureStorage;
  final Map<String, Object?> _memoryPrefs = <String, Object?>{};
  final Map<String, String> _memorySecure = <String, String>{};
  final Future<String?> Function()? _fallbackDirectoryPathResolver;
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
    try {
      _secureStorage = const FlutterSecureStorage();
    } catch (_) {
      _secureStorage = null;
    }
    _initialized = true;
  }

  Future<SettingsSnapshot> loadSettingsSnapshot() async {
    await initialize();
    return SettingsSnapshot.fromJsonString(await _readPrefString(_settingsKey));
  }

  Future<void> saveSettingsSnapshot(SettingsSnapshot snapshot) async {
    await initialize();
    await _writePrefString(_settingsKey, snapshot.toJsonString());
  }

  Future<List<SecretAuditEntry>> loadAuditTrail() async {
    await initialize();
    final raw = await _readPrefString(_auditKey);
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
    await _writePrefString(
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
    };
  }

  Future<String?> _readPrefString(String key) async {
    if (_prefs != null) {
      return _prefs!.getString(key);
    }
    final value = _memoryPrefs[key];
    return value is String ? value : null;
  }

  Future<void> _writePrefString(String key, String value) async {
    if (_prefs != null) {
      await _prefs!.setString(key, value);
      return;
    }
    _memoryPrefs[key] = value;
  }

  Future<String?> _readSecure(String key) async {
    if (_secureStorage != null) {
      try {
        return await _secureStorage!.read(key: key);
      } catch (_) {
        // Fall back to in-memory storage for tests and unsupported runners.
      }
    }
    return _memorySecure[key];
  }

  Future<void> _writeSecure(String key, String value) async {
    if (_secureStorage != null) {
      try {
        await _secureStorage!.write(key: key, value: value);
        return;
      } catch (_) {
        // Fall back to in-memory storage for tests and unsupported runners.
      }
    }
    _memorySecure[key] = value;
  }

  Future<void> _deleteSecure(String key) async {
    if (_secureStorage != null) {
      try {
        await _secureStorage!.delete(key: key);
      } catch (_) {
        // Keep the in-memory fallback in sync.
      }
    }
    _memorySecure.remove(key);
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
