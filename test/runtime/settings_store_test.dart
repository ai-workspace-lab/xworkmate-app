import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/file_store_support.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/settings_store.dart';

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

  Future<File> writeThreadsFile(Object payload) async {
    final file = File('${tempRoot.path}/tasks/threads.json');
    await file.parent.create(recursive: true);
    await file.writeAsString(payload is String ? payload : jsonEncode(payload));
    return file;
  }

  group('loadTaskThreads per-record recovery', () {
    test(
      'keeps valid threads when one record uses the removed auto mode',
      () async {
        final legacyAuto = _deepCopy(_validThreadJson('draft-legacy-auto'));
        (legacyAuto['executionBinding'] as Map)['executionMode'] = 'auto';
        await writeThreadsFile([
          _validThreadJson('draft-valid-1'),
          legacyAuto,
          _validThreadJson('draft-valid-2'),
        ]);

        final loaded = await store.loadTaskThreads();

        expect(loaded.map((thread) => thread.threadId), [
          'draft-valid-1',
          'draft-valid-2',
        ]);
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
        await writeThreadsFile([incomplete, _validThreadJson('draft-valid-1')]);

        final loaded = await store.loadTaskThreads();

        expect(loaded.map((thread) => thread.threadId), ['draft-valid-1']);
        final skipped = store.lastSkippedInvalidTaskThreadRecords.single;
        expect(skipped.threadId, 'draft-incomplete');
        expect(
          skipped.reason,
          SkippedTaskThreadReason.incompleteWorkspaceBinding,
        );
      },
    );

    test('records non-map entries as invalid persisted data', () async {
      await writeThreadsFile([_validThreadJson('draft-valid-1'), 42]);

      final loaded = await store.loadTaskThreads();

      expect(loaded.map((thread) => thread.threadId), ['draft-valid-1']);
      expect(
        store.lastSkippedInvalidTaskThreadRecords.single.reason,
        SkippedTaskThreadReason.invalidPersistedThreadData,
      );
    });

    test('backs up the original file before any partial recovery', () async {
      final legacyAuto = _deepCopy(_validThreadJson('draft-legacy-auto'));
      (legacyAuto['executionBinding'] as Map)['executionMode'] = 'auto';
      await writeThreadsFile([legacyAuto, _validThreadJson('draft-valid-1')]);

      await store.loadTaskThreads();

      final backups = Directory('${tempRoot.path}/tasks')
          .listSync()
          .whereType<File>()
          .where((file) => file.path.contains('.invalid-'))
          .toList();
      expect(backups, hasLength(1));
      final decoded =
          jsonDecode(await backups.single.readAsString()) as List<dynamic>;
      expect(decoded, hasLength(2));
    });

    test('backs up an unparseable file and reports the failure', () async {
      await writeThreadsFile('this is not json');

      final loaded = await store.loadTaskThreads();

      expect(loaded, isEmpty);
      expect(store.tasksWriteFailure, isNotNull);
      final backups = Directory('${tempRoot.path}/tasks')
          .listSync()
          .whereType<File>()
          .where((file) => file.path.contains('.invalid-'))
          .toList();
      expect(backups, hasLength(1));
    });

    test('clears stale skip records on a subsequent clean load', () async {
      final legacyAuto = _deepCopy(_validThreadJson('draft-legacy-auto'));
      (legacyAuto['executionBinding'] as Map)['executionMode'] = 'auto';
      final file = await writeThreadsFile([legacyAuto]);
      await store.loadTaskThreads();
      expect(store.lastSkippedInvalidTaskThreadRecords, isNotEmpty);

      await file.writeAsString(jsonEncode([_validThreadJson('draft-valid-1')]));
      final loaded = await store.loadTaskThreads();

      expect(loaded, hasLength(1));
      expect(store.lastSkippedInvalidTaskThreadRecords, isEmpty);
    });

    test('round-trips a saved thread list unchanged', () async {
      final layoutProbe = await store.loadTaskThreads();
      expect(layoutProbe, isEmpty);
      final thread = TaskThread(
        threadId: 'draft-roundtrip',
        title: 'roundtrip',
        workspaceBinding: const WorkspaceBinding(
          workspaceId: 'draft-roundtrip',
          workspaceKind: WorkspaceKind.localFs,
          workspacePath: '/tmp/xworkmate-test-ws/draft-roundtrip',
          displayPath: '/tmp/xworkmate-test-ws/draft-roundtrip',
          writable: true,
        ),
      );

      await store.saveTaskThreads([thread]);
      final loaded = await store.loadTaskThreads();

      expect(loaded, hasLength(1));
      expect(loaded.single.threadId, 'draft-roundtrip');
      expect(store.lastSkippedInvalidTaskThreadRecords, isEmpty);
    });
  });

  group('per-session thread files', () {
    File threadFile(String threadId) =>
        File('${tempRoot.path}/tasks/${encodeStableFileKey(threadId)}.json');
    File indexFile() => File('${tempRoot.path}/tasks/index.json');
    File legacyFile() => File('${tempRoot.path}/tasks/threads.json');

    TaskThread thread(String threadId) =>
        TaskThread.fromJson(_validThreadJson(threadId));

    test('save writes one file per thread plus an ordered index', () async {
      await store.saveTaskThreads([thread('draft-a'), thread('draft-b')]);

      expect(threadFile('draft-a').existsSync(), isTrue);
      expect(threadFile('draft-b').existsSync(), isTrue);
      expect(legacyFile().existsSync(), isFalse);
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

    test('legacy threads.json migrates to per-session files on load', () async {
      await writeThreadsFile([
        _validThreadJson('draft-legacy-1'),
        _validThreadJson('draft-legacy-2'),
      ]);

      final loaded = await store.loadTaskThreads();

      expect(loaded.map((item) => item.threadId).toList(), [
        'draft-legacy-1',
        'draft-legacy-2',
      ]);
      expect(threadFile('draft-legacy-1').existsSync(), isTrue);
      expect(threadFile('draft-legacy-2').existsSync(), isTrue);
      expect(legacyFile().existsSync(), isFalse);
      final retired = Directory('${tempRoot.path}/tasks')
          .listSync()
          .whereType<File>()
          .where((file) => file.path.contains('.migrated-'))
          .toList();
      expect(retired, hasLength(1));

      final reloaded = await store.loadTaskThreads();
      expect(reloaded.map((item) => item.threadId).toList(), [
        'draft-legacy-1',
        'draft-legacy-2',
      ]);
    });

    test('migration sweeps per-session files absent from legacy', () async {
      await store.saveTaskThreads([thread('draft-stale')]);
      await writeThreadsFile([_validThreadJson('draft-fresh')]);

      final loaded = await store.loadTaskThreads();

      expect(loaded.map((item) => item.threadId).toList(), ['draft-fresh']);
      expect(threadFile('draft-stale').existsSync(), isFalse);
      expect(threadFile('draft-fresh').existsSync(), isTrue);
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
}
