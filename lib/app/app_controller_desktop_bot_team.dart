import '../features/bot_team/bot_team_models.dart';
import '../features/bot_team/role_task_runner.dart';
import '../features/bot_team/role_task_session_binding.dart';
import '../i18n/app_language.dart';
import '../models/app_models.dart';
import '../runtime/acp_endpoint_paths.dart';
import '../runtime/runtime_models.dart';
import '../runtime/task_session_client.dart';
import '../runtime/task_session_binding.dart';
import '../runtime/task_session_sync_service.dart';
import '../runtime/file_store_support.dart';
import 'app_controller_desktop_core.dart';
import 'app_controller_desktop_runtime_helpers.dart';
import 'app_controller_desktop_thread_sessions.dart';
import 'app_controller_desktop_thread_storage.dart';

/// Bot tasks go to Accounts/DSH through the Bridge `/api/v1` proxy with the
/// signed-in account token or self-hosted bridge token; the DSH orchestrator runs them (AI Workspace v2.1).
extension AppControllerDesktopBotTeam on AppController {
  static String _stripBearerToken(String? raw) {
    final trimmed = raw?.trim() ?? '';
    if (trimmed.toLowerCase().startsWith('bearer ')) {
      return trimmed.substring(7).trim();
    }
    return trimmed;
  }

  String get _taskSessionSource {
    final config =
        settingsControllerInternal.snapshot.acpBridgeServerModeConfig;
    final source = config.effective.source.trim();
    if (source != '' && source != 'default') return source;
    if (config.selfHosted.isConfigured) return 'bridge';
    if (settingsControllerInternal.accountSessionTokenInternal
        .trim()
        .isNotEmpty) {
      return 'cloud';
    }
    return 'default';
  }

  Uri? _taskSessionEndpoint() {
    final config =
        settingsControllerInternal.snapshot.acpBridgeServerModeConfig;
    final source = _taskSessionSource;
    if (source == 'cloud' &&
        config.effective.source.trim() == 'cloud' &&
        config.effective.endpoint.trim().isEmpty) {
      return null;
    }
    final raw = source == 'bridge'
        ? config.selfHosted.serverUrl
        : config.effective.endpoint;
    final endpoint = raw.trim().isNotEmpty
        ? Uri.tryParse(raw.trim())
        : source == 'bridge'
        ? null
        : resolveBridgeAcpEndpointInternal();
    if (endpoint == null ||
        endpoint.host.isEmpty ||
        endpoint.userInfo.isNotEmpty ||
        !['http', 'https'].contains(endpoint.scheme)) {
      return null;
    }
    // Match the shared-session transport contract: remote origins require
    // HTTPS; an explicitly configured loopback may intentionally use HTTP.
    final host = endpoint.host.toLowerCase();
    final isLoopback =
        host == 'localhost' ||
        host == '127.0.0.1' ||
        host == '::1' ||
        host == '[::1]';
    if (endpoint.scheme != 'https' && !isLoopback) {
      return null;
    }
    return endpoint.replace(
      path: AcpEndpointPaths.fromBaseEndpoint(endpoint).basePath,
      query: null,
      fragment: null,
    );
  }

  /// Explicit source failures stop here. Environment compatibility applies
  /// only when no account or self-hosted source is configured.
  Future<String?> resolveTaskSessionAuthTokenInternal(Uri endpoint) async {
    final expected = _taskSessionEndpoint();
    final base = endpoint.replace(
      path: AcpEndpointPaths.fromBaseEndpoint(endpoint).basePath,
      query: null,
      fragment: null,
    );
    if (expected == null || base != expected) return null;
    switch (_taskSessionSource) {
      case 'bridge':
        final config =
            settingsControllerInternal.snapshot.acpBridgeServerModeConfig;
        if (!config.selfHosted.isConfigured) return null;
        final ref = config.selfHosted.passwordRef.trim();
        if (ref.isEmpty) return null;
        final token = _stripBearerToken(
          await storeInternal.loadSecretValueByRef(ref),
        );
        return token.isEmpty ? null : token;
      case 'cloud':
        final token = settingsControllerInternal.accountSessionTokenInternal
            .trim();
        return token.isEmpty ? null : token;
      case 'default':
        break;
      default:
        return null;
    }
    final envToken =
        runtimeEnvironmentValueInternal('ACP_BRIDGE_SERVER_TOKEN') ??
        runtimeEnvironmentValueInternal('AI_WORKSPACE_AUTH_TOKEN') ??
        runtimeEnvironmentValueInternal('BRIDGE_AUTH_TOKEN');
    if (envToken != null && envToken.trim().isNotEmpty) {
      return envToken.trim();
    }
    return null;
  }

