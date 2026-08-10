import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:xworkmate/runtime/session_sync_contract.dart';

void main() {
  test('decodes a lightweight snapshot without artifact payloads', () {
    final snapshot = CloudSessionSnapshot.fromJson(
      jsonDecode('''
        {
          "sessionId": "session-1",
          "namespaceId": "ns-1",
          "title": "Shared task",
          "lastEventSeq": 3,
          "lifecycleState": "ready",
          "context": {"summary": "continue the deployment"},
          "taskRun": {"id": "run-1", "state": "running", "bridgeTaskRef": "opaque-1"}
        }
      ''')
          as Map<String, dynamic>,
    );

    expect(snapshot.sessionId, 'session-1');
    expect(snapshot.namespaceId, 'ns-1');
    expect(snapshot.context['summary'], 'continue the deployment');
    expect(snapshot.taskRun?.bridgeTaskRef, 'opaque-1');
    expect(snapshot.toJson().containsKey('artifacts'), isFalse);
  });

  test(
    'cursor accepts the next event, ignores duplicates, and detects gaps',
    () {
      final cursor = SessionSyncCursor(lastSeq: 2);

      expect(cursor.accept(SessionEvent(seq: 3, type: 'run.running')), isTrue);
      expect(cursor.lastSeq, 3);
      expect(cursor.accept(SessionEvent(seq: 3, type: 'run.running')), isFalse);
      expect(
        () => cursor.accept(SessionEvent(seq: 5, type: 'run.completed')),
        throwsA(isA<SessionSyncGap>()),
      );
    },
  );

  test('namespace binding is derived from existing workspace identity', () {
    final binding = NamespaceBinding.fromWorkspace(
      workspaceId: 'workspace-1',
      namespaceId: 'ns-1',
    );

    expect(binding.workspaceId, 'workspace-1');
    expect(binding.namespaceId, 'ns-1');
  });

  test('coordinator attaches snapshot and marks a gap for replay', () {
    final coordinator = SessionSyncCoordinator();
    coordinator.attach(
      CloudSessionSnapshot(
        sessionId: 'session-1',
        namespaceId: 'ns-1',
        title: 'Shared task',
        lastEventSeq: 4,
        lifecycleState: 'ready',
        context: const <String, dynamic>{},
      ),
    );

    expect(
      coordinator.accept(SessionEvent(seq: 5, type: 'run.running')),
      isTrue,
    );
    expect(coordinator.needsReplay, isFalse);
    expect(
      coordinator.accept(SessionEvent(seq: 7, type: 'run.completed')),
      isFalse,
    );
    expect(coordinator.needsReplay, isTrue);
    expect(coordinator.replayFromSeq, 6);
  });
}
