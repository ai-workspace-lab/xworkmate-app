import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/features/bot_team/bot_team_models.dart';
import 'package:xworkmate/features/bot_team/role_task_runner.dart';
import 'package:xworkmate/runtime/task_session_client.dart';

import 'fake_task_session_client.dart';

void main() {
  test(
    'reused session with more than one page of history polls the new run',
    () async {
      final client = FakeTaskSessionClient();
      final session = await client.createSession(
        namespaceId: 'ns-personal',
        title: 'old',
      );
      for (var i = 0; i < 150; i++) {
        client.addEvent(session.sessionId, 'run.completed', {
          'taskRunId': 'old-$i',
        });
      }
      final view = await RoleTaskRunner(
        client: client,
        timeout: Duration.zero,
      ).run(text: 'new turn', role: 'worker', existingSession: session);
      expect(view.runId, 'run-1');
      expect(view.phase, BotTaskPhase.queued);
      expect(client.sessions, hasLength(1));
    },
  );
  test('reuses a session and awaits persistence before append', () async {
    final client = FakeTaskSessionClient();
    const session = TaskSessionSummary(
      sessionId: 'existing',
      title: 'old',
      lastEventSeq: 0,
      updatedAt: null,
      lastRunState: '',
    );
    var persisted = false;
    await RoleTaskRunner(client: client, timeout: Duration.zero).run(
      text: 'next',
      role: 'engineer',
      existingSession: session,
      onSessionReady: (namespace, selected) async {
        expect(client.appended, isEmpty);
        expect(selected.sessionId, 'existing');
        await Future<void>.delayed(Duration.zero);
        persisted = true;
      },
    );
    expect(persisted, isTrue);
    expect(client.sessions, isEmpty);
    expect(client.appended.single['sessionId'], 'existing');
  });

  test('persistence failure prevents append', () async {
    final client = FakeTaskSessionClient();
    await expectLater(
      RoleTaskRunner(client: client).run(
        text: 'first',
        role: 'worker',
        onSessionReady: (_, _) async => throw StateError('write failed'),
      ),
      throwsStateError,
    );
    expect(client.appended, isEmpty);
  });
  test('runs a role task to its end and returns the answer', () async {
    final accounts = FakeTaskSessionClient();
    final seen = <BotTaskPhase>[];
    final view =
        await RoleTaskRunner(
          client: accounts,
          pollInterval: Duration.zero,
          newRequestId: () => 'req-1',
        ).run(
          text: 'refactor the parser',
          role: 'engineer',
          onProgress: (progress) {
            seen.add(progress.phase);
            if (seen.length == 1) {
              // The orchestrator claims, selects and finishes the run.
              final session = accounts.sessions.single.sessionId;
              accounts.addEvent(session, 'run.progressed', {
                'taskRunId': 'run-1',
                'phase': 'selected',
                'roleSelection': {
                  'role': 'engineer',
                  'executor': 'opencode',
                  'modelId': 'model-a',
                },
              });
              accounts.addEvent(session, 'assistant.message.created', {
                'taskRunId': 'run-1',
                'text': 'done: parser split',
              });
              accounts.addEvent(session, 'run.completed', {
                'taskRunId': 'run-1',
              });
            }
          },
        );

    expect(accounts.sessions.single.title, 'refactor the parser');
    expect(accounts.appended.single['routing'], <String, Object?>{
      'roleMode': 'auto',
      'role': 'engineer',
    });
    expect(accounts.appended.single['clientRequestId'], 'req-1');
    expect(seen.first, BotTaskPhase.queued);
    expect(view.phase, BotTaskPhase.completed);
    expect(view.answer, 'done: parser split');
    expect(view.executor, 'opencode');
    expect(view.modelId, 'model-a');
  });

  test('a run still going at the timeout comes back unfinished', () async {
    final accounts = FakeTaskSessionClient();
    final view = await RoleTaskRunner(
      client: accounts,
      pollInterval: Duration.zero,
      timeout: Duration.zero,
    ).run(text: 'long job', role: 'researcher');
    expect(view.active, isTrue);
    expect(view.phase, BotTaskPhase.queued);
  });

  test('routing and titles are shared with the Bot team page', () {
    expect(botRoleRouting(), <String, Object?>{'roleMode': 'auto'});
    expect(botRoleRouting(role: ' worker ', workspace: ' repo '), {
      'roleMode': 'auto',
      'role': 'worker',
      'workspace': 'repo',
    });
    expect(botTaskTitle('x' * 41), '${'x' * 40}…');
  });
}
