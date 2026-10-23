import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/features/bot_team/role_task_session_binding.dart';
import 'package:xworkmate/runtime/task_session_binding.dart';
import 'package:xworkmate/runtime/task_session_sync_service.dart';

import 'fake_task_session_client.dart';

void main() {
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
