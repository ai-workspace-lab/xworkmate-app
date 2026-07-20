import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'file_store_support.dart';
import 'runtime_models.dart';

/// 解码失败时的上报回调:store 只负责隔离与上报,原因归类留给调用方。
typedef TaskThreadSkipRecorder = void Function(String threadId, Object error);

/// 每会话任务线程持久化后端的统一契约。
///
/// 平台与介质差异(桌面文件布局、移动端 SharedPreferences、未来的
/// iCloud / 云同步后端)收敛在 [TaskThreadStoreProvider] 层,上层
/// `SettingsStore` 只面向本接口,不再出现平台分支。
abstract class TaskThreadStore {
  Future<List<TaskThread>> load();

  Future<void> save(List<TaskThread> threads);

  Future<void> clear();
}

/// 存储后端接入点。新的后端(例如 iCloud key-value / CloudKit、其他云
/// 存储)实现本接口并加入 [TaskThreadStoreRegistry] 即可参与选择,
/// 无需改动 `SettingsStore`。
abstract class TaskThreadStoreProvider {
  String get id;

  bool get supportsCurrentPlatform;

  TaskThreadStore open({
    required StoreLayoutResolver layoutResolver,
    required TaskThreadSkipRecorder onSkippedRecord,
  });
}

class TaskThreadStoreRegistry {
  TaskThreadStoreRegistry({List<TaskThreadStoreProvider>? providers})
    : _providers = List.unmodifiable(providers ?? defaultProviders());

  final List<TaskThreadStoreProvider> _providers;

  /// 内置顺序即优先级:移动端命中 SharedPreferences 后端,桌面端命中
  /// 文件后端。
  static List<TaskThreadStoreProvider> defaultProviders() =>
      <TaskThreadStoreProvider>[
        PrefsTaskThreadStoreProvider(),
        FileTaskThreadStoreProvider(),
      ];

  TaskThreadStoreProvider resolveForPlatform() {
    for (final provider in _providers) {
      if (provider.supportsCurrentPlatform) {
        return provider;
      }
    }
    throw StateError('No task thread store provider supports this platform.');
  }
}

class FileTaskThreadStoreProvider implements TaskThreadStoreProvider {
  static const String providerId = 'local-file';

  @override
  String get id => providerId;

  @override
  bool get supportsCurrentPlatform => !kIsWeb;

  @override
  TaskThreadStore open({
    required StoreLayoutResolver layoutResolver,
    required TaskThreadSkipRecorder onSkippedRecord,
  }) => FileTaskThreadStore(
    layoutResolver: layoutResolver,
    onSkippedRecord: onSkippedRecord,
  );
}

class PrefsTaskThreadStoreProvider implements TaskThreadStoreProvider {
  static const String providerId = 'shared-preferences';

  @override
  String get id => providerId;

  @override
  bool get supportsCurrentPlatform =>
      !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  @override
  TaskThreadStore open({
    required StoreLayoutResolver layoutResolver,
    required TaskThreadSkipRecorder onSkippedRecord,
  }) => PrefsTaskThreadStore(onSkippedRecord: onSkippedRecord);
}

/// 桌面端:每会话一个 JSON 文件 + `index.json` 排序索引。
class FileTaskThreadStore implements TaskThreadStore {
  FileTaskThreadStore({
    required StoreLayoutResolver layoutResolver,
    required TaskThreadSkipRecorder onSkippedRecord,
  }) : _layoutResolver = layoutResolver,
       _onSkippedRecord = onSkippedRecord;

  static const String _indexFileName = 'index.json';

  final StoreLayoutResolver _layoutResolver;
  final TaskThreadSkipRecorder _onSkippedRecord;

  /// 上次成功写入的每会话 JSON,按 threadId 记。null 值表示文件存在但
  /// 内容未知(冷启动 prime 时只列了文件名),下次 save 会强制重写。
  final Map<String, String?> _lastWrittenThreadJsonByThreadId =
      <String, String?>{};
  List<String> _lastWrittenThreadIndex = const <String>[];
  bool _cachePrimed = false;

  bool _isThreadPayloadFile(File file) {
    final name = file.uri.pathSegments.last;
    return name.endsWith('.json') &&
        name != _indexFileName &&
        name != 'threads.json' &&
        !name.contains('.invalid-') &&
        !name.contains('.migrated-') &&
        !name.contains('.tmp-');
  }

  @override
  Future<List<TaskThread>> load() async {
    final layout = await _layoutResolver.resolve();
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
        _onSkippedRecord(threadId, error);
        await _backupUnreadableFile(file);
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

    _primeCacheFromThreads(ordered);
    return ordered;
  }

