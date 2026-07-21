import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xworkmate/runtime/file_store_support.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/task_thread_store.dart';

TaskThread _thread(String threadId) {
  return TaskThread(
    threadId: threadId,
    title: 'thread $threadId',
    workspaceBinding: WorkspaceBinding(
      workspaceId: threadId,
      workspaceKind: WorkspaceKind.localFs,
      workspacePath: '/tmp/xworkmate-test-ws/$threadId',
      displayPath: '/tmp/xworkmate-test-ws/$threadId',
      writable: true,
    ),
  );
}

class _FakeProvider implements TaskThreadStoreProvider {
  _FakeProvider(this.id, {required this.supported});

  @override
  final String id;
  final bool supported;

  @override
  bool get supportsCurrentPlatform => supported;

  @override
  TaskThreadStore open({
    required StoreLayoutResolver layoutResolver,
    required TaskThreadSkipRecorder onSkippedRecord,
  }) {
    throw UnimplementedError('fake provider never opens');
  }
}

void main() {
  group('PrefsTaskThreadStore', () {
    late List<String> skippedThreadIds;
    late PrefsTaskThreadStore store;

    PrefsTaskThreadStore newStore() => PrefsTaskThreadStore(
      onSkippedRecord: (threadId, error) => skippedThreadIds.add(threadId),
    );

    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      skippedThreadIds = <String>[];
      store = newStore();
    });

    test('round-trips a saved thread list', () async {
      await store.save([_thread('draft-a'), _thread('draft-b')]);

      final loaded = await newStore().load();

      expect(loaded.map((t) => t.threadId).toList(), ['draft-a', 'draft-b']);
    });

    test('load returns threads in index order', () async {
      await store.save([_thread('draft-a'), _thread('draft-b')]);
      await store.save([_thread('draft-b'), _thread('draft-a')]);

      final loaded = await newStore().load();

      expect(loaded.map((t) => t.threadId).toList(), ['draft-b', 'draft-a']);
    });

    test('an orphan thread key missing from the index still loads', () async {
      await store.save([_thread('draft-indexed')]);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '${PrefsTaskThreadStore.threadKeyPrefix}draft-orphan',
        jsonEncode(_thread('draft-orphan')),
      );

      final loaded = await newStore().load();

      expect(loaded.map((t) => t.threadId).toSet(), {
        'draft-indexed',
        'draft-orphan',
      });
    });

    test('a corrupt value loses only that session and is backed up', () async {
      await store.save([_thread('draft-good'), _thread('draft-bad')]);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '${PrefsTaskThreadStore.threadKeyPrefix}draft-bad',
        'not json at all',
      );

      final loaded = await newStore().load();

      expect(loaded.map((t) => t.threadId).toList(), ['draft-good']);
      expect(skippedThreadIds, ['draft-bad']);
      expect(
        prefs.getString('${PrefsTaskThreadStore.threadKeyPrefix}draft-bad'),
        isNull,
      );
      final backupKeys = prefs
          .getKeys()
          .where((k) => k.startsWith(PrefsTaskThreadStore.invalidKeyPrefix))
          .toList();
      expect(backupKeys, hasLength(1));
      expect(prefs.getString(backupKeys.single), 'not json at all');
    });

    test('save removes keys for threads no longer present', () async {
      await store.save([_thread('draft-keep'), _thread('draft-drop')]);
      await store.save([_thread('draft-keep')]);

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('${PrefsTaskThreadStore.threadKeyPrefix}draft-drop'),
        isNull,
      );
      final index =
          jsonDecode(prefs.getString(PrefsTaskThreadStore.indexKey)!)
              as Map<String, dynamic>;
      expect(index['threadIds'], ['draft-keep']);
    });

    test('a save before any load never deletes unknown keys', () async {
      // 回归:启动早期用「仅含新 draft 的部分快照」保存,绝不能把
      // 尚未 load 过的历史会话键当作已删除清掉(iOS 重启丢会话根因)。
      await store.save([_thread('draft-history')]);

      await newStore().save([_thread('draft-fresh')]);

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(
          '${PrefsTaskThreadStore.threadKeyPrefix}draft-history',
        ),
        isNotNull,
      );
      final reunited = await newStore().load();
      expect(reunited.map((t) => t.threadId).toSet(), {
        'draft-history',
        'draft-fresh',
      });
    });

    test('a fresh store instance prunes stale keys after loading', () async {
      await store.save([_thread('draft-old')]);

      final second = newStore();
      await second.load();
      await second.save([_thread('draft-new')]);

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('${PrefsTaskThreadStore.threadKeyPrefix}draft-old'),
        isNull,
      );
      expect(
        prefs.getString('${PrefsTaskThreadStore.threadKeyPrefix}draft-new'),
        isNotNull,
      );
    });

    test('an emptied list stays empty across store instances', () async {
      await store.save([_thread('draft-a')]);
      await store.save(const <TaskThread>[]);

      final loaded = await newStore().load();

      expect(loaded, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs
            .getKeys()
            .where((k) => k.startsWith(PrefsTaskThreadStore.threadKeyPrefix)),
        isEmpty,
      );
    });

    test('clear removes every task key including invalid backups', () async {
      await store.save([_thread('draft-a')]);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '${PrefsTaskThreadStore.invalidKeyPrefix}draft-x-1',
        'junk',
      );

      await store.clear();

      expect(
        prefs.getKeys().where((k) => k.startsWith('xworkmate.tasks.')),
        isEmpty,
      );
      expect(await newStore().load(), isEmpty);
    });

    test('save stamps the storage schema version', () async {
      await store.save([_thread('draft-a')]);

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getInt(PrefsTaskThreadStore.schemaVersionKey),
        PrefsTaskThreadStore.schemaVersion,
      );
    });
  });

  group('FileTaskThreadStore', () {
    late Directory tempRoot;
    late List<String> skippedThreadIds;
    late FileTaskThreadStore store;

    FileTaskThreadStore newStore() => FileTaskThreadStore(
      layoutResolver: StoreLayoutResolver(
        supportRootPathResolver: () async => tempRoot.path,
      ),
      onSkippedRecord: (threadId, error) => skippedThreadIds.add(threadId),
    );

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp('task-store-test-');
      skippedThreadIds = <String>[];
      store = newStore();
    });

    tearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    test('round-trips a saved thread list', () async {
      await store.save([_thread('draft-a'), _thread('draft-b')]);

      final loaded = await newStore().load();

      expect(loaded.map((t) => t.threadId).toList(), ['draft-a', 'draft-b']);
    });

    test('clear removes payload files and the index', () async {
      await store.save([_thread('draft-a')]);

      await store.clear();

      expect(await newStore().load(), isEmpty);
      expect(
        File('${tempRoot.path}/tasks/index.json').existsSync(),
        isFalse,
      );
    });

    test('a save before any load never deletes unknown files', () async {
      await store.save([_thread('draft-history')]);

      await newStore().save([_thread('draft-fresh')]);

      final reunited = await newStore().load();
      expect(reunited.map((t) => t.threadId).toSet(), {
        'draft-history',
        'draft-fresh',
      });
    });
  });

  group('TaskThreadStoreRegistry', () {
    test('resolves the first provider supporting the platform', () {
      final registry = TaskThreadStoreRegistry(
        providers: [
          _FakeProvider('unsupported', supported: false),
          _FakeProvider('first-supported', supported: true),
          _FakeProvider('also-supported', supported: true),
        ],
      );

      expect(registry.resolveForPlatform().id, 'first-supported');
    });

    test('default registry resolves the file store on desktop hosts', () {
      final registry = TaskThreadStoreRegistry();

      expect(
        registry.resolveForPlatform().id,
        FileTaskThreadStoreProvider.providerId,
      );
    });

    test('throws a clear error when no provider supports the platform', () {
      final registry = TaskThreadStoreRegistry(
        providers: [_FakeProvider('unsupported', supported: false)],
      );

      expect(registry.resolveForPlatform, throwsStateError);
    });
  });
}
