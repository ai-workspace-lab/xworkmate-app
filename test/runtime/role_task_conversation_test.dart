// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/i18n/app_language.dart';
import 'package:xworkmate/models/app_models.dart';
import 'package:xworkmate/runtime/task_session_client.dart';

import '../features/bot_team/fake_task_session_client.dart';

/// Accounts plus an orchestrator that settles every run as soon as it is
/// queued, with [terminal] as the final event.
class _SettlingAccounts extends FakeTaskSessionClient {
  _SettlingAccounts({this.terminal = 'run.completed'});

  final String terminal;

  @override
  Future<TaskMessageReceipt> appendMessage({
    required String sessionId,
    required String clientRequestId,
    required String text,
    Map<String, Object?> routing = const <String, Object?>{},
  }) async {
    final receipt = await super.appendMessage(
      sessionId: sessionId,
      clientRequestId: clientRequestId,
      text: text,
      routing: routing,
    );
    final runId = receipt.taskRunId;
    if (terminal == 'run.completed') {
      addEvent(sessionId, 'run.progressed', {
        'taskRunId': runId,
        'phase': 'selected',
        'roleSelection': {
          'role': routing['role'],
          'executor': 'opencode',
          'modelId': 'model-a',
        },
      });
      addEvent(sessionId, 'assistant.message.created', {
        'taskRunId': runId,
        'text': 'the answer',
      });
      addEvent(sessionId, 'run.completed', {'taskRunId': runId});
    } else {
      addEvent(sessionId, 'run.failed', {
        'taskRunId': runId,
        'phase': 'rejected',
        'code': 'ROLE_SELECTION_REJECTED',
        'roleSelection': {'message': 'role not enabled'},
      });
    }
    return receipt;
  }
}

void main() {
  setUp(() => setActiveAppLanguage(AppLanguage.zh));

  AppController controllerFor(String key) {
    final controller = AppController(environmentOverride: const {});
    controller.sessionsControllerInternal.currentSessionKeyInternal = key;
    return controller;
  }

  test(
    'Run now puts the request and the DS Bot answer in the conversation',
    () async {
      final controller = controllerFor('unit-role-now');
      addTearDown(controller.dispose);
      final accounts = _SettlingAccounts();

      await controller.runRoleTaskInConversation(
        sessionKey: 'unit-role-now',
        text: 'split the parser',
        role: AssistantMode.engineer,
        clientFactory: () => accounts,
      );

      expect(accounts.appended.single['routing'], <String, Object?>{
        'roleMode': 'auto',
        'role': 'engineer',
      });
      final messages =
          controller.assistantThreadMessagesInternal['unit-role-now']!;
      expect(messages.map((message) => message.role), ['user', 'assistant']);
      expect(messages.first.text, 'split the parser');
      expect(
        messages.last.text,
        '[Engineer · opencode · model-a]\n\nthe answer',
      );
      expect(messages.last.error, isFalse);
      expect(
        controller.assistantSessionHasPendingRun('unit-role-now'),
        isFalse,
      );
    },
  );

  test('a rejected role comes back as an error in the conversation', () async {
    final controller = controllerFor('unit-role-rejected');
    addTearDown(controller.dispose);

    await controller.runRoleTaskInConversation(
      sessionKey: 'unit-role-rejected',
      text: 'design it',
      role: AssistantMode.architect,
      clientFactory: () => _SettlingAccounts(terminal: 'run.failed'),
    );

    final last =
        controller.assistantThreadMessagesInternal['unit-role-rejected']!.last;
    expect(last.error, isTrue);
    expect(last.text, '[Architect] 被策略拒绝：role not enabled');
  });

  test('handing off creates a Bot team thread and notes it here', () async {
    final controller = controllerFor('unit-role-handoff');
    addTearDown(controller.dispose);
    final accounts = FakeTaskSessionClient();

    final sessionId = await controller.handOffRoleTaskToBotTeam(
      sessionKey: 'unit-role-handoff',
      text: 'nightly dependency audit',
      role: AssistantMode.worker,
      clientFactory: () => accounts,
      newRequestId: () => 'req-1',
    );

    expect(sessionId, accounts.sessions.single.sessionId);
    expect(accounts.appended.single['routing'], <String, Object?>{
      'roleMode': 'auto',
      'role': 'worker',
    });
    expect(accounts.appended.single['clientRequestId'], 'req-1');
    final messages =
        controller.assistantThreadMessagesInternal['unit-role-handoff']!;
    expect(messages.first.text, 'nightly dependency audit');
    expect(messages.last.text, contains('已交给 Bot 团队（Worker）'));
    expect(
      controller.assistantSessionHasPendingRun('unit-role-handoff'),
      isFalse,
    );
  });

  test('without a Bridge and account nothing is sent', () async {
    final controller = controllerFor('unit-role-offline');
    addTearDown(controller.dispose);

    await controller.runRoleTaskInConversation(
      sessionKey: 'unit-role-offline',
      text: 'anything',
      role: AssistantMode.researcher,
      clientFactory: () => null,
    );
    final last =
        controller.assistantThreadMessagesInternal['unit-role-offline']!.last;
    expect(last.error, isTrue);
    expect(last.text, contains('登录账户'));
  });
}
