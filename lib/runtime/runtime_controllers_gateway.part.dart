part of 'runtime_controllers.dart';

class _AiGatewayResponseException implements Exception {
  const _AiGatewayResponseException({
    required this.statusCode,
    required this.message,
  });

  final int statusCode;
  final String message;
}

class GatewayAgentsController extends ChangeNotifier {
  GatewayAgentsController(this._runtime);

  final GatewayRuntime _runtime;

  List<GatewayAgentSummary> _agents = const <GatewayAgentSummary>[];
  String _selectedAgentId = '';
  bool _loading = false;
  String? _error;

  List<GatewayAgentSummary> get agents => _agents;
  String get selectedAgentId => _selectedAgentId;
  bool get loading => _loading;
  String? get error => _error;

  GatewayAgentSummary? get selectedAgent {
    final selected = _selectedAgentId.trim();
    if (selected.isEmpty) {
      return null;
    }
    for (final agent in _agents) {
      if (agent.id == selected) {
        return agent;
      }
    }
    return null;
  }

  String get activeAgentName => selectedAgent?.name ?? 'Main';

  void restoreSelection(String agentId) {
    _selectedAgentId = agentId.trim();
    notifyListeners();
  }

  void selectAgent(String? agentId) {
    _selectedAgentId = agentId?.trim() ?? '';
    notifyListeners();
  }

  Future<void> refresh() async {
    if (!_runtime.isConnected) {
      _agents = const <GatewayAgentSummary>[];
      _error = null;
      notifyListeners();
      return;
    }
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _agents = await _runtime.listAgents();
      if (_selectedAgentId.isNotEmpty &&
          !_agents.any((item) => item.id == _selectedAgentId)) {
        _selectedAgentId = '';
      }
    } catch (error) {
      _error = error.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}

class GatewaySessionsController extends ChangeNotifier {
  GatewaySessionsController(this._runtime);

  final GatewayRuntime _runtime;

  List<GatewaySessionSummary> _sessions = const <GatewaySessionSummary>[];
  String _currentSessionKey = 'main';
  String _mainSessionBaseKey = 'main';
  String _selectedAgentId = '';
  String _defaultAgentId = '';
  bool _loading = false;
  String? _error;

  List<GatewaySessionSummary> get sessions => _sessions;
  String get currentSessionKey => _currentSessionKey;
  bool get loading => _loading;
  String? get error => _error;
  String get mainSessionBaseKey => _mainSessionBaseKey;

  void configure({
    required String mainSessionKey,
    required String selectedAgentId,
    required String defaultAgentId,
  }) {
    _mainSessionBaseKey = normalizeMainSessionKey(mainSessionKey);
    _selectedAgentId = selectedAgentId.trim();
    _defaultAgentId = defaultAgentId.trim();
    final preferred = preferredSessionKey;
    if (_currentSessionKey.trim().isEmpty ||
        _currentSessionKey == 'main' ||
        _currentSessionKey == _mainSessionBaseKey ||
        _currentSessionKey.startsWith('agent:')) {
      _currentSessionKey = preferred;
    }
    notifyListeners();
  }

  String get preferredSessionKey {
    final selected = _selectedAgentId.trim();
    final defaultAgent = _defaultAgentId.trim();
    final base = normalizeMainSessionKey(_mainSessionBaseKey);
    if (selected.isEmpty ||
        (defaultAgent.isNotEmpty && selected == defaultAgent)) {
      return base;
    }
    return makeAgentSessionKey(agentId: selected, baseKey: base);
  }

  Future<void> refresh() async {
    if (!_runtime.isConnected) {
      _sessions = const <GatewaySessionSummary>[];
      _error = null;
      notifyListeners();
      return;
    }
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _sessions = await _runtime.listSessions(limit: 50);
      if (!_sessions.any(
        (item) => matchesSessionKey(item.key, _currentSessionKey),
      )) {
        _currentSessionKey = preferredSessionKey;
      }
    } catch (error) {
      _error = error.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> switchSession(String sessionKey) async {
    final trimmed = sessionKey.trim();
    if (trimmed.isEmpty || trimmed == _currentSessionKey) {
      return;
    }
    _currentSessionKey = trimmed;
    notifyListeners();
  }
}

class GatewayChatController extends ChangeNotifier {
  GatewayChatController(this._runtime);

  final GatewayRuntime _runtime;

  List<GatewayChatMessage> _messages = const <GatewayChatMessage>[];
  String _sessionKey = 'main';
  bool _loading = false;
  bool _sending = false;
  bool _aborting = false;
  String? _error;
  String? _streamingAssistantText;
  final Set<String> _pendingRuns = <String>{};

