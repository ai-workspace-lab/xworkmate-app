import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/features/bot_team/bot_team_models.dart';
import 'package:xworkmate/runtime/task_session_client.dart';

TaskSessionEvent event(int seq, String type, Map<String, dynamic> payload) =>
    TaskSessionEvent(seq: seq, type: type, payload: payload, createdAt: null);

void main() {
  test('a completed run carries the prompt, the selection and the answer', () {
    final tasks = foldBotTasks(<TaskSessionEvent>[
      event(4, 'run.progressed', {'taskRunId': 'r1', 'phase': 'selected', 'roleSelection': {'role': 'engineer', 'executor': 'opencode', 'modelId': 'm-1'}}),
      event(1, 'message.created', {'taskRunId': 'r1', 'text': 'fix the test'}),
      event(2, 'run.queued', {'taskRunId': 'r1'}),
      event(3, 'run.running', {'taskRunId': 'r1'}),
      event(5, 'run.progressed', {'taskRunId': 'r1', 'phase': 'memory'}),
      event(6, 'run.progressed', {'taskRunId': 'r1', 'phase': 'started'}),
      event(7, 'assistant.message.created', {'taskRunId': 'r1', 'text': 'Done.'}),
      event(8, 'run.completed', {'taskRunId': 'r1', 'resolvedRole': 'engineer', 'resolvedModelId': 'm-1'}),
    ]);
    final task = tasks.single;
    expect(task.prompt, 'fix the test');
    expect(task.phase, BotTaskPhase.completed);
    expect(task.executor, 'opencode');
    expect(task.modelId, 'm-1');
    expect(task.answer, 'Done.');
    expect(task.memoryUsed, isTrue);
    expect(task.active, isFalse);
  });

  test('a rejection shows the policy reason; a failure shows its code', () {
    final tasks = foldBotTasks(<TaskSessionEvent>[
      event(1, 'message.created', {'taskRunId': 'r1', 'text': 'survey'}),
      event(2, 'run.failed', {'taskRunId': 'r1', 'phase': 'rejected', 'code': 'ROLE_SELECTION_REJECTED', 'roleSelection': {'role': 'researcher', 'code': 'role_not_enabled', 'message': 'role researcher is not enabled in this policy'}}),
      event(3, 'message.created', {'taskRunId': 'r2', 'text': 'build'}),
      event(4, 'run.failed', {'taskRunId': 'r2', 'code': 'EXECUTOR_STOPPED', 'stopReason': 'max-tokens'}),
    ]);
    expect(tasks[0].phase, BotTaskPhase.rejected);
    expect(tasks[0].error, 'role researcher is not enabled in this policy');
    expect(tasks[1].phase, BotTaskPhase.failed);
    expect(tasks[1].error, 'EXECUTOR_STOPPED · max-tokens');
  });

  test('a cancel request is shown until the run settles as cancelled', () {
    final pending = foldBotTasks(<TaskSessionEvent>[
      event(1, 'message.created', {'taskRunId': 'r1', 'text': 'long job'}),
      event(2, 'run.progressed', {'taskRunId': 'r1', 'phase': 'started'}),
      event(3, 'run.cancel_requested', {'taskRunId': 'r1'}),
    ]).single;
    expect(pending.cancelRequested, isTrue);
    expect(pending.active, isTrue);
    final settled = foldBotTasks(<TaskSessionEvent>[
      event(1, 'message.created', {'taskRunId': 'r1', 'text': 'long job'}),
      event(3, 'run.cancel_requested', {'taskRunId': 'r1'}),
      event(4, 'run.cancelled', {'taskRunId': 'r1'}),
    ]).single;
    expect(settled.phase, BotTaskPhase.cancelled);
    expect(settled.active, isFalse);
  });

  test('auto sends no role; every other role sends its name', () {
    expect(BotRole.auto.routingValue, '');
    expect(BotRole.engineer.routingValue, 'engineer');
    expect(BotRole.values.map((role) => role.routingValue).where((v) => v.isNotEmpty).toSet(),
        <String>{'chat', 'worker', 'engineer', 'architect', 'researcher', 'specialist'});
  });
}