  /// Secure self-host credentials require the asynchronous resolver.
  TaskSessionClient? createTaskSessionClient() {
    final endpoint = _taskSessionEndpoint();
    if (endpoint == null) {
      return null;
    }
    final source = _taskSessionSource;
    if (source != 'cloud' && source != 'default') return null;
    var token = source == 'cloud'
        ? settingsControllerInternal.accountSessionTokenInternal.trim()
        : '';
    if (source == 'default') {
      token =
          (runtimeEnvironmentValueInternal('ACP_BRIDGE_SERVER_TOKEN') ??
                  runtimeEnvironmentValueInternal('AI_WORKSPACE_AUTH_TOKEN') ??
                  runtimeEnvironmentValueInternal('BRIDGE_AUTH_TOKEN'))
              ?.trim() ??
          '';
    }
    if (token.isEmpty) {
      return null;
    }
    final base = endpoint.replace(
      path: AcpEndpointPaths.fromBaseEndpoint(endpoint).basePath,
      query: null,
      fragment: null,
    );
    return HttpTaskSessionClient(bridgeBase: base, accountToken: token);
  }

  /// Creates a client using only the selected source's credentials.
  Future<TaskSessionClient?> resolveTaskSessionClientInternal() async {
    final endpoint = _taskSessionEndpoint();
    if (endpoint == null) {
      return null;
    }
    final token = await resolveTaskSessionAuthTokenInternal(endpoint);
    if (token == null || token.isEmpty) {
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
  /// 直通模式：在线即时任务通过 DS Bridge DSH Adapter 执行
  Future<void> runRoleTaskInConversation({
    required String sessionKey,
    required String text,
    required AssistantMode role,
    TaskSessionClient? Function()? clientFactory,
    TaskSessionBindingStore? bindingStore,
  }) async {
    final key = normalizedAssistantSessionKeyInternal(sessionKey);
    final prompt = text.trim();
    if (prompt.isEmpty || roleTaskPendingSessionKeysInternal.contains(key)) {
      return;
    }
    appendAssistantThreadMessageInternal(key, _message('user', prompt));
    roleTaskPendingSessionKeysInternal.add(key);
    notifyIfActiveInternal();
    try {
      final client = clientFactory != null
          ? clientFactory()
          : await resolveTaskSessionClientInternal();
      if (client == null) {
        appendAssistantThreadMessageInternal(key, _signInRequired());
        return;
      }
      final endpoint = _taskSessionEndpoint();
      if (endpoint == null) {
        throw StateError('Task session endpoint is unavailable.');
      }
      final store = bindingStore ?? await _roleTaskBindingStore();
      final bindingKey = roleTaskBindingKey(
        threadKey: key,
        source: _taskSessionSource,
        endpoint: endpoint,
      );
      final existing = await loadRoleTaskSession(
        store: store,
        client: client,
        bindingKey: bindingKey,
      );
      final view = await RoleTaskRunner(client: client).run(
        text: prompt,
        role: role.name,
        existingSession: existing,
        onSessionReady: (namespace, session) async {
          final previous = await store.load(bindingKey);
          if (previous != null &&
              (previous.namespaceId != namespace ||
                  previous.cloudSessionId != session.sessionId)) {
            throw const TaskSessionBindingMismatch(field: 'sessionIdentity');
          }
          await store.save(
            previous ??
                TaskSessionBinding(
                  taskThreadKey: bindingKey,
                  cloudSessionId: session.sessionId,
                  namespaceId: namespace,
                  lastEventSeq: 0,
                  snapshotVersion: 0,
                ),
          );
        },
      );
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

  Future<TaskSessionBindingStore> _roleTaskBindingStore() async {
    final settingsFile = await storeInternal.resolvedSettingsFile();
    if (settingsFile == null) {
      throw StateError('Task session storage is unavailable.');
    }
    final root = settingsFile.parent.parent.path;
    return FileTaskSessionBindingStore(
      layoutResolver: StoreLayoutResolver(
        appDataRootPathResolver: () async => root,
        supportRootPathResolver: () async => root,
      ),
    );
  }

  /// Hands [text] to the Bot team as a background [role] task thread for
  /// offline, long-running or scheduled work, and notes the hand-off in the
  /// [sessionKey] conversation. Returns the new Bot team session id, or an
  /// empty string when the task could not be handed off.
  /// 离线模式：离线后台任务交给 DSH Bot Adapter 角色编排
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
    final client = clientFactory != null
        ? clientFactory()
        : await resolveTaskSessionClientInternal();
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
      final routing = botRoleRouting(role: role.name);
      routing['preferredGatewayProviderId'] = 'dsbot';
      await client.appendMessage(
        sessionId: session.sessionId,
        clientRequestId: (newRequestId ?? nextLocalMessageIdInternal)(),
        text: prompt,
        routing: routing,
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
