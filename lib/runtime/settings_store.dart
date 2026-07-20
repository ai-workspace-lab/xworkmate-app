import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

enum SkippedTaskThreadReason {
  removedAutoExecutionMode,
  incompleteWorkspaceBinding,
  invalidPersistedThreadData,
}

class SkippedTaskThreadRecord {
  const SkippedTaskThreadRecord({required this.threadId, required this.reason});

  final String threadId;
  final SkippedTaskThreadReason reason;
}

class SettingsStore {
  SettingsStore(this._layoutResolver);

  final StoreLayoutResolver _layoutResolver;

  PersistentWriteFailure? _settingsWriteFailure;
  PersistentWriteFailure? get settingsWriteFailure => _settingsWriteFailure;

  PersistentWriteFailure? _tasksWriteFailure;
  PersistentWriteFailure? get tasksWriteFailure => _tasksWriteFailure;

  PersistentWriteFailure? _auditWriteFailure;
  PersistentWriteFailure? get auditWriteFailure => _auditWriteFailure;

  final List<SkippedTaskThreadRecord> _lastSkippedInvalidTaskThreadRecords = [];
  List<SkippedTaskThreadRecord> get lastSkippedInvalidTaskThreadRecords =>
      List.unmodifiable(_lastSkippedInvalidTaskThreadRecords);

  Future<void> initialize() async {
    // Basic connectivity check.
    try {
      await _layoutResolver.resolve();
    } catch (e) {
      _settingsWriteFailure = _wrapFailure(
        'initialize',
        PersistentStoreScope.settings,
        e,
      );
    }
  }

