export 'secret_store.dart';
export 'settings_store.dart';

import 'file_store_support.dart';
import 'runtime_models.dart';
import 'secret_store.dart';
import 'settings_store.dart';

class SecureConfigStore {
  SecureConfigStore({
    Future<String?> Function()? fallbackDirectoryPathResolver,
    Future<String?> Function()? databasePathResolver,
    Future<String?> Function()? defaultSupportDirectoryPathResolver,
    SecureConfigDatabaseOpener? databaseOpener,
    SecureStorageClient? secureStorage,
    bool enableSecureStorage = true,
  }) {
    final layoutResolver = StoreLayoutResolver(
      localRootPathResolver: databasePathResolver,
      secretRootPathResolver: fallbackDirectoryPathResolver,
      supportRootPathResolver: defaultSupportDirectoryPathResolver,
    );
    _secretStore = SecretStore(
      fallbackDirectoryPathResolver: fallbackDirectoryPathResolver,
      databasePathResolver: databasePathResolver,
      defaultSupportDirectoryPathResolver: defaultSupportDirectoryPathResolver,
      secureStorage: secureStorage,
      enableSecureStorage: enableSecureStorage,
      layoutResolver: layoutResolver,
    );
    _settingsStore = SettingsStore(
      fallbackDirectoryPathResolver: fallbackDirectoryPathResolver,
      databasePathResolver: databasePathResolver,
      defaultSupportDirectoryPathResolver: defaultSupportDirectoryPathResolver,
      databaseOpener: databaseOpener,
      layoutResolver: layoutResolver,
    );
  }

  late final SecretStore _secretStore;
  late final SettingsStore _settingsStore;

  Future<void> initialize() async {
    await _secretStore.initialize();
    await _settingsStore.initialize();
  }

  Future<SettingsSnapshot> loadSettingsSnapshot() {
    return _settingsStore.loadSettingsSnapshot();
  }

  Future<void> saveSettingsSnapshot(SettingsSnapshot snapshot) {
    return _settingsStore.saveSettingsSnapshot(snapshot);
  }

  Future<List<AssistantThreadRecord>> loadAssistantThreadRecords() {
    return _settingsStore.loadAssistantThreadRecords();
  }

  Future<void> saveAssistantThreadRecords(List<AssistantThreadRecord> records) {
    return _settingsStore.saveAssistantThreadRecords(records);
  }

  Future<void> clearAssistantLocalState() {
    return _settingsStore.clearAssistantLocalState();
  }

  Future<List<SecretAuditEntry>> loadAuditTrail() {
    return _settingsStore.loadAuditTrail();
  }

  Future<void> appendAudit(SecretAuditEntry entry) {
    return _settingsStore.appendAudit(entry);
  }

  Future<Map<String, String>> loadSecureRefs() {
    return _secretStore.loadSecureRefs();
  }

  Future<String?> loadGatewayToken({int? profileIndex}) =>
      _secretStore.loadGatewayToken(profileIndex: profileIndex);

  Future<void> saveGatewayToken(String value, {int? profileIndex}) =>
      _secretStore.saveGatewayToken(value, profileIndex: profileIndex);

  Future<void> clearGatewayToken({int? profileIndex}) =>
      _secretStore.clearGatewayToken(profileIndex: profileIndex);

  Future<String?> loadGatewayPassword({int? profileIndex}) =>
      _secretStore.loadGatewayPassword(profileIndex: profileIndex);

  Future<void> saveGatewayPassword(String value, {int? profileIndex}) =>
      _secretStore.saveGatewayPassword(value, profileIndex: profileIndex);

  Future<void> clearGatewayPassword({int? profileIndex}) =>
      _secretStore.clearGatewayPassword(profileIndex: profileIndex);

  Future<String?> loadOllamaCloudApiKey() =>
      _secretStore.loadOllamaCloudApiKey();

  Future<void> saveOllamaCloudApiKey(String value) =>
      _secretStore.saveOllamaCloudApiKey(value);

  Future<String?> loadVaultToken() => _secretStore.loadVaultToken();

  Future<void> saveVaultToken(String value) =>
      _secretStore.saveVaultToken(value);

  Future<String?> loadAiGatewayApiKey() => _secretStore.loadAiGatewayApiKey();

  Future<void> saveAiGatewayApiKey(String value) =>
      _secretStore.saveAiGatewayApiKey(value);

  Future<void> clearAiGatewayApiKey() => _secretStore.clearAiGatewayApiKey();

  Future<LocalDeviceIdentity?> loadDeviceIdentity() {
    return _secretStore.loadDeviceIdentity();
  }

  Future<void> saveDeviceIdentity(LocalDeviceIdentity identity) {
    return _secretStore.saveDeviceIdentity(identity);
  }

  Future<String?> loadDeviceToken({
    required String deviceId,
    required String role,
  }) {
    return _secretStore.loadDeviceToken(deviceId: deviceId, role: role);
  }

  Future<void> saveDeviceToken({
    required String deviceId,
    required String role,
    required String token,
  }) {
    return _secretStore.saveDeviceToken(
      deviceId: deviceId,
      role: role,
      token: token,
    );
  }

  Future<void> clearDeviceToken({
    required String deviceId,
    required String role,
  }) {
    return _secretStore.clearDeviceToken(deviceId: deviceId, role: role);
  }

  void dispose() {
    _settingsStore.dispose();
    _secretStore.dispose();
  }

  static String maskValue(String value) {
    return SecretStore.maskValue(value);
  }
}