  @override
  Future<void> save(List<TaskThread> threads) async {
    final layout = await _layoutResolver.resolve();
    if (!_cachePrimed) {
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
      _cachePrimed = true;
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
  }

  @override
  Future<void> clear() async {
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
    _cachePrimed = true;
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

  Future<void> _backupUnreadableFile(File file) async {
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

  void _primeCacheFromThreads(List<TaskThread> ordered) {
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
    _cachePrimed = true;
  }
}

/// 移动端:SharedPreferences(iOS UserDefaults / Android)。
///
/// 选型依据:值由系统守护进程落盘,App 被杀不丢已写入的值;卸载即清,
/// 与 Keychain 残留组合出「重装即登出」;天然免疫 iOS 容器路径漂移。
/// 这是移动端唯一真值源——没有文件回退,也没有旧数据迁移。
class PrefsTaskThreadStore implements TaskThreadStore {
  PrefsTaskThreadStore({required TaskThreadSkipRecorder onSkippedRecord})
    : _onSkippedRecord = onSkippedRecord;

  static const String threadKeyPrefix = 'xworkmate.tasks.thread.';
  static const String indexKey = 'xworkmate.tasks.index';
  static const String invalidKeyPrefix = 'xworkmate.tasks.invalid.';
  static const String taskKeyPrefix = 'xworkmate.tasks.';

  /// 未来 schema 变更的迁移锚点;当前版本仅打标,不做迁移。
  static const String schemaVersionKey = 'xworkmate.storage.schemaVersion';
  static const int schemaVersion = 1;

  final TaskThreadSkipRecorder _onSkippedRecord;

  final Map<String, String?> _lastWrittenThreadJsonByThreadId =
      <String, String?>{};
  List<String> _lastWrittenThreadIndex = const <String>[];
  bool _cachePrimed = false;

  @override
  Future<List<TaskThread>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final indexIds = _readIndex(prefs);
    final keys = prefs
        .getKeys()
        .where((key) => key.startsWith(threadKeyPrefix))
        .toList();
    final byId = <String, TaskThread>{};
    for (final key in keys) {
      String threadId = key.substring(threadKeyPrefix.length);
      final raw = prefs.getString(key);
      try {
        if (raw == null) {
          throw const FormatException('not-a-string');
        }
        final decoded = jsonDecode(raw);
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
        // 坏一个值只丢一个会话;原始字符串备份到 invalid 键后从工作集
        // 移除,避免每次启动重复失败。
        _onSkippedRecord(threadId, error);
        if (raw != null) {
          final stamp = DateTime.now().millisecondsSinceEpoch;
          await prefs.setString('$invalidKeyPrefix$threadId-$stamp', raw);
        }
        await prefs.remove(key);
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
    _cachePrimed = true;
    return ordered;
  }

  @override
  Future<void> save(List<TaskThread> threads) async {
    final prefs = await SharedPreferences.getInstance();
    if (!_cachePrimed) {
      _lastWrittenThreadJsonByThreadId.clear();
      final keys = prefs
          .getKeys()
          .where((key) => key.startsWith(threadKeyPrefix))
          .toList();
      for (final key in keys) {
        _lastWrittenThreadJsonByThreadId[key.substring(
              threadKeyPrefix.length,
            )] =
            null;
      }
      _cachePrimed = true;
    }

    final desiredJsonByThreadId = <String, String>{
      for (final thread in threads) thread.threadId: jsonEncode(thread),
    };
    for (final entry in desiredJsonByThreadId.entries) {
      if (_lastWrittenThreadJsonByThreadId[entry.key] == entry.value) {
        continue;
      }
      await prefs.setString('$threadKeyPrefix${entry.key}', entry.value);
    }
    final removedThreadIds = _lastWrittenThreadJsonByThreadId.keys
        .where((threadId) => !desiredJsonByThreadId.containsKey(threadId))
        .toList(growable: false);
    for (final threadId in removedThreadIds) {
      await prefs.remove('$threadKeyPrefix$threadId');
    }

    final nextIndex = threads
        .map((thread) => thread.threadId)
        .toList(growable: false);
    if (!listEquals(nextIndex, _lastWrittenThreadIndex)) {
      await prefs.setString(
        indexKey,
        jsonEncode(<String, dynamic>{'version': 1, 'threadIds': nextIndex}),
      );
    }
    await prefs.setInt(schemaVersionKey, schemaVersion);

    _lastWrittenThreadJsonByThreadId
      ..clear()
      ..addAll(desiredJsonByThreadId);
    _lastWrittenThreadIndex = nextIndex;
  }

  @override
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs
        .getKeys()
        .where((key) => key.startsWith(taskKeyPrefix))
        .toList();
    for (final key in keys) {
      await prefs.remove(key);
    }
    _lastWrittenThreadJsonByThreadId.clear();
    _lastWrittenThreadIndex = const <String>[];
    _cachePrimed = true;
    await prefs.setInt(schemaVersionKey, schemaVersion);
  }

  List<String> _readIndex(SharedPreferences prefs) {
    final rawIndex = prefs.getString(indexKey);
    if (rawIndex == null) {
      return const [];
    }
    try {
      final decoded = jsonDecode(rawIndex);
      if (decoded is Map && decoded['threadIds'] is List) {
        return (decoded['threadIds'] as List)
            .map((item) => item.toString())
            .toList(growable: false);
      }
    } catch (e) {
      // index 只承载排序;损坏时靠键扫描兜底,不算数据丢失。
      debugPrint('Prefs thread index unreadable, falling back to scan: $e');
    }
    return const [];
  }
}
