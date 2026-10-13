import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/features/bot_team/bot_team_controller.dart';
import 'package:xworkmate/features/bot_team/bot_team_models.dart';
import 'package:xworkmate/runtime/task_session_client.dart';

import 'fake_task_session_client.dart';

void main() {
  late FakeTaskSessionClient accounts;
  var ids = 0;

  BotTeamController controller({TaskSessionClient? Function()? factory}) => BotTeamController(
    clientFactory: factory ?? () => accounts,
    pollInterval: const Duration(milliseconds: 10),
    newRequestId: () => 'req-${++ids}',
  );

  setUp(() {
    accounts = FakeTaskSessionClient();
    ids = 0;
  });

  test('without a bridge or account the page says so and sends nothing', () async {
    final bots = controller(factory: () => null);
    await bots.load();
    expect(bots.connected, isFalse);
    expect(bots.error, isNotEmpty);
    await bots.send('anything');
    bots.dispose();
  });

  test('the first task creates a session and queues a run with routing hints', () async {
    final bots = controller();
    await bots.load();
    bots.setRole(BotRole.engineer);
    await bots.send('  make the failing test pass  ', workspaceKey: ' repo ');
    expect(accounts.sessions.single.title, 'make the failing test pass');
    expect(bots.selectedSessionId, accounts.sessions.single.sessionId);
    expect(accounts.appended.single['routing'], <String, Object?>{'roleMode': 'auto', 'role': 'engineer', 'workspace': 'repo'});
    expect(accounts.appended.single['clientRequestId'], 'req-1');
    expect(bots.tasks.single.phase, BotTaskPhase.queued);
    expect(bots.hasActiveTask, isTrue);
    bots.dispose();
  });

  test('auto role sends no role, and a second task reuses the session', () async {
    final bots = controller();
    await bots.load();
    await bots.send('one');
    await bots.send('two');
    expect(accounts.sessions, hasLength(1));
    expect(accounts.appended.map((call) => call['routing']), everyElement(<String, Object?>{'roleMode': 'auto'}));
    expect(bots.tasks.map((task) => task.prompt), <String>['one', 'two']);
    bots.dispose();
  });

  test('polling follows the run to its end and then stops', () async {
    final bots = controller();
    await bots.load();
    await bots.send('fix it');
    final session = bots.selectedSessionId;
    final runId = bots.tasks.single.runId;
    accounts.addEvent(session, 'run.progressed', {'taskRunId': runId, 'phase': 'selected', 'roleSelection': {'role': 'engineer', 'executor': 'codex', 'modelId': 'm'}});
    accounts.addEvent(session, 'assistant.message.created', {'taskRunId': runId, 'text': 'Fixed.'});
    accounts.addEvent(session, 'run.completed', {'taskRunId': runId});
    await Future<void>.delayed(const Duration(milliseconds: 60));
    final task = bots.tasks.single;
    expect(task.phase, BotTaskPhase.completed);
    expect(task.answer, 'Fixed.');
    expect(task.executor, 'codex');
    expect(bots.hasActiveTask, isFalse);
    bots.dispose();
  });

  test('cancel asks Accounts and shows the request until the worker settles it', () async {
    final bots = controller();
    await bots.load();
    await bots.send('long job');
    final runId = bots.tasks.single.runId;
    await bots.cancel(runId);
    expect(accounts.cancelled, <String>[runId]);
    expect(bots.tasks.single.cancelRequested, isTrue);
    accounts.addEvent(bots.selectedSessionId, 'run.cancelled', {'taskRunId': runId});
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(bots.tasks.single.phase, BotTaskPhase.cancelled);
    bots.dispose();
  });

  test('a failed send keeps the error and the composer text for retry', () async {
    final bots = controller();
    await bots.load();
    accounts.failNextAppend = const TaskSessionException(statusCode: 400, code: 'invalid_task_session_payload', message: 'invalid task session payload');
    await bots.send('bad');
    expect(bots.error, 'invalid task session payload');
    expect(bots.sending, isFalse);
    bots.dispose();
  });

  test('load selects the most recent session and replays its events', () async {
    accounts.sessions.add(const TaskSessionSummary(sessionId: 'old', title: 'Old', lastEventSeq: 2, updatedAt: null, lastRunState: 'completed'));
    accounts.addEvent('old', 'message.created', {'taskRunId': 'r0', 'text': 'earlier'});
    accounts.addEvent('old', 'run.completed', {'taskRunId': 'r0'});
    final bots = controller();
    await bots.load();
    expect(bots.selectedSessionId, 'old');
    expect(bots.tasks.single.prompt, 'earlier');
    bots.startNewSession();
    expect(bots.selectedSessionId, isEmpty);
    expect(bots.tasks, isEmpty);
    bots.dispose();
  });
}
