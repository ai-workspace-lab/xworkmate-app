import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/package_info_plus.dart';

import 'file_store_support.dart';
import 'runtime_models.dart';
import 'secret_store.dart';
import 'settings_store.dart';

class SecureConfigStore {
  SecureConfigStore({
    StoreLayoutResolver? layoutResolver,
    SettingsStore? settingsStore,
    SecretStore? secretStore,
  }) : _layoutResolver = layoutResolver ?? StoreLayoutResolver(),
       _settingsStore = settingsStore ?? SettingsStore(layoutResolver ?? StoreLayoutResolver()),
       _secretStore = secretStore ?? SecretStore(layoutResolver ?? StoreLayoutResolver());

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

  Future<Map<String, String>> loadAccountManagedSecrets() => _secretStore.loadAccountManagedSecrets();
  Future<void> saveAccountManagedSecret({required String target, required String value}) => _secretStore.saveAccountManagedSecret(target: target, value: value);
  Future<void> clearAccountManagedSecret({required String target}) => _secretStore.clearAccountManagedSecret(target: target);
  Future<void> clearAccountManagedSecrets() => _secretStore.clearAccountManagedSecrets();

  Future<String?> loadAccountSessionToken() => _secretStore.loadAccountSessionToken();
  Future<void> saveAccountSessionToken(String value) => _secretStore.saveAccountSessionToken(value);
  Future<void> clearAccountSessionToken() => _secretStore.clearAccountSessionToken();

  Future<int?> loadAccountSessionExpiresAtMs() => _secretStore.loadAccountSessionExpiresAtMs();
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

  Future<AccountSyncState?> loadAccountSyncState() => _secretStore.loadAccountSyncState();
  Future<void> saveAccountSyncState(AccountSyncState value) => _secretStore.saveAccountSyncState(value);
  Future<void> clearAccountSyncState() => _secretStore.clearAccountSyncState();

  Future<Map<String, TaskThread>> loadTaskThreads() => _settingsStore.loadTaskThreads();
  Future<void> saveTaskThreads(Map<String, TaskThread> threads) => _settingsStore.saveTaskThreads(threads);

  Future<List<SecretAuditEntry>> loadAuditTrail() => _secretStore.loadAuditTrail();
  Future<void> appendAudit(SecretAuditEntry entry) => _secretStore.appendAudit(entry);

  Future<File?> resolvedSettingsFile() => _layoutResolver.resolve().then((l) => File('${l.configDirectory.path}/settings.yaml'));
  Future<Directory?> resolvedSettingsWatchDirectory() => _layoutResolver.resolve().then((l) => l.configDirectory);

  Map<String, String> get secureRefs => _secretStore.secureRefs;
  String? get settingsWriteFailure => _settingsStore.auditWriteFailure;

  void dispose() {
    _settingsStore.dispose();
    _secretStore.dispose();
  }

  static String maskValue(String value) => SecretStore.maskValue(value);
}