  Future<SettingsSnapshot> loadSnapshot() async {
    try {
      if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
        final prefs = await SharedPreferences.getInstance();
        final content = prefs.getString('xworkmate.settings.yaml');
        if (content != null) {
          return SettingsSnapshot.fromJsonString(content);
        }
        final layout = await _layoutResolver.resolve();
        final file = File('${layout.configDirectory.path}/settings.yaml');
        if (await file.exists()) {
          final legacyContent = await file.readAsString();
          await prefs.setString('xworkmate.settings.yaml', legacyContent);
          return SettingsSnapshot.fromJsonString(legacyContent);
        }
        return SettingsSnapshot.defaults();
      }
      final layout = await _layoutResolver.resolve();
      final file = File('${layout.configDirectory.path}/settings.yaml');
      if (await file.exists()) {
        final content = await file.readAsString();
        return SettingsSnapshot.fromJsonString(content);
      }
    } catch (e) {
      _settingsWriteFailure = _wrapFailure(
        'loadSnapshot',
        PersistentStoreScope.settings,
        e,
      );
    }
    return SettingsSnapshot.defaults();
  }

  Future<void> saveSnapshot(SettingsSnapshot snapshot) async {
    try {
      if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('xworkmate.settings.yaml', snapshot.toJsonString());
        _settingsWriteFailure = null;
        return;
      }
      final layout = await _layoutResolver.resolve();
      final file = File('${layout.configDirectory.path}/settings.yaml');
      await file.writeAsString(snapshot.toJsonString(), flush: true);
      _settingsWriteFailure = null;
    } catch (e) {
      _settingsWriteFailure = _wrapFailure(
        'saveSnapshot',
        PersistentStoreScope.settings,
        e,
      );
    }
  }

  Future<SettingsSnapshotReloadResult> reloadSnapshotResult() async {
    final next = await loadSnapshot();
    return SettingsSnapshotReloadResult(applied: true, snapshot: next);
  }

  static const String _legacyThreadsFileName = 'threads.json';
  static const String _threadIndexFileName = 'index.json';

  /// 上次成功写入的每会话 JSON,按 threadId 记。null 值表示文件存在但内容
  /// 未知(冷启动 prime 时只列了文件名),下次 save 会强制重写。
  final Map<String, String?> _lastWrittenThreadJsonByThreadId =
      <String, String?>{};
  List<String> _lastWrittenThreadIndex = const <String>[];
  bool _threadCachePrimed = false;

  Future<List<TaskThread>> loadTaskThreads() async {
    _lastSkippedInvalidTaskThreadRecords.clear();
    try {
      if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
        return await _loadPerSessionTaskThreadsMobile();
      }
      final layout = await _layoutResolver.resolve();
      return await _loadPerSessionTaskThreads(layout);
    } catch (e) {
      _tasksWriteFailure = _wrapFailure(
        'loadTaskThreads',
        PersistentStoreScope.tasks,
        e,
      );
    }
    return const [];
  }

  bool _isThreadPayloadFile(File file) {
    final name = file.uri.pathSegments.last;
    return name.endsWith('.json') &&
        name != _threadIndexFileName &&
        name != _legacyThreadsFileName &&
        !name.contains('.invalid-') &&
        !name.contains('.migrated-') &&
        !name.contains('.tmp-');
  }

  Future<List<TaskThread>> _loadPerSessionTaskThreads(
    StoreLayout layout,
  ) async {
    final indexIds = await _readThreadIndex(layout);
    final byId = <String, TaskThread>{};
    final files = layout.tasksDirectory
        .listSync()
        .whereType<File>()
        .where(_isThreadPayloadFile)
        .toList();
    for (final file in files) {
      String threadId =
          decodeStableFileKey(
            file.uri.pathSegments.last.replaceAll(RegExp(r'\.json$'), ''),
          ) ??
          'unknown';
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is! Map) {
          throw const FormatException('not-a-map');
        }
        final map = decoded.cast<String, dynamic>();
        final persistedId = map['threadId']?.toString().trim() ?? '';
        if (persistedId.isNotEmpty) {
          threadId = persistedId;
        }
        byId[threadId] = TaskThread.fromJson(map);
      } catch (error) {
        // 坏一个文件只丢一个会话;原字节备份后从工作集中拿掉,避免每次
        // 启动都重复失败。
        _recordSkippedTaskThread(threadId, error);
        await _backupUnreadableTaskThreads(file);
        await deleteIfExists(file);
      }
    }
    final ordered = <TaskThread>[];
    for (final threadId in indexIds) {
      final thread = byId.remove(threadId);
      if (thread != null) {
        ordered.add(thread);
      }
    }
    // index 写入前进程被杀会留下不在 index 里的孤儿文件;按 threadId 排序
    // 追加,保证结果确定。
    final orphanIds = byId.keys.toList()..sort();
    ordered.addAll(orphanIds.map((threadId) => byId[threadId]!));

    _lastWrittenThreadJsonByThreadId
      ..clear()
      ..addEntries(
        ordered.map(
          (thread) =>
              MapEntry<String, String?>(thread.threadId, jsonEncode(thread)),
        ),
      );
    _lastWrittenThreadIndex = ordered
        .map((thread) => thread.threadId)
        .toList(growable: false);
    _threadCachePrimed = true;
    return ordered;
  }

  Future<List<String>> _readThreadIndex(StoreLayout layout) async {
    try {
      final file = layout.taskIndexFile;
      if (!await file.exists()) {
        return const [];
      }
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map && decoded['threadIds'] is List) {
        return (decoded['threadIds'] as List)
            .map((item) => item.toString())
            .toList(growable: false);
      }
    } catch (e, stackTrace) {
      // index 只承载排序;损坏时靠目录扫描兜底,不算数据丢失。
      debugPrint(
        'Thread index unreadable, falling back to scan: $e\n$stackTrace',
      );
    }
    return const [];
  }

  void _recordSkippedTaskThread(String threadId, Object error) {
    // Reason mapping keys off the throw sites in TaskThread: the legacy
    // "auto" execution mode raises FormatException("... no longer supported")
    // and an incomplete workspace binding raises StateError mentioning
    // workspaceBinding. Anything else counts as invalid persisted data.
    final message = error.toString();
    final SkippedTaskThreadReason reason;
    if (message.contains('no longer supported')) {
      reason = SkippedTaskThreadReason.removedAutoExecutionMode;
    } else if (message.contains('workspaceBinding')) {
      reason = SkippedTaskThreadReason.incompleteWorkspaceBinding;
    } else {
      reason = SkippedTaskThreadReason.invalidPersistedThreadData;
    }
    _lastSkippedInvalidTaskThreadRecords.add(
      SkippedTaskThreadRecord(threadId: threadId, reason: reason),
    );
  }

  Future<void> _backupUnreadableTaskThreads(File file) async {
    // Keep the original bytes recoverable before any later save rewrites
    // threads.json with only the surviving subset.
    try {
      if (!await file.exists()) {
        return;
      }
      final stamp = DateTime.now().millisecondsSinceEpoch;
      await file.copy('${file.path}.invalid-$stamp.bak');
    } catch (e, stackTrace) {
      debugPrint('Task thread backup failed: $e\n$stackTrace');
    }
  }

  Future<void> saveTaskThreads(List<TaskThread> threads) async {
    try {
      if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
        await _saveTaskThreadsMobile(threads);
        return;
      }
      final layout = await _layoutResolver.resolve();
      if (!_threadCachePrimed) {
        // 冷缓存只需要文件名集合就能做删除对账;内容未知记 null,
        // 本轮全部重写一遍。
        _lastWrittenThreadJsonByThreadId.clear();
        final existing = layout.tasksDirectory
            .listSync()
            .whereType<File>()
            .where(_isThreadPayloadFile);
        for (final file in existing) {
          final threadId = decodeStableFileKey(
            file.uri.pathSegments.last.replaceAll(RegExp(r'\.json$'), ''),
          );
          if (threadId != null) {
            _lastWrittenThreadJsonByThreadId[threadId] = null;
          }
        }
        _threadCachePrimed = true;
      }

      final desiredJsonByThreadId = <String, String>{
        for (final thread in threads) thread.threadId: jsonEncode(thread),
      };
      for (final entry in desiredJsonByThreadId.entries) {
        if (_lastWrittenThreadJsonByThreadId[entry.key] == entry.value) {
          continue;
        }
        await atomicWriteString(
          layout.taskFileForSessionKey(entry.key),
          entry.value,
        );
      }
      final removedThreadIds = _lastWrittenThreadJsonByThreadId.keys
          .where((threadId) => !desiredJsonByThreadId.containsKey(threadId))
          .toList(growable: false);
      for (final threadId in removedThreadIds) {
        await deleteIfExists(layout.taskFileForSessionKey(threadId));
      }

      final nextIndex = threads
          .map((thread) => thread.threadId)
          .toList(growable: false);
      if (!listEquals(nextIndex, _lastWrittenThreadIndex)) {
        await atomicWriteString(
          layout.taskIndexFile,
          jsonEncode(<String, dynamic>{'version': 1, 'threadIds': nextIndex}),
        );
      }

      _lastWrittenThreadJsonByThreadId
        ..clear()
        ..addAll(desiredJsonByThreadId);
      _lastWrittenThreadIndex = nextIndex;
      _tasksWriteFailure = null;
    } catch (e) {
      _tasksWriteFailure = _wrapFailure(
        'saveTaskThreads',
        PersistentStoreScope.tasks,
        e,
      );
    }
  }

  Future<void> clearAssistantLocalState() async {
    try {
      if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('xworkmate.settings.yaml');
        await prefs.remove('xworkmate.tasks.index');
        final keys = prefs.getKeys().where((k) => k.startsWith('xworkmate.tasks.thread.')).toList();
        for (final k in keys) {
           await prefs.remove(k);
        }
        _lastWrittenThreadJsonByThreadId.clear();
        _lastWrittenThreadIndex = const <String>[];
        _threadCachePrimed = true;
        return;
      }
      final layout = await _layoutResolver.resolve();
      await deleteIfExists(layout.taskIndexFile);
      final payloadFiles = layout.tasksDirectory
          .listSync()
          .whereType<File>()
          .where(_isThreadPayloadFile)
          .toList();
      for (final file in payloadFiles) {
        await deleteIfExists(file);
      }
      _lastWrittenThreadJsonByThreadId.clear();
      _lastWrittenThreadIndex = const <String>[];
      _threadCachePrimed = true;
      await deleteIfExists(
        File('${layout.configDirectory.path}/settings.yaml'),
      );
    } catch (e, stackTrace) {
      debugPrint('Error: $e\n$stackTrace');
      // Ignore errors for secondary persistence.
    }
  }

  Future<List<SecretAuditEntry>> loadAuditTrail() async {
    try {
      if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
        final prefs = await SharedPreferences.getInstance();
        final content = prefs.getString('xworkmate.audit.json');
        if (content != null) {
          final decoded = jsonDecode(content);
          if (decoded is List) {
            return decoded.map((e) => SecretAuditEntry.fromJson(e)).toList();
          }
        } else {
          final layout = await _layoutResolver.resolve();
          final file = File('${layout.configDirectory.path}/audit.json');
          if (await file.exists()) {
            final legacyContent = await file.readAsString();
            final decoded = jsonDecode(legacyContent);
            if (decoded is List) {
              await prefs.setString('xworkmate.audit.json', legacyContent);
              return decoded.map((e) => SecretAuditEntry.fromJson(e)).toList();
            }
          }
        }
        return const [];
      }
      final layout = await _layoutResolver.resolve();
      final file = File('${layout.configDirectory.path}/audit.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final decoded = jsonDecode(content);
        if (decoded is List) {
          return decoded.map((e) => SecretAuditEntry.fromJson(e)).toList();
        }
      }
    } catch (e, stackTrace) {
      debugPrint('Error: $e\n$stackTrace');
      // Ignore errors for secondary persistence.
    }
    return const [];
  }

  Future<void> appendAudit(SecretAuditEntry entry) async {
    try {
      final items = (await loadAuditTrail()).toList(growable: true);
      items.insert(0, entry);
      if (items.length > 40) {
        items.removeRange(40, items.length);
      }
      if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('xworkmate.audit.json', jsonEncode(items));
        _auditWriteFailure = null;
        return;
      }
      final layout = await _layoutResolver.resolve();
      final file = File('${layout.configDirectory.path}/audit.json');
      await file.writeAsString(jsonEncode(items), flush: true);
      _auditWriteFailure = null;
    } catch (e) {
      _auditWriteFailure = _wrapFailure(
        'appendAudit',
        PersistentStoreScope.audit,
        e,
      );
    }
  }


  Future<List<TaskThread>> _loadPerSessionTaskThreadsMobile() async {
    final prefs = await SharedPreferences.getInstance();
    final rawIndex = prefs.getString('xworkmate.tasks.index');
    List<String> indexIds = const [];
    if (rawIndex != null) {
      try {
        final decoded = jsonDecode(rawIndex);
        if (decoded is Map && decoded['threadIds'] is List) {
          indexIds = (decoded['threadIds'] as List)
              .map((item) => item.toString())
              .toList(growable: false);
        }
      } catch (e) {}
    } else {
      final keys = prefs.getKeys().where((k) => k.startsWith('xworkmate.tasks.thread.')).toList();
      if (keys.isEmpty) {
        try {
          final layout = await _layoutResolver.resolve();
          final legacyThreads = await _loadPerSessionTaskThreads(layout);
          if (legacyThreads.isNotEmpty) {
            await _saveTaskThreadsMobile(legacyThreads);
            return legacyThreads;
          }
        } catch (e) {
          debugPrint('Legacy task migration failed: $e');
        }
      }
    }

    final keys = prefs.getKeys().where((k) => k.startsWith('xworkmate.tasks.thread.')).toList();
    final byId = <String, TaskThread>{};
    for (final k in keys) {
      String threadId = k.substring('xworkmate.tasks.thread.'.length);
      try {
        final raw = prefs.getString(k);
        if (raw != null) {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            final map = decoded.cast<String, dynamic>();
            final persistedId = map['threadId']?.toString().trim() ?? '';
            if (persistedId.isNotEmpty) {
              threadId = persistedId;
            }
            byId[threadId] = TaskThread.fromJson(map);
          }
        }
      } catch (error) {
        _recordSkippedTaskThread(threadId, error);
        await prefs.remove(k);
      }
    }

    final ordered = <TaskThread>[];
    for (final threadId in indexIds) {
      final thread = byId.remove(threadId);
      if (thread != null) {
        ordered.add(thread);
      }
    }
    final orphanIds = byId.keys.toList()..sort();
    ordered.addAll(orphanIds.map((threadId) => byId[threadId]!));

    _lastWrittenThreadJsonByThreadId
      ..clear()
      ..addEntries(
        ordered.map(
          (thread) =>
              MapEntry<String, String?>(thread.threadId, jsonEncode(thread)),
        ),
      );
    _lastWrittenThreadIndex = ordered
        .map((thread) => thread.threadId)
        .toList(growable: false);
    _threadCachePrimed = true;
    return ordered;
  }

  Future<void> _saveTaskThreadsMobile(List<TaskThread> threads) async {
    final prefs = await SharedPreferences.getInstance();
    if (!_threadCachePrimed) {
      _lastWrittenThreadJsonByThreadId.clear();
      final keys = prefs.getKeys().where((k) => k.startsWith('xworkmate.tasks.thread.')).toList();
      for (final k in keys) {
        final threadId = k.substring('xworkmate.tasks.thread.'.length);
        _lastWrittenThreadJsonByThreadId[threadId] = null;
      }
      _threadCachePrimed = true;
    }

    final desiredJsonByThreadId = <String, String>{
      for (final thread in threads) thread.threadId: jsonEncode(thread),
    };

    for (final entry in desiredJsonByThreadId.entries) {
      if (_lastWrittenThreadJsonByThreadId[entry.key] == entry.value) {
        continue;
      }
      await prefs.setString('xworkmate.tasks.thread.${entry.key}', entry.value);
    }

    final removedThreadIds = _lastWrittenThreadJsonByThreadId.keys
        .where((threadId) => !desiredJsonByThreadId.containsKey(threadId))
        .toList(growable: false);
    for (final threadId in removedThreadIds) {
      await prefs.remove('xworkmate.tasks.thread.$threadId');
    }

    final nextIndex = threads
        .map((thread) => thread.threadId)
        .toList(growable: false);
    if (!listEquals(nextIndex, _lastWrittenThreadIndex)) {
      await prefs.setString(
        'xworkmate.tasks.index',
        jsonEncode(<String, dynamic>{'version': 1, 'threadIds': nextIndex}),
      );
    }

    _lastWrittenThreadJsonByThreadId
      ..clear()
      ..addAll(desiredJsonByThreadId);
    _lastWrittenThreadIndex = nextIndex;
    _tasksWriteFailure = null;
  }

  PersistentWriteFailure _wrapFailure(
    String operation,
    PersistentStoreScope scope,
    Object error,
  ) {
    return PersistentWriteFailure(
      scope: scope,
      operation: operation,
      message: error.toString(),
      timestampMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  void dispose() {}
}
