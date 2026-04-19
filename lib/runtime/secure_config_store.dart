import 'dart:convert';
import 'dart:io';

import 'file_store_support.dart';
import 'runtime_models.dart';
import 'secret_store.dart';
import 'settings_store.dart';

class SecureConfigStore {
  SecureConfigStore({
    Future<String?> Function()? secretRootPathResolver,
    Future<String?> Function()? appDataRootPathResolver,
    Future<String?> Function()? supportRootPathResolver,
    StoreLayoutResolver? layoutResolver,
    SettingsStore? settingsStore,
    SecretStore? secretStore,
    bool enableSecureStorage = true,
  }) : _layoutResolver = layoutResolver ?? StoreLayoutResolver(
         secretRootPathResolver: secretRootPathResolver,
         appDataRootPathResolver: appDataRootPathResolver,
         supportRootPathResolver: supportRootPathResolver,
       ),
       _settingsStore = settingsStore ?? SettingsStore(layoutResolver ?? StoreLayoutResolver(
         appDataRootPathResolver: appDataRootPathResolver,
         supportRootPathResolver: supportRootPathResolver,
       )),
       _secretStore = secretStore ?? SecretStore(
         layoutResolver: layoutResolver ?? StoreLayoutResolver(
           secretRootPathResolver: secretRootPathResolver,
           appDataRootPathResolver: appDataRootPathResolver,
           supportRootPathResolver: supportRootPathResolver,
         ),
         enableSecureStorage: enableSecureStorage,
       );

  final StoreLayoutResolver _layoutResolver;
  final SettingsStore _settingsStore;
  final SecretStore _secretStore;

  Future<void> initialize() async {
    await _settingsStore.initialize();
    await _secretStore.initialize();
  }

  Future<SettingsSnapshot> loadSettingsSnapshot() => _settingsStore.loadSnapshot();
  Future<void> saveSettingsSnapshot(SettingsSnapshot snapshot) => _settingsStore.saveSnapshot(snapshot);
  Future<SettingsSnapshotReloadResult> reloadSettingsSnapshotResult() => _settingsStore.reloadSnapshotResult();

  Future<String?> loadSecretValueByRef(String refName) => _secretStore.loadSecretValueByRef(refName);
  Future<void> saveSecretValueByRef(String refName, String value) => _secretStore.saveSecretValueByRef(refName, value);
  Future<void> clearSecretValueByRef(String refName) => _secretStore.clearSecretValueByRef(refName);

  Future<Map<String, String>> loadAccountManagedSecrets() => _secretStore.loadAccountManagedSecrets();
  Future<String?> loadAccountManagedSecret({required String target}) => _secretStore.loadAccountManagedSecret(target: target);
  Future<void> saveAccountManagedSecret({required String target, required String value}) => _secretStore.saveAccountManagedSecret(target: target, value: value);
  Future<void> clearAccountManagedSecret({required String target}) => _secretStore.clearAccountManagedSecret(target: target);
  Future<void> clearAccountManagedSecrets() => _secretStore.clearAccountManagedSecrets();

  Future<AccountSyncState?> loadAccountSyncState() => _secretStore.loadAccountSyncState();
  Future<void> saveAccountSyncState(AccountSyncState value) => _secretStore.saveAccountSyncState(value);
  Future<void> clearAccountSyncState() => _secretStore.clearAccountSyncState();

  Future<List<SecretAuditEntry>> loadAuditTrail() => _settingsStore.loadAuditTrail();
  Future<void> appendAudit(SecretAuditEntry entry) => _settingsStore.appendAudit(entry);

  Future<LocalDeviceIdentity?> loadDeviceIdentity() => _secretStore.loadDeviceIdentity();
  Future<void> saveDeviceIdentity(LocalDeviceIdentity identity) => _secretStore.saveDeviceIdentity(identity);
  Future<String?> loadDeviceToken({required String deviceId, required String role}) => _secretStore.loadDeviceToken(deviceId: deviceId, role: role);
  Future<void> saveDeviceToken({required String deviceId, required String role, required String token}) => _secretStore.saveDeviceToken(deviceId: deviceId, role: role, token: token);
  Future<void> clearDeviceToken({required String deviceId, required String role}) => _secretStore.clearDeviceToken(deviceId: deviceId, role: role);

