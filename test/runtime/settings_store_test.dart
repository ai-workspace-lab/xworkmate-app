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
    test('keeps valid threads when one record uses the removed auto mode',
        () async {
      final legacyAuto = _deepCopy(_validThreadJson('draft-legacy-auto'));
      (legacyAuto['executionBinding'] as Map)['executionMode'] = 'auto';
      await writeThreadsFile([
        _validThreadJson('draft-valid-1'),
        legacyAuto,
        _validThreadJson('draft-valid-2'),
      ]);

      final loaded = await store.loadTaskThreads();

      expect(
        loaded.map((thread) => thread.threadId),
        ['draft-valid-1', 'draft-valid-2'],
      );
      expect(store.lastSkippedInvalidTaskThreadRecords, hasLength(1));
      final skipped = store.lastSkippedInvalidTaskThreadRecords.single;
      expect(skipped.threadId, 'draft-legacy-auto');
      expect(skipped.reason, SkippedTaskThreadReason.removedAutoExecutionMode);
    });

    test('keeps valid threads when one record has an incomplete binding',
        () async {
      final incomplete = _deepCopy(_validThreadJson('draft-incomplete'));
      (incomplete['workspaceBinding'] as Map)['workspacePath'] = '';
      await writeThreadsFile([
        incomplete,
        _validThreadJson('draft-valid-1'),
      ]);

      final loaded = await store.loadTaskThreads();

      expect(loaded.map((thread) => thread.threadId), ['draft-valid-1']);
      final skipped = store.lastSkippedInvalidTaskThreadRecords.single;
      expect(skipped.threadId, 'draft-incomplete');
      expect(
        skipped.reason,
        SkippedTaskThreadReason.incompleteWorkspaceBinding,
      );
    });

    test('records non-map entries as invalid persisted data', () async {
      await writeThreadsFile([
        _validThreadJson('draft-valid-1'),
        42,
      ]);

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
}