  List<GatewayChatMessage> get messages => _messages;
  String get sessionKey => _sessionKey;
  bool get loading => _loading;
  bool get sending => _sending;
  bool get aborting => _aborting;
  String? get error => _error;
  String? get streamingAssistantText => _streamingAssistantText;
  bool get hasPendingRun => _pendingRuns.isNotEmpty;
  String? get activeRunId => _pendingRuns.isEmpty ? null : _pendingRuns.first;

  Future<void> loadSession(String sessionKey) async {
    final next = sessionKey.trim().isEmpty ? 'main' : sessionKey.trim();
    _sessionKey = next;
    if (!_runtime.isConnected) {
      _messages = const <GatewayChatMessage>[];
      _streamingAssistantText = null;
      _error = null;
      notifyListeners();
      return;
    }
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _messages = await _runtime.loadHistory(next);
      _streamingAssistantText = null;
    } catch (error) {
      _error = error.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> sendMessage({
    required String sessionKey,
    required String message,
    required String thinking,
    List<GatewayChatAttachmentPayload> attachments =
        const <GatewayChatAttachmentPayload>[],
    String? agentId,
    Map<String, dynamic>? metadata,
  }) async {
    final trimmed = message.trim();
    if ((trimmed.isEmpty && attachments.isEmpty) || !_runtime.isConnected) {
      return;
    }
    _sessionKey = sessionKey.trim().isEmpty ? 'main' : sessionKey.trim();
    _sending = true;
    _error = null;
    _streamingAssistantText = null;
    _messages = List<GatewayChatMessage>.from(_messages)
      ..add(
        GatewayChatMessage(
          id: _ephemeralId(),
          role: 'user',
          text: trimmed.isEmpty ? 'See attached.' : trimmed,
          timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
          toolCallId: null,
          toolName: null,
          stopReason: null,
          pending: false,
          error: false,
        ),
      );
    notifyListeners();
    try {
      final runId = await _runtime.sendChat(
        sessionKey: _sessionKey,
        message: trimmed.isEmpty ? 'See attached.' : trimmed,
        thinking: thinking,
        attachments: attachments,
        agentId: agentId,
        metadata: metadata,
      );
      _pendingRuns.add(runId);
    } catch (error) {
      _error = error.toString();
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  Future<void> abortRun() async {
    if (_pendingRuns.isEmpty || !_runtime.isConnected) {
      return;
    }
    _aborting = true;
    notifyListeners();
    try {
      final runIds = _pendingRuns.toList(growable: false);
      for (final runId in runIds) {
        await _runtime.abortChat(sessionKey: _sessionKey, runId: runId);
      }
    } catch (error) {
      _error = error.toString();
    } finally {
      _aborting = false;
      notifyListeners();
    }
  }

  void handleEvent(GatewayPushEvent event) {
    if (event.event == 'chat') {
      _handleChatEvent(asMap(event.payload));
      return;
    }
    if (event.event == 'agent') {
      _handleAgentEvent(asMap(event.payload));
    }
  }

  void clear() {
    _messages = const <GatewayChatMessage>[];
    _pendingRuns.clear();
    _streamingAssistantText = null;
    _error = null;
    notifyListeners();
  }

  void _handleChatEvent(Map<String, dynamic> payload) {
    final runId = stringValue(payload['runId']);
    final state = stringValue(payload['state']) ?? '';
    final incomingSessionKey =
        stringValue(payload['sessionKey']) ?? _sessionKey;
    final isOurRun = runId != null && _pendingRuns.contains(runId);
    if (!matchesSessionKey(incomingSessionKey, _sessionKey) && !isOurRun) {
      return;
    }

    final message = asMap(payload['message']);
    final role = (stringValue(message['role']) ?? '').toLowerCase();
    final text = extractMessageText(message);
    if (role == 'assistant' &&
        text.isNotEmpty &&
        (state == 'delta' || state == 'final')) {
      _streamingAssistantText = text;
    }
    if (state == 'error') {
      _error = stringValue(payload['errorMessage']) ?? 'Chat failed';
    }
    if (state == 'final' || state == 'aborted' || state == 'error') {
      if (runId != null) {
        _pendingRuns.remove(runId);
      } else {
        _pendingRuns.clear();
      }
      unawaited(loadSession(_sessionKey));
      notifyListeners();
      return;
    }
    notifyListeners();
  }

  void _handleAgentEvent(Map<String, dynamic> payload) {
    final runId = stringValue(payload['runId']);
    if (runId == null || !_pendingRuns.contains(runId)) {
      return;
    }
    final stream = stringValue(payload['stream']);
    final data = asMap(payload['data']);
    if (stream == 'assistant') {
      final nextText = stringValue(data['text']) ?? extractMessageText(data);
      if (nextText.isNotEmpty) {
        _streamingAssistantText = nextText;
        notifyListeners();
      }
    }
  }
}
