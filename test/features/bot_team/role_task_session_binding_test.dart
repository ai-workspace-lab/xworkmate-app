import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/features/bot_team/role_task_session_binding.dart';
import 'package:xworkmate/runtime/task_session_binding.dart';
import 'package:xworkmate/runtime/task_session_sync_service.dart';
import 'package:xworkmate/runtime/task_session_client.dart';
import 'package:xworkmate/runtime/session_sync_contract.dart';

import 'fake_task_session_client.dart';

class _SnapshotClient extends FakeTaskSessionClient
    implements TaskSessionSnapshotReader {
  String returnedId = 'saved';
  String returnedNamespace = 'ns-personal';
  TaskSessionException? failure;
  @override
  Future<List<TaskSessionSummary>> listSessions(String namespaceId) async =>
      throw StateError('A capped list is not an identity lookup');
  @override
  Future<CloudSessionSnapshot> loadSnapshot(String sessionId) async {
    if (failure != null) throw failure!;
    return CloudSessionSnapshot(
      sessionId: returnedId,
      namespaceId: returnedNamespace,
      title: 'saved conversation',
      snapshotVersion: 1,
      lastEventSeq: 0,
      lifecycleState: 'active',
      context: const {},
    );
  }
}

void main() {
  for (final mismatch in [
    '',
    'sessionId',
    'namespaceId',
    'missing',
    'unauthorized',
  ]) {
    test('loads binding by canonical snapshot, case=$mismatch', () async {
      final store = MemoryTaskSessionBindingStore();
      final binding = TaskSessionBinding(
        taskThreadKey: 'scoped',
        cloudSessionId: 'saved',
        namespaceId: 'ns-personal',
        lastEventSeq: 0,
        snapshotVersion: 0,
      );
      await store.save(binding);
      final client = _SnapshotClient();
      if (mismatch == 'sessionId') client.returnedId = 'foreign';
      if (mismatch == 'namespaceId') client.returnedNamespace = 'foreign';
      if (mismatch == 'missing' || mismatch == 'unauthorized') {
        client.failure = TaskSessionException(
          statusCode: mismatch == 'missing' ? 404 : 401,
          code: 'fixture',
          message: 'fixture failure',
        );
      }
      final loaded = loadRoleTaskSession(
        store: store,
        client: client,
        bindingKey: 'scoped',
      );
      if (mismatch.isEmpty) {
        expect((await loaded)!.sessionId, 'saved');
      } else {
        await expectLater(
          loaded,
          throwsA(
            mismatch == 'unauthorized'
                ? isA<TaskSessionException>()
                : isA<TaskSessionBindingMismatch>(),
          ),
        );
      }
      expect(await store.load('scoped'), binding);
      expect(client.appended, isEmpty);
    });
  }
  test(
    'scope isolates source, origin, base path and thread, not ACP suffix',
    () {
      String key(
        String url, {
        String source = 'bridge',
        String thread = 'local',
      }) => roleTaskBindingKey(
        threadKey: thread,
        source: source,
        endpoint: Uri.parse(url),
      );
      final base = key('https://bridge.example.com/team');
      expect(key('https://bridge.example.com/team/acp/rpc'), base);
      expect(key('https://bridge.example.com/team/acp'), base);
      expect(
        key('https://bridge.example.com/team', source: 'cloud'),
        isNot(base),
      );
      expect(key('https://other.example.com/team'), isNot(base));
      expect(key('https://bridge.example.com/other'), isNot(base));
      expect(key('https://bridge.example.com:8443/team'), isNot(base));
      expect(
        key('https://bridge.example.com/team', thread: 'another'),
        isNot(base),
      );
      expect(base, isNot(contains('example.com')));
    },
  );

  for (final namespace in ['wrong-namespace', 'ns-personal']) {
    test(
      'rejects a binding with mismatched namespace or missing session: $namespace',
      () async {
        final store = MemoryTaskSessionBindingStore();
        await store.save(
          TaskSessionBinding(
            taskThreadKey: 'scoped',
            cloudSessionId: 'missing',
            namespaceId: namespace,
            lastEventSeq: 0,
            snapshotVersion: 0,
          ),
        );
        final client = FakeTaskSessionClient();
        await expectLater(
          loadRoleTaskSession(
            store: store,
            client: client,
            bindingKey: 'scoped',
          ),
          throwsA(isA<TaskSessionBindingMismatch>()),
        );
        expect(client.sessions, isEmpty);
        expect(client.appended, isEmpty);
        expect((await store.load('scoped'))!.cloudSessionId, 'missing');
      },
    );
  }
}
