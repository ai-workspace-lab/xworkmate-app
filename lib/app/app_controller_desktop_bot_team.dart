import '../features/bot_team/bot_team_models.dart';
import '../features/bot_team/role_task_runner.dart';
import '../i18n/app_language.dart';
import '../models/app_models.dart';
import '../runtime/acp_endpoint_paths.dart';
import '../runtime/runtime_models.dart';
import '../runtime/task_session_client.dart';
import 'app_controller_desktop_core.dart';
import 'app_controller_desktop_runtime_helpers.dart';
import 'app_controller_desktop_thread_sessions.dart';
import 'app_controller_desktop_thread_storage.dart';

/// Bot tasks go to Accounts through the Bridge `/api/v1` proxy with the
/// signed-in account token; the DSH orchestrator runs them (AI Workspace v2.1).
extension AppControllerDesktopBotTeam on AppController {
  /// Null until a Bridge endpoint resolves and an account session exists.
  TaskSessionClient? createTaskSessionClient() {
    final endpoint = resolveBridgeAcpEndpointInternal();
    final token = settingsControllerInternal.accountSessionTokenInternal.trim();
    if (endpoint == null || token.isEmpty) {
      return null;
    }
    final base = endpoint.replace(
      path: AcpEndpointPaths.fromBaseEndpoint(endpoint).basePath,
      query: null,
      fragment: null,
    );
    return HttpTaskSessionClient(bridgeBase: base, accountToken: token);
  }

  /// Runs [text] as a [role] task on DS Bot now and writes the request and
  /// its answer into the [sessionKey] conversation. The conversation shows as
  /// running until the task ends.
  Future<void> runRoleTaskInConversation({
    required String sessionKey,
    required String text,
    required AssistantMode role,
    TaskSessionClient? Function()? clientFactory,
  }) async {
    final key = normalizedAssistantSessionKeyInternal(sessionKey);
    final prompt = text.trim();
    if (prompt.isEmpty || roleTaskPendingSessionKeysInternal.contains(key)) {
      return;
    }
    appendAssistantThreadMessageInternal(key, _message('user', prompt));
    final client = (clientFactory ?? createTaskSessionClient)();
    if (client == null) {
      appendAssistantThreadMessageInternal(key, _signInRequired());
      await flushAssistantThreadPersistenceInternal();
      return;
    }
    roleTaskPendingSessionKeysInternal.add(key);
    notifyIfActiveInternal();
    try {
      final view = await RoleTaskRunner(
        client: client,
      ).run(text: prompt, role: role.name);
      appendAssistantThreadMessageInternal(key, _resultMessage(role, view));
    } catch (failure) {
      appendAssistantThreadMessageInternal(
        key,
        _message('assistant', _describe(failure), error: true),
      );
    } finally {
      roleTaskPendingSessionKeysInternal.remove(key);
      await flushAssistantThreadPersistenceInternal();
      notifyIfActiveInternal();
    }
  }

  /// Hands [text] to the Bot team as a background [role] task thread for
  /// offline, long-running or scheduled work, and notes the hand-off in the
  /// [sessionKey] conversation. Returns the new Bot team session id, or an
  /// empty string when the task could not be handed off.
  Future<String> handOffRoleTaskToBotTeam({
    required String sessionKey,
    required String text,
    required AssistantMode role,
    TaskSessionClient? Function()? clientFactory,
    String Function()? newRequestId,
  }) async {
    final key = normalizedAssistantSessionKeyInternal(sessionKey);
    final prompt = text.trim();
    if (prompt.isEmpty) {
      return '';
    }
    appendAssistantThreadMessageInternal(key, _message('user', prompt));
    final client = (clientFactory ?? createTaskSessionClient)();
    if (client == null) {
      appendAssistantThreadMessageInternal(key, _signInRequired());
      await flushAssistantThreadPersistenceInternal();
      return '';
    }
    try {
      final namespaceId = await client.personalNamespaceId();
      final session = await client.createSession(
        namespaceId: namespaceId,
        title: botTaskTitle(prompt),
      );
      await client.appendMessage(
        sessionId: session.sessionId,
        clientRequestId: (newRequestId ?? nextLocalMessageIdInternal)(),
        text: prompt,
        routing: botRoleRouting(role: role.name),
      );
      appendAssistantThreadMessageInternal(
        key,
        _message(
          'assistant',
          appText(
            '已交给 Bot 团队（${role.label}）在后台执行：「${session.title}」。'
                '进度和结果在 Bot 团队页查看。',
            'Handed to the Bot team (${role.label}) to run in the background: '
                '"${session.title}". Follow it on the Bot team page.',
          ),
        ),
      );
      return session.sessionId;
    } catch (failure) {
      appendAssistantThreadMessageInternal(
        key,
        _message('assistant', _describe(failure), error: true),
      );
      return '';
    } finally {
      await flushAssistantThreadPersistenceInternal();
      notifyIfActiveInternal();
    }
  }

  GatewayChatMessage _resultMessage(AssistantMode role, BotTaskView view) {
    final header = [
      role.label,
      if (view.executor.isNotEmpty) view.executor,
      if (view.modelId.isNotEmpty) view.modelId,
    ].join(' · ');
    return switch (view.phase) {
      BotTaskPhase.completed => _message(
        'assistant',
        view.answer.isEmpty
            ? appText(
                '[$header] 已完成，没有返回文本。',
                '[$header] Done, no text returned.',
              )
            : '[$header]\n\n${view.answer}',
      ),
      BotTaskPhase.failed || BotTaskPhase.rejected => _message(
        'assistant',
        '[$header] ${view.phase.label}${view.error.isEmpty ? '' : '：${view.error}'}',
        error: true,
      ),
      BotTaskPhase.cancelled => _message(
        'assistant',
        '[$header] ${view.phase.label}',
        error: true,
      ),
      _ => _message(
        'assistant',
        appText(
          '[$header] 仍在执行（${view.phase.label}），已转为后台任务，可在 Bot 团队页继续查看。',
          '[$header] Still running (${view.phase.label}); it continues in the '
              'background on the Bot team page.',
        ),
      ),
    };
  }

  GatewayChatMessage _signInRequired() => _message(
    'assistant',
    appText(
      '需要先连接 Bridge 并登录账户，才能把任务交给 DS Bot。',
      'Connect the Bridge and sign in to hand tasks to DS Bot.',
    ),
    error: true,
  );

  String _describe(Object failure) =>
      failure is TaskSessionException ? failure.message : failure.toString();

  GatewayChatMessage _message(String role, String text, {bool error = false}) {
    return GatewayChatMessage(
      id: nextLocalMessageIdInternal(),
      role: role,
      text: text,
      timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
      toolCallId: null,
      toolName: null,
      stopReason: null,
      pending: false,
      error: error,
    );
  }
}
