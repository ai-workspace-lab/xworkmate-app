import 'dart:convert';
import 'dart:io';

export 'file_store_support.dart';
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
    _layoutResolver = layoutResolver;
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
  late final StoreLayoutResolver _layoutResolver;

  Future<void> initialize() async {
    await _secretStore.initialize();
    await _settingsStore.initialize();
  }

  Future<SettingsSnapshot> loadSettingsSnapshot() {
    return _settingsStore.loadSettingsSnapshot();
  }

  Future<SettingsSnapshot> reloadSettingsSnapshot() {
    return _settingsStore.reloadSettingsSnapshot();
  }

  Future<SettingsSnapshotReloadResult> reloadSettingsSnapshotResult() {
    return _settingsStore.reloadSettingsSnapshotResult();
  }

  Future<void> saveSettingsSnapshot(SettingsSnapshot snapshot) {
    return _settingsStore.saveSettingsSnapshot(snapshot);
  }

  Future<List<File>> resolvedSettingsFiles() {
    return _settingsStore.resolvedSettingsFiles();
  }

  Future<List<Directory>> resolvedSettingsWatchDirectories() {
    return _settingsStore.resolvedSettingsWatchDirectories();
  }

  Future<List<TaskThread>> loadTaskThreads() {
    return _settingsStore.loadTaskThreads();
  }

  Future<void> saveTaskThreads(List<TaskThread> records) {
    return _settingsStore.saveTaskThreads(records);
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

  Future<Map<String, dynamic>?> loadSupportJson(String relativePath) async {
    final file = await supportFile(relativePath);
    if (file == null || !await file.exists()) {
      return null;
    }
    final raw = await file.readAsString();
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  Future<void> saveSupportJson(
    String relativePath,
    Map<String, dynamic> payload,
  ) async {
    final file = await supportFile(relativePath);
    if (file == null) {
      return;
    }
    await atomicWriteString(file, jsonEncode(payload), ownerOnly: true);
  }

  Future<File?> supportFile(String relativePath) async {
    final normalized = relativePath.trim();
    if (normalized.isEmpty) {
      return null;
    }
    final layout = await _layoutResolver.resolve();
    return File('${layout.rootDirectory.path}/$normalized');
  }

  Future<Map<String, String>> loadSecureRefs() {
    return _secretStore.loadSecureRefs();
  }

  Future<String?> loadSecretValueByRef(String refName) =>
      _secretStore.loadSecretValueByRef(refName);

  Future<void> saveSecretValueByRef(String refName, String value) =>
      _secretStore.saveSecretValueByRef(refName, value);

  Future<void> clearSecretValueByRef(String refName) =>
      _secretStore.clearSecretValueByRef(refName);

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

  Future<String?> loadAccountSessionToken() =>
      _secretStore.loadAccountSessionToken();

  Future<void> saveAccountSessionToken(String value) =>
      _secretStore.saveAccountSessionToken(value);

  Future<void> clearAccountSessionToken() =>
      _secretStore.clearAccountSessionToken();

  Future<int> loadAccountSessionExpiresAtMs() =>
      _secretStore.loadAccountSessionExpiresAtMs();

  Future<void> saveAccountSessionExpiresAtMs(int value) =>
      _secretStore.saveAccountSessionExpiresAtMs(value);

  Future<void> clearAccountSessionExpiresAtMs() =>
      _secretStore.clearAccountSessionExpiresAtMs();

  Future<String?> loadAccountSessionUserId() =>
      _secretStore.loadAccountSessionUserId();

  Future<void> saveAccountSessionUserId(String value) =>
      _secretStore.saveAccountSessionUserId(value);

  Future<void> clearAccountSessionUserId() =>
      _secretStore.clearAccountSessionUserId();

  Future<String?> loadAccountSessionIdentifier() =>
      _secretStore.loadAccountSessionIdentifier();

  Future<void> saveAccountSessionIdentifier(String value) =>
      _secretStore.saveAccountSessionIdentifier(value);

  Future<void> clearAccountSessionIdentifier() =>
      _secretStore.clearAccountSessionIdentifier();

  Future<AccountSessionSummary?> loadAccountSessionSummary() =>
      _secretStore.loadAccountSessionSummary();

  Future<void> saveAccountSessionSummary(AccountSessionSummary value) =>
      _secretStore.saveAccountSessionSummary(value);

  Future<void> clearAccountSessionSummary() =>
      _secretStore.clearAccountSessionSummary();

  Future<AccountSyncState?> loadAccountSyncState() async {
    final payload = await loadSupportJson('account/sync_state.json');
    if (payload == null) {
      return null;
    }
    return AccountSyncState.fromJson(payload);
  }

  Future<void> saveAccountSyncState(AccountSyncState value) =>
      saveSupportJson('account/sync_state.json', value.toJson());

  Future<void> clearAccountSyncState() async {
    final file = await supportFile('account/sync_state.json');
    if (file != null && await file.exists()) {
      await file.delete();
    }
  }

  Future<AccountRemoteProfile?> loadAccountProfile() =>
      _secretStore.loadAccountProfile();

  Future<void> saveAccountProfile(AccountRemoteProfile value) =>
      _secretStore.saveAccountProfile(value);

  Future<void> clearAccountProfile() => _secretStore.clearAccountProfile();

  Future<String?> loadAccountManagedSecret({required String target}) =>
      _secretStore.loadAccountManagedSecret(target: target);

  Future<void> saveAccountManagedSecret({
    required String target,
    required String value,
  }) => _secretStore.saveAccountManagedSecret(target: target, value: value);

  Future<void> clearAccountManagedSecret({required String target}) =>
      _secretStore.clearAccountManagedSecret(target: target);

  Future<void> clearAccountManagedSecrets() =>
      _secretStore.clearAccountManagedSecrets();

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

  PersistentWriteFailures get persistentWriteFailures =>
      PersistentWriteFailures(
        settings: _settingsStore.settingsWriteFailure,
        tasks: _settingsStore.tasksWriteFailure,
        secrets: _secretStore.secretsWriteFailure,
        audit: _settingsStore.auditWriteFailure,
      );

  void dispose() {
    _settingsStore.dispose();
    _secretStore.dispose();
  }

  static String maskValue(String value) {
    return SecretStore.maskValue(value);
  }
}
