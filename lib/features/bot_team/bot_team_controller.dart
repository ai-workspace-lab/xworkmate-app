import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../i18n/app_language.dart';
import '../../runtime/task_session_client.dart';
import 'bot_team_models.dart';

/// Drives the Bot team page: sessions and their task runs live in Accounts,
/// so this controller keeps only what the page shows and re-reads the rest.
class BotTeamController extends ChangeNotifier {
  BotTeamController({
    required TaskSessionClient? Function() clientFactory,
    this.pollInterval = const Duration(milliseconds: 1500),
    String Function()? newRequestId,
  }) : _clientFactory = clientFactory,
       _newRequestId = newRequestId ?? (() => const Uuid().v4());

  final TaskSessionClient? Function() _clientFactory;
  final Duration pollInterval;
  final String Function() _newRequestId;

  TaskSessionClient? _client;
  Timer? _poll;
  bool _polling = false;
  bool _disposed = false;

  bool loading = false;
  bool sending = false;
  String error = '';
  String namespaceId = '';
  List<TaskSessionSummary> sessions = const <TaskSessionSummary>[];
  String selectedSessionId = '';
  final List<TaskSessionEvent> _events = <TaskSessionEvent>[];
  int _lastSeq = 0;
  BotRole role = BotRole.auto;

  List<BotTaskView> get tasks => foldBotTasks(_events);

  bool get hasActiveTask => tasks.any((task) => task.active);

  bool get connected => _client != null;

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  String _describe(Object error) =>
      error is TaskSessionException ? error.message : error.toString();

  Future<void> load() async {
    _client = _clientFactory();
    if (_client == null) {
      error = appText(
        '需要先连接 Bridge 并登录账户，Bot 任务才能下发。',
        'Connect the Bridge and sign in to send Bot tasks.',
      );
      _notify();
      return;
    }
    loading = true;
    error = '';
    _notify();
    try {
      namespaceId = await _client!.personalNamespaceId();
      sessions = await _client!.listSessions(namespaceId);
      if (selectedSessionId.isEmpty && sessions.isNotEmpty) {
        await _select(sessions.first.sessionId);
      }
    } catch (failure) {
      error = _describe(failure);
    } finally {
      loading = false;
      _notify();
    }
  }

  void setRole(BotRole value) {
    role = value;
    _notify();
  }

  Future<void> selectSession(String sessionId) async {
    if (sessionId == selectedSessionId) {
      return;
    }
    await _select(sessionId);
    _notify();
  }

  void startNewSession() {
    _stopPolling();
    selectedSessionId = '';
    _events.clear();
    _lastSeq = 0;
    _notify();
  }

  Future<void> _select(String sessionId) async {
    _stopPolling();
    selectedSessionId = sessionId;
    _events.clear();
    _lastSeq = 0;
    await _refreshEvents();
    _ensurePolling();
  }

  /// Sends one task. A new session is created for the first task; the run is
  /// queued in Accounts and the orchestrator picks it up.
  Future<void> send(String text, {String workspaceKey = ''}) async {
    final client = _client;
    final prompt = text.trim();
    if (client == null || prompt.isEmpty || sending) {
      return;
    }
    sending = true;
    error = '';
    _notify();
    try {
      if (selectedSessionId.isEmpty) {
        final title = prompt.length > 40
            ? '${prompt.substring(0, 40)}…'
            : prompt;
        final created = await client.createSession(
          namespaceId: namespaceId,
          title: title,
        );
        sessions = <TaskSessionSummary>[created, ...sessions];
        selectedSessionId = created.sessionId;
        _events.clear();
        _lastSeq = 0;
      }
      await client.appendMessage(
        sessionId: selectedSessionId,
        clientRequestId: _newRequestId(),
        text: prompt,
        routing: <String, Object?>{
          'roleMode': 'auto',
          if (role.routingValue.isNotEmpty) 'role': role.routingValue,
          if (workspaceKey.trim().isNotEmpty) 'workspace': workspaceKey.trim(),
        },
      );
      await _refreshEvents();
      _ensurePolling();
    } catch (failure) {
      error = _describe(failure);
    } finally {
      sending = false;
      _notify();
    }
  }

  Future<void> cancel(String taskRunId) async {
    final client = _client;
    if (client == null || selectedSessionId.isEmpty) {
      return;
    }
    try {
      await client.cancelRun(
        sessionId: selectedSessionId,
        taskRunId: taskRunId,
        clientRequestId: _newRequestId(),
      );
      await _refreshEvents();
    } catch (failure) {
      error = _describe(failure);
    }
    _notify();
  }

  Future<void> _refreshEvents() async {
    final client = _client;
    final sessionId = selectedSessionId;
    if (client == null || sessionId.isEmpty) {
      return;
    }
    var more = true;
    while (more) {
      final page = await client.listEvents(
        sessionId: sessionId,
        afterSeq: _lastSeq,
      );
      if (sessionId != selectedSessionId) {
        return;
      }
      _events.addAll(page.events);
      if (page.events.isNotEmpty) {
        _lastSeq = page.events.last.seq;
      }
      more = page.events.isNotEmpty && _lastSeq < page.lastEventSeq;
    }
  }

  void _ensurePolling() {
    if (_poll != null || !hasActiveTask) {
      return;
    }
    _poll = Timer.periodic(pollInterval, (_) => unawaited(_pollOnce()));
  }

  Future<void> _pollOnce() async {
    if (_polling) {
      return;
    }
    _polling = true;
    try {
      await _refreshEvents();
      if (!hasActiveTask) {
        _stopPolling();
      }
    } catch (failure) {
      error = _describe(failure);
    } finally {
      _polling = false;
      _notify();
    }
  }

  void _stopPolling() {
    _poll?.cancel();
    _poll = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _stopPolling();
    super.dispose();
  }
}
