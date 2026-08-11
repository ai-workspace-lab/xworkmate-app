import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/session_sync_contract.dart';
import 'package:xworkmate/runtime/task_session_api_client.dart';
import 'package:xworkmate/runtime/task_session_binding.dart';
import 'package:xworkmate/runtime/task_session_sync_service.dart';

void main() {
  test(
    'create binds the local TaskThread key to the server identity',
    () async {
      final gateway = _FakeTaskSessionGateway()
        ..createdSnapshot = _snapshot(
          sessionId: 'cloud-session-1',
          namespaceId: 'namespace-1',
          snapshotVersion: 2,
          lastEventSeq: 4,
        );
      final store = MemoryTaskSessionBindingStore();
      final service = TaskSessionSyncService(gateway: gateway, store: store);

      final binding = await service.createBinding(
        taskThreadKey: 'draft-1',
        namespaceId: 'namespace-1',
        title: 'Shared task',
      );

      expect(binding.cloudSessionId, 'cloud-session-1');
      expect(binding.lastEventSeq, 4);
      expect(await store.load('draft-1'), binding);
    },
  );

  test('loads a snapshot then replays ordered server events', () async {
    final gateway = _FakeTaskSessionGateway()
      ..snapshots.add(_snapshot(snapshotVersion: 3, lastEventSeq: 2))
      ..eventPages.add(<SessionEvent>[
        _event(3, 'message.created'),
        _event(4, 'run.queued'),
      ])
      ..eventPages.add(<SessionEvent>[]);
    final store = MemoryTaskSessionBindingStore();
    await store.save(_binding(lastEventSeq: 1, snapshotVersion: 1));
    final service = TaskSessionSyncService(gateway: gateway, store: store);

    final result = await service.synchronize('local-thread-1', pageLimit: 2);

    expect(result.snapshot.snapshotVersion, 3);
    expect(result.events.map((event) => event.seq), <int>[3, 4]);
    expect(gateway.eventRequests, <({int afterSeq, int limit})>[
      (afterSeq: 2, limit: 2),
      (afterSeq: 4, limit: 2),
    ]);
    expect((await store.load('local-thread-1'))?.lastEventSeq, 4);
    expect((await store.load('local-thread-1'))?.snapshotVersion, 3);
  });

  test('a replay gap reloads snapshot and resumes from server truth', () async {
    final gateway = _FakeTaskSessionGateway()
      ..snapshots.addAll(<CloudSessionSnapshot>[
        _snapshot(snapshotVersion: 3, lastEventSeq: 2),
        _snapshot(snapshotVersion: 4, lastEventSeq: 3),
      ])
      ..eventPages.add(<SessionEvent>[_event(4, 'run.running')])
      ..eventPages.add(<SessionEvent>[_event(4, 'run.running')])
      ..eventPages.add(<SessionEvent>[]);
    final store = MemoryTaskSessionBindingStore();
    await store.save(_binding(lastEventSeq: 2, snapshotVersion: 2));
    final service = TaskSessionSyncService(gateway: gateway, store: store);

    final result = await service.synchronize('local-thread-1', pageLimit: 1);

    expect(gateway.snapshotLoadCount, 2);
    expect(result.snapshot.snapshotVersion, 4);
    expect(result.events.map((event) => event.seq), <int>[4]);
    expect((await store.load('local-thread-1'))?.lastEventSeq, 4);
  });

  test('namespace mismatch cannot overwrite the local binding', () async {
    final gateway = _FakeTaskSessionGateway()
      ..snapshots.add(
        _snapshot(namespaceId: 'namespace-other', lastEventSeq: 5),
      );
    final store = MemoryTaskSessionBindingStore();
    final original = _binding(lastEventSeq: 2, snapshotVersion: 2);
    await store.save(original);
    final service = TaskSessionSyncService(gateway: gateway, store: store);

    await expectLater(
      service.synchronize('local-thread-1'),
      throwsA(isA<TaskSessionBindingMismatch>()),
    );
    expect(await store.load('local-thread-1'), original);
  });
}

TaskSessionBinding _binding({int lastEventSeq = 0, int snapshotVersion = 0}) =>
    TaskSessionBinding(
      taskThreadKey: 'local-thread-1',
      cloudSessionId: 'cloud-session-1',
      namespaceId: 'namespace-1',
      lastEventSeq: lastEventSeq,
      snapshotVersion: snapshotVersion,
    );

CloudSessionSnapshot _snapshot({
  String sessionId = 'cloud-session-1',
  String namespaceId = 'namespace-1',
  int snapshotVersion = 1,
  int lastEventSeq = 0,
}) => CloudSessionSnapshot(
  sessionId: sessionId,
  namespaceId: namespaceId,
  title: 'Shared task',
  snapshotVersion: snapshotVersion,
  lastEventSeq: lastEventSeq,
  lifecycleState: 'ready',
  context: const <String, dynamic>{},
);

SessionEvent _event(int seq, String type) => SessionEvent(
  seq: seq,
  type: type,
  payload: const <String, dynamic>{},
  createdAt: DateTime.utc(2026, 8, 11),
);

class _FakeTaskSessionGateway implements TaskSessionGateway {
  CloudSessionSnapshot? createdSnapshot;
  final List<CloudSessionSnapshot> snapshots = <CloudSessionSnapshot>[];
  final List<List<SessionEvent>> eventPages = <List<SessionEvent>>[];
  final List<({int afterSeq, int limit})> eventRequests =
      <({int afterSeq, int limit})>[];
  int snapshotLoadCount = 0;

  @override
  Future<CloudSessionSnapshot> createSession({
    required String namespaceId,
    required String title,
  }) async => createdSnapshot!;

  @override
  Future<List<SessionEvent>> loadEvents(
    String sessionId, {
    required int afterSeq,
    required int limit,
  }) async {
    eventRequests.add((afterSeq: afterSeq, limit: limit));
    return eventPages.removeAt(0);
  }

  @override
  Future<CloudSessionSnapshot> loadSnapshot(String sessionId) async {
    snapshotLoadCount += 1;
    return snapshots.removeAt(0);
  }

  @override
  Future<TaskSessionMessageReceipt> sendMessage({
    required String sessionId,
    required String clientRequestId,
    required String text,
    TaskSessionRunRequest? run,
  }) => throw UnimplementedError();
}
