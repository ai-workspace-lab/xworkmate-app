import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/file_store_support.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/settings_store.dart';
import 'package:xworkmate/runtime/task_thread_store.dart';

Map<String, dynamic> _validThreadJson(String threadId) {
  return TaskThread(
    threadId: threadId,
    title: 'valid $threadId',
    workspaceBinding: WorkspaceBinding(
      workspaceId: threadId,
      workspaceKind: WorkspaceKind.localFs,
      workspacePath: '/tmp/xworkmate-test-ws/$threadId',
      displayPath: '/tmp/xworkmate-test-ws/$threadId',
      writable: true,
    ),
  ).toJson();
}

Map<String, dynamic> _deepCopy(Map<String, dynamic> value) {
  return (jsonDecode(jsonEncode(value)) as Map).cast<String, dynamic>();
}

class _ThrowingTaskThreadStore implements TaskThreadStore {
  bool failing = true;

  @override
  Future<List<TaskThread>> load() async => const <TaskThread>[];

  @override
  Future<void> save(List<TaskThread> threads) async {
    if (failing) {
      throw const FileSystemException('save failed');
    }
  }

  @override
  Future<void> clear() async {}
}

void main() {
  late Directory tempRoot;
  late SettingsStore store;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('settings-store-test-');
    store = SettingsStore(
      StoreLayoutResolver(supportRootPathResolver: () async => tempRoot.path),
    );
  });

  tearDown(() async {
    store.dispose();
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  File threadFile(String threadId) =>
      File('${tempRoot.path}/tasks/${encodeStableFileKey(threadId)}.json');
  File indexFile() => File('${tempRoot.path}/tasks/index.json');

  TaskThread thread(String threadId) =>
      TaskThread.fromJson(_validThreadJson(threadId));

  Future<void> writeThreadPayload(String threadId, Object payload) async {
    final file = threadFile(threadId);
    await file.parent.create(recursive: true);
    await file.writeAsString(payload is String ? payload : jsonEncode(payload));
  }

  group('loadTaskThreads per-record recovery', () {
    test(
      'keeps valid threads when one record uses the removed auto mode',
      () async {
        final legacyAuto = _deepCopy(_validThreadJson('draft-legacy-auto'));
        (legacyAuto['executionBinding'] as Map)['executionMode'] = 'auto';
        await writeThreadPayload('draft-valid-1', _validThreadJson('draft-valid-1'));
        await writeThreadPayload('draft-legacy-auto', legacyAuto);

        final loaded = await store.loadTaskThreads();

        expect(loaded.map((item) => item.threadId).toList(), ['draft-valid-1']);
        expect(store.lastSkippedInvalidTaskThreadRecords, hasLength(1));
        final skipped = store.lastSkippedInvalidTaskThreadRecords.single;
        expect(skipped.threadId, 'draft-legacy-auto');
        expect(
          skipped.reason,
          SkippedTaskThreadReason.removedAutoExecutionMode,
        );
      },
    );

    test(
      'keeps valid threads when one record has an incomplete binding',
      () async {
        final incomplete = _deepCopy(_validThreadJson('draft-incomplete'));
        (incomplete['workspaceBinding'] as Map)['workspacePath'] = '';
        await writeThreadPayload('draft-incomplete', incomplete);
        await writeThreadPayload('draft-valid-1', _validThreadJson('draft-valid-1'));

        final loaded = await store.loadTaskThreads();

        expect(loaded.map((item) => item.threadId).toList(), ['draft-valid-1']);
        final skipped = store.lastSkippedInvalidTaskThreadRecords.single;
        expect(skipped.threadId, 'draft-incomplete');
        expect(
          skipped.reason,
          SkippedTaskThreadReason.incompleteWorkspaceBinding,
        );
      },
    );

    test('records undecodable payloads as invalid persisted data', () async {
      await writeThreadPayload('draft-valid-1', _validThreadJson('draft-valid-1'));
      await writeThreadPayload('draft-broken', 'not json at all');

      final loaded = await store.loadTaskThreads();

      expect(loaded.map((item) => item.threadId).toList(), ['draft-valid-1']);
      expect(
        store.lastSkippedInvalidTaskThreadRecords.single.reason,
        SkippedTaskThreadReason.invalidPersistedThreadData,
      );
    });

    test('clears stale skip records on a subsequent clean load', () async {
      await writeThreadPayload('draft-broken', 'not json at all');
      await store.loadTaskThreads();
      expect(store.lastSkippedInvalidTaskThreadRecords, isNotEmpty);

      await store.saveTaskThreads([thread('draft-valid-1')]);
      final loaded = await store.loadTaskThreads();

      expect(loaded, hasLength(1));
      expect(store.lastSkippedInvalidTaskThreadRecords, isEmpty);
    });

    test('round-trips a saved thread list unchanged', () async {
      final layoutProbe = await store.loadTaskThreads();
      expect(layoutProbe, isEmpty);

      await store.saveTaskThreads([thread('draft-roundtrip')]);
      final loaded = await store.loadTaskThreads();

      expect(loaded, hasLength(1));
      expect(loaded.single.threadId, 'draft-roundtrip');
      expect(store.lastSkippedInvalidTaskThreadRecords, isEmpty);
    });
  });

  group('per-session thread files', () {
    test('save writes one file per thread plus an ordered index', () async {
      await store.saveTaskThreads([thread('draft-a'), thread('draft-b')]);

      expect(threadFile('draft-a').existsSync(), isTrue);
      expect(threadFile('draft-b').existsSync(), isTrue);
      final index =
          jsonDecode(await indexFile().readAsString()) as Map<String, dynamic>;
      expect(index['threadIds'], ['draft-a', 'draft-b']);
    });

    test('load returns threads in index order', () async {
      await store.saveTaskThreads([thread('draft-a'), thread('draft-b')]);
      await store.saveTaskThreads([thread('draft-b'), thread('draft-a')]);

      final loaded = await store.loadTaskThreads();

      expect(loaded.map((item) => item.threadId).toList(), [
        'draft-b',
        'draft-a',
      ]);
    });

    test('a corrupt per-session file loses only that session', () async {
      await store.saveTaskThreads([thread('draft-good'), thread('draft-bad')]);
      await threadFile('draft-bad').writeAsString('not json at all');

      final loaded = await store.loadTaskThreads();

      expect(loaded.map((item) => item.threadId).toList(), ['draft-good']);
      expect(store.lastSkippedInvalidTaskThreadRecords, hasLength(1));
      final backups = Directory('${tempRoot.path}/tasks')
          .listSync()
          .whereType<File>()
          .where((file) => file.path.contains('.invalid-'))
          .toList();
      expect(backups, hasLength(1));
    });

    test('an orphan thread file missing from the index still loads', () async {
      await store.saveTaskThreads([thread('draft-indexed')]);
      final orphan = thread('draft-orphan');
      await threadFile('draft-orphan').writeAsString(jsonEncode(orphan));

      final loaded = await store.loadTaskThreads();

      expect(loaded.map((item) => item.threadId).toSet(), {
        'draft-indexed',
        'draft-orphan',
      });
    });

    test('save removes files for threads no longer present', () async {
      await store.saveTaskThreads([thread('draft-keep'), thread('draft-drop')]);
      await store.saveTaskThreads([thread('draft-keep')]);

      expect(threadFile('draft-keep').existsSync(), isTrue);
      expect(threadFile('draft-drop').existsSync(), isFalse);
      final index =
          jsonDecode(await indexFile().readAsString()) as Map<String, dynamic>;
      expect(index['threadIds'], ['draft-keep']);
    });

    test('a fresh store instance prunes stale files on save', () async {
      await store.saveTaskThreads([thread('draft-old')]);
      final secondStore = SettingsStore(
        StoreLayoutResolver(supportRootPathResolver: () async => tempRoot.path),
      );
      addTearDown(secondStore.dispose);

      await secondStore.saveTaskThreads([thread('draft-new')]);

      expect(threadFile('draft-new').existsSync(), isTrue);
      expect(threadFile('draft-old').existsSync(), isFalse);
    });

    test('clearAssistantLocalState removes thread files and index', () async {
      await store.saveTaskThreads([thread('draft-a')]);

      await store.clearAssistantLocalState();

      expect(threadFile('draft-a').existsSync(), isFalse);
      expect(indexFile().existsSync(), isFalse);
      final loaded = await store.loadTaskThreads();
      expect(loaded, isEmpty);
    });
  });

  group('task thread store delegation', () {
    test('wraps store save failures and clears them on success', () async {
      final failingStore = _ThrowingTaskThreadStore();
      final settingsStore = SettingsStore(
        StoreLayoutResolver(supportRootPathResolver: () async => tempRoot.path),
        taskThreadStore: failingStore,
      );
      addTearDown(settingsStore.dispose);

      await settingsStore.saveTaskThreads([thread('draft-a')]);
      expect(settingsStore.tasksWriteFailure, isNotNull);
      expect(settingsStore.tasksWriteFailure!.operation, 'saveTaskThreads');

      failingStore.failing = false;
      await settingsStore.saveTaskThreads([thread('draft-a')]);
      expect(settingsStore.tasksWriteFailure, isNull);
    });
  });
}