  Future<Map<String, String>> loadSecureRefs() => _secretStore.loadSecureRefs();

  Future<String?> loadAccountSessionToken() => _secretStore.loadAccountSessionToken();
  Future<void> saveAccountSessionToken(String value) => _secretStore.saveAccountSessionToken(value);
  Future<void> clearAccountSessionToken() => _secretStore.clearAccountSessionToken();

  Future<int?> loadAccountSessionExpiresAtMs() => _secretStore.loadAccountSessionExpiresAtMs().then((v) => v == 0 ? null : v);
  Future<void> saveAccountSessionExpiresAtMs(int value) => _secretStore.saveAccountSessionExpiresAtMs(value);
  Future<void> clearAccountSessionExpiresAtMs() => _secretStore.clearAccountSessionExpiresAtMs();

  Future<String?> loadAccountSessionUserId() => _secretStore.loadAccountSessionUserId();
  Future<void> saveAccountSessionUserId(String value) => _secretStore.saveAccountSessionUserId(value);
  Future<void> clearAccountSessionUserId() => _secretStore.clearAccountSessionUserId();

  Future<String?> loadAccountSessionIdentifier() => _secretStore.loadAccountSessionIdentifier();
  Future<void> saveAccountSessionIdentifier(String value) => _secretStore.saveAccountSessionIdentifier(value);
  Future<void> clearAccountSessionIdentifier() => _secretStore.clearAccountSessionIdentifier();

  Future<AccountSessionSummary?> loadAccountSessionSummary() => _secretStore.loadAccountSessionSummary();
  Future<void> saveAccountSessionSummary(AccountSessionSummary value) => _secretStore.saveAccountSessionSummary(value);
  Future<void> clearAccountSessionSummary() => _secretStore.clearAccountSessionSummary();

  Future<List<TaskThread>> loadTaskThreads() => _settingsStore.loadTaskThreads();
  Future<void> saveTaskThreads(List<TaskThread> threads) => _settingsStore.saveTaskThreads(threads);
  List<SkippedTaskThreadRecord> get lastSkippedInvalidTaskThreadRecords => _settingsStore.lastSkippedInvalidTaskThreadRecords;

  Future<void> clearAssistantLocalState() => _settingsStore.clearAssistantLocalState();

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

  Future<AppUiState> loadAppUiState() async {
    final payload = await loadSupportJson('ui/state.json');
    if (payload == null) {
      return AppUiState.defaults();
    }
    try {
      return AppUiState.fromJson(payload);
    } catch (_) {
      return AppUiState.defaults();
    }
  }

  Future<void> saveAppUiState(AppUiState value) =>
      saveSupportJson('ui/state.json', value.toJson());

  Future<void> clearAppUiState() async {
    final file = await supportFile('ui/state.json');
    if (file == null) {
      return;
    }
    await deleteIfExists(file);
  }

  PersistentWriteFailures get persistentWriteFailures =>
      PersistentWriteFailures(
        settings: _settingsStore.auditWriteFailure,
        tasks: _settingsStore.tasksWriteFailure,
        secrets: _secretStore.secretsWriteFailure,
        audit: _settingsStore.auditWriteFailure,
      );

  Future<File?> resolvedSettingsFile() => _layoutResolver.resolve().then((l) => File('${l.configDirectory.path}/settings.yaml'));
  Future<Directory?> resolvedSettingsWatchDirectory() => _layoutResolver.resolve().then((l) => l.configDirectory);

  Map<String, String> get secureRefs => _secretStore.secureRefs;
  PersistentWriteFailure? get settingsWriteFailure => _settingsStore.settingsWriteFailure;

  void dispose() {
    _settingsStore.dispose();
    _secretStore.dispose();
  }

  static String maskValue(String value) => SecretStore.maskValue(value);
}
