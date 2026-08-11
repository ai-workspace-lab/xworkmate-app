import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/file_store_support.dart';
import 'package:xworkmate/runtime/task_session_binding.dart';

void main() {
  group('TaskSessionBinding', () {
    test('round-trips only the local-to-cloud identity and cursors', () {
      final binding = TaskSessionBinding(
        taskThreadKey: 'local-thread-1',
        cloudSessionId: 'cloud-session-1',
        namespaceId: 'namespace-1',
        lastEventSeq: 9,
        snapshotVersion: 4,
      );

      final json = binding.toJson();
      final decoded = TaskSessionBinding.fromJson(json);

      expect(decoded, binding);
      expect(json.keys, <String>{
        'taskThreadKey',
        'cloudSessionId',
        'namespaceId',
        'lastEventSeq',
        'snapshotVersion',
      });
      expect(json.containsKey('token'), isFalse);
      expect(json.containsKey('artifacts'), isFalse);
    });

    test('rejects incomplete identity and negative cursors', () {
      expect(
        () => TaskSessionBinding(
          taskThreadKey: '',
          cloudSessionId: 'cloud-session-1',
          namespaceId: 'namespace-1',
          lastEventSeq: 0,
          snapshotVersion: 0,
        ),
        throwsArgumentError,
      );
      expect(
        () => TaskSessionBinding(
          taskThreadKey: 'local-thread-1',
          cloudSessionId: 'cloud-session-1',
          namespaceId: 'namespace-1',
          lastEventSeq: -1,
          snapshotVersion: 0,
        ),
        throwsArgumentError,
      );
    });
  });

  test(
    'file binding store persists one mapping per local TaskThread key',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'xworkmate-cloud-session-binding-',
      );
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      final layoutResolver = StoreLayoutResolver(
        appDataRootPathResolver: () async => root.path,
        supportRootPathResolver: () async => root.path,
        secretRootPathResolver: () async => '${root.path}/secrets',
      );
      final store = FileTaskSessionBindingStore(layoutResolver: layoutResolver);
      final binding = TaskSessionBinding(
        taskThreadKey: 'draft/local 1',
        cloudSessionId: 'cloud-session-1',
        namespaceId: 'namespace-1',
        lastEventSeq: 3,
        snapshotVersion: 2,
      );

      await store.save(binding);
      final loaded = await store.load('draft/local 1');

      expect(loaded, binding);
      expect(
        File(
          '${root.path}/tasks/session-bindings/'
          '${encodeStableFileKey('draft/local 1')}.json',
        ).existsSync(),
        isTrue,
      );

      await store.remove('draft/local 1');
      expect(await store.load('draft/local 1'), isNull);
    },
  );
}
