import 'runtime_models.dart';

abstract class SecureStorageClient {
  Future<String?> read({required String key});

  Future<void> write({required String key, required String value});

  Future<void> delete({required String key});
}

class SecretStore {
  SecretStore({
    Future<String?> Function()? fallbackDirectoryPathResolver,
    Future<String?> Function()? databasePathResolver,
    Future<String?> Function()? defaultSupportDirectoryPathResolver,
    SecureStorageClient? secureStorage,
    bool enableSecureStorage = true,
  });

  static const String legacyLocalStateKey = 'xworkmate.local_state.key';

  Future<void> initialize() async {}

  Future<String?> loadGatewayToken({int? profileIndex}) {
    throw StateError(
      'Legacy secret persistence removed. New secret-path store is pending implementation.',
    );
  }

  Future<void> saveGatewayToken(String value, {int? profileIndex}) {
    throw StateError(
      'Legacy secret persistence removed. New secret-path store is pending implementation.',
    );
  }

  Future<void> clearGatewayToken({int? profileIndex}) {
    throw StateError(
      'Legacy secret persistence removed. New secret-path store is pending implementation.',
    );
  }

  Future<String?> loadGatewayPassword({int? profileIndex}) {
    throw StateError(
      'Legacy secret persistence removed. New secret-path store is pending implementation.',
    );
  }

  Future<void> saveGatewayPassword(String value, {int? profileIndex}) {
    throw StateError(
      'Legacy secret persistence removed. New secret-path store is pending implementation.',
    );
  }

  Future<void> clearGatewayPassword({int? profileIndex}) {
    throw StateError(
      'Legacy secret persistence removed. New secret-path store is pending implementation.',
    );
  }

  Future<String?> loadOllamaCloudApiKey() {
    throw StateError(
      'Legacy secret persistence removed. New secret-path store is pending implementation.',
    );
  }

  Future<void> saveOllamaCloudApiKey(String value) {
    throw StateError(
      'Legacy secret persistence removed. New secret-path store is pending implementation.',
    );
  }

  Future<String?> loadVaultToken() {
    throw StateError(
      'Legacy secret persistence removed. New secret-path store is pending implementation.',
    );
  }

  Future<void> saveVaultToken(String value) {
    throw StateError(
      'Legacy secret persistence removed. New secret-path store is pending implementation.',
    );
  }

  Future<String?> loadAiGatewayApiKey() {
    throw StateError(
      'Legacy secret persistence removed. New secret-path store is pending implementation.',
    );
  }

  Future<void> saveAiGatewayApiKey(String value) {
    throw StateError(
      'Legacy secret persistence removed. New secret-path store is pending implementation.',
    );
  }

  Future<void> clearAiGatewayApiKey() {
    throw StateError(
      'Legacy secret persistence removed. New secret-path store is pending implementation.',
    );
  }

  Future<Map<String, String>> loadSecureRefs() {
    throw StateError(
      'Legacy secret persistence removed. New secret-path store is pending implementation.',
    );
  }

  static String gatewayTokenRefKey(int profileIndex) =>
      _gatewayTokenRefKey(profileIndex);

  static String gatewayPasswordRefKey(int profileIndex) =>
      _gatewayPasswordRefKey(profileIndex);

  Future<LocalDeviceIdentity?> loadDeviceIdentity() {
    throw StateError(
      'Legacy secret persistence removed. New secret-path store is pending implementation.',
    );
  }

  Future<void> saveDeviceIdentity(LocalDeviceIdentity identity) {
    throw StateError(
      'Legacy secret persistence removed. New secret-path store is pending implementation.',
    );
  }

  Future<String?> loadDeviceToken({
    required String deviceId,
    required String role,
  }) {
    throw StateError(
      'Legacy secret persistence removed. New secret-path store is pending implementation.',
    );
  }

  Future<void> saveDeviceToken({
    required String deviceId,
    required String role,
    required String token,
  }) {
    throw StateError(
      'Legacy secret persistence removed. New secret-path store is pending implementation.',
    );
  }

  Future<void> clearDeviceToken({
    required String deviceId,
    required String role,
  }) {
    throw StateError(
      'Legacy secret persistence removed. New secret-path store is pending implementation.',
    );
  }

  Future<List<int>?> loadLegacyLocalStateKeyBytes() {
    throw StateError(
      'Legacy secret persistence removed. New secret-path store is pending implementation.',
    );
  }

  Future<void> dispose() async {}

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
}
