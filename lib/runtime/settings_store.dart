import 'dart:async';

import 'runtime_models.dart';

typedef SecureConfigDatabaseOpener = FutureOr<Object?> Function(
  String resolvedPath,
);

class SettingsStore {
  SettingsStore({
    Future<String?> Function()? fallbackDirectoryPathResolver,
    Future<String?> Function()? databasePathResolver,
    Future<String?> Function()? defaultSupportDirectoryPathResolver,
    SecureConfigDatabaseOpener? databaseOpener,
  });

  static const String settingsKey = 'xworkmate.settings.snapshot';
  static const String auditKey = 'xworkmate.secrets.audit';
  static const String assistantThreadsKey = 'xworkmate.assistant.threads';
  static const String databaseFileName = 'config-store.sqlite3';
  static const String databaseTableName = 'config_entries';

  Future<void> initialize() async {}

  Future<SettingsSnapshot> loadSettingsSnapshot() {
    throw StateError(
      'Legacy settings persistence removed. New file-based settings store is pending implementation.',
    );
  }

  Future<void> saveSettingsSnapshot(SettingsSnapshot snapshot) {
    throw StateError(
      'Legacy settings persistence removed. New file-based settings store is pending implementation.',
    );
  }

  Future<List<AssistantThreadRecord>> loadAssistantThreadRecords() {
    throw StateError(
      'Legacy settings persistence removed. New file-based settings store is pending implementation.',
    );
  }

  Future<void> saveAssistantThreadRecords(
    List<AssistantThreadRecord> records,
  ) {
    throw StateError(
      'Legacy settings persistence removed. New file-based settings store is pending implementation.',
    );
  }

  Future<void> clearAssistantLocalState() {
    throw StateError(
      'Legacy settings persistence removed. New file-based settings store is pending implementation.',
    );
  }

  Future<List<SecretAuditEntry>> loadAuditTrail() {
    throw StateError(
      'Legacy settings persistence removed. New file-based settings store is pending implementation.',
    );
  }

  Future<void> appendAudit(SecretAuditEntry entry) {
    throw StateError(
      'Legacy settings persistence removed. New file-based settings store is pending implementation.',
    );
  }

  void dispose() {}
}
