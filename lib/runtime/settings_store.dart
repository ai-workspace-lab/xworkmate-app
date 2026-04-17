import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'file_store_support.dart';
import 'runtime_models.dart';

enum SettingsSnapshotReloadStatus { applied, invalid }

class SettingsSnapshotReloadResult {
  const SettingsSnapshotReloadResult({
    required this.applied,
    required this.snapshot,
  });

  final bool applied;
  final SettingsSnapshot snapshot;
}

class SettingsStore {
  SettingsStore(this._layoutResolver);

  final StoreLayoutResolver _layoutResolver;
  String? _auditWriteFailure;
  String? get auditWriteFailure => _auditWriteFailure;

  Future<void> initialize() async {
    // Basic connectivity check.
    try {
      await _layoutResolver.resolve();
    } catch (e) {
      _auditWriteFailure = 'Storage unavailable: $e';
    }
  }

  Future<SettingsSnapshot> loadSnapshot() async {
    try {
      final layout = await _layoutResolver.resolve();
      final file = File('${layout.configDirectory.path}/settings.yaml');
      if (await file.exists()) {
        final content = await file.readAsString();
        return SettingsSnapshot.fromJsonString(content);
      }
    } catch (e) {
      _auditWriteFailure = 'Failed to load settings: $e';
    }
    return SettingsSnapshot.defaults();
  }

  Future<void> saveSnapshot(SettingsSnapshot snapshot) async {
    try {
      final layout = await _layoutResolver.resolve();
      final file = File('${layout.configDirectory.path}/settings.yaml');
      await file.writeAsString(snapshot.toJsonString(), flush: true);
      _auditWriteFailure = null;
    } catch (e) {
      _auditWriteFailure = 'Failed to save settings: $e';
      // In-memory fallback happens at Controller level via current snapshot retention.
    }
  }

  Future<SettingsSnapshotReloadResult> reloadSnapshotResult() async {
    final next = await loadSnapshot();
    return SettingsSnapshotReloadResult(applied: true, snapshot: next);
  }

  Future<Map<String, TaskThread>> loadTaskThreads() async {
    try {
      final layout = await _layoutResolver.resolve();
      final file = File('${layout.tasksDirectory.path}/threads.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final decoded = jsonDecode(content);
        if (decoded is Map<String, dynamic>) {
          return decoded.map((key, value) => MapEntry(key, TaskThread.fromJson(value)));
        }
      }
    } catch (_) {
      // Ignore errors for secondary persistence.
    }
    return const {};
  }

  Future<void> saveTaskThreads(Map<String, TaskThread> threads) async {
    try {
      final layout = await _layoutResolver.resolve();
      final file = File('${layout.tasksDirectory.path}/threads.json');
      await file.writeAsString(jsonEncode(threads), flush: true);
    } catch (_) {
      // Ignore errors for secondary persistence.
    }
  }

  void dispose() {}
}
