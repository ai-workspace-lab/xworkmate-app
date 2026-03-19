import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'gateway_runtime.dart';
import 'runtime_models.dart';
import 'secure_config_store.dart';

class SettingsController extends ChangeNotifier {
  SettingsController(this._store);

  final SecureConfigStore _store;

  SettingsSnapshot _snapshot = SettingsSnapshot.defaults();
  Map<String, String> _secureRefs = const <String, String>{};
  List<SecretAuditEntry> _auditTrail = const <SecretAuditEntry>[];
  String _ollamaStatus = 'Idle';
  String _vaultStatus = 'Idle';
  String _aiGatewayStatus = 'Idle';

  SettingsSnapshot get snapshot => _snapshot;
  Map<String, String> get secureRefs => _secureRefs;
  List<SecretAuditEntry> get auditTrail => _auditTrail;
  String get ollamaStatus => _ollamaStatus;
  String get vaultStatus => _vaultStatus;
  String get aiGatewayStatus => _aiGatewayStatus;

  Future<void> initialize() async {
    _snapshot = await _store.loadSettingsSnapshot();
    await _reloadDerivedState();
    notifyListeners();
  }

  Future<void> refreshDerivedState() async {
    await _reloadDerivedState();
    notifyListeners();
  }

  Future<void> saveSnapshot(SettingsSnapshot snapshot) async {
    _snapshot = snapshot;
    await _store.saveSettingsSnapshot(snapshot);
    await _reloadDerivedState();
    notifyListeners();
  }

  Future<void> saveGatewaySecrets({
    required String token,
    required String password,
  }) async {
    final trimmedToken = token.trim();
    final trimmedPassword = password.trim();
    if (trimmedToken.isNotEmpty) {
      await _store.saveGatewayToken(trimmedToken);
      await appendAudit(
        SecretAuditEntry(
          timeLabel: _timeLabel(),
          action: 'Updated',
          provider: 'Gateway',
          target: 'gateway_token',
          module: 'Assistant',
          status: 'Success',
        ),
      );
    }
    if (trimmedPassword.isNotEmpty) {
      await _store.saveGatewayPassword(trimmedPassword);
      await appendAudit(
        SecretAuditEntry(
          timeLabel: _timeLabel(),
          action: 'Updated',
          provider: 'Gateway',
          target: 'gateway_password',
          module: 'Assistant',
          status: 'Success',
        ),
      );
    }
    await _reloadDerivedState();
    notifyListeners();
  }

  Future<void> clearGatewaySecrets({
    bool token = false,
    bool password = false,
  }) async {
    if (token) {
      await _store.clearGatewayToken();
      await appendAudit(
        SecretAuditEntry(
          timeLabel: _timeLabel(),
          action: 'Cleared',
          provider: 'Gateway',
          target: 'gateway_token',
          module: 'Assistant',
          status: 'Success',
        ),
      );
    }
    if (password) {
      await _store.clearGatewayPassword();
      await appendAudit(
        SecretAuditEntry(
          timeLabel: _timeLabel(),
          action: 'Cleared',
          provider: 'Gateway',
          target: 'gateway_password',
          module: 'Assistant',
          status: 'Success',
        ),
      );
    }
    await _reloadDerivedState();
    notifyListeners();
  }

  Future<void> saveOllamaCloudApiKey(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return;
    }
    await _store.saveOllamaCloudApiKey(trimmed);
    await appendAudit(
      SecretAuditEntry(
        timeLabel: _timeLabel(),
        action: 'Updated',
        provider: 'Ollama Cloud',
        target: _snapshot.ollamaCloud.apiKeyRef,
        module: 'Settings',
        status: 'Success',
      ),
    );
    await _reloadDerivedState();
    notifyListeners();
  }

  Future<String> loadOllamaCloudApiKey() async {
    return (await _store.loadOllamaCloudApiKey())?.trim() ?? '';
  }

  Future<void> saveVaultToken(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return;
    }
    await _store.saveVaultToken(trimmed);
    await appendAudit(
      SecretAuditEntry(
        timeLabel: _timeLabel(),
        action: 'Updated',
        provider: 'Vault',
        target: _snapshot.vault.tokenRef,
        module: 'Secrets',
        status: 'Success',
      ),
    );
    await _reloadDerivedState();
    notifyListeners();
  }

  Future<String> loadVaultToken() async {
    return (await _store.loadVaultToken())?.trim() ?? '';
  }

  Future<void> saveAiGatewayApiKey(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return;
    }
    await _store.saveAiGatewayApiKey(trimmed);
    await appendAudit(
      SecretAuditEntry(
        timeLabel: _timeLabel(),
        action: 'Updated',
        provider: 'AI Gateway',
        target: _snapshot.aiGateway.apiKeyRef,
        module: 'Settings',
        status: 'Success',
      ),
    );
    await _reloadDerivedState();
    notifyListeners();
  }

  Future<String> loadAiGatewayApiKey() async {
    return (await _store.loadAiGatewayApiKey())?.trim() ?? '';
  }

  Future<void> appendAudit(SecretAuditEntry entry) async {
    await _store.appendAudit(entry);
    _auditTrail = await _store.loadAuditTrail();
    notifyListeners();
  }

  Future<String> testOllamaConnection({required bool cloud}) async {
    final base = cloud
        ? _snapshot.ollamaCloud.baseUrl.trim()
        : _snapshot.ollamaLocal.endpoint.trim();
    if (base.isEmpty) {
      final message = 'Missing endpoint';
      _ollamaStatus = message;
      notifyListeners();
      return message;
    }
    try {
      final uri = Uri.parse(
        cloud ? base : '$base${base.endsWith('/') ? '' : '/'}api/tags',
      );
      final response = await _simpleGet(
        uri,
        headers: cloud
            ? <String, String>{
                if (_secureRefs[_snapshot.ollamaCloud.apiKeyRef] != null)
                  'Authorization': 'Bearer live-secret',
              }
            : const <String, String>{},
      );
      final message = response.statusCode < 500
          ? 'Reachable (${response.statusCode})'
          : 'Unhealthy (${response.statusCode})';
      _ollamaStatus = message;
      notifyListeners();
      return message;
    } catch (error) {
      final message = 'Failed: $error';
      _ollamaStatus = message;
      notifyListeners();
      return message;
    }
  }

  Future<String> testVaultConnection() async {
    final address = _snapshot.vault.address.trim();
    if (address.isEmpty) {
      const message = 'Missing address';
      _vaultStatus = message;
      notifyListeners();
      return message;
    }
    try {
      final uri = Uri.parse(
        '$address${address.endsWith('/') ? '' : '/'}v1/sys/health',
      );
      final headers = <String, String>{
        if (_snapshot.vault.namespace.trim().isNotEmpty)
          'X-Vault-Namespace': _snapshot.vault.namespace.trim(),
      };
      final token = await _store.loadVaultToken();
      if (token != null && token.trim().isNotEmpty) {
        headers['X-Vault-Token'] = token.trim();
      }
      final response = await _simpleGet(uri, headers: headers);
      final message = response.statusCode < 500
          ? 'Reachable (${response.statusCode})'
          : 'Unhealthy (${response.statusCode})';
      _vaultStatus = message;
      notifyListeners();
      return message;
    } catch (error) {
      final message = 'Failed: $error';
      _vaultStatus = message;
      notifyListeners();
      return message;
    }
  }

  Future<AiGatewayProfile> syncAiGatewayCatalog(
    AiGatewayProfile profile, {
    String apiKeyOverride = '',
  }) async {
    final normalizedBaseUrl = _normalizeAiGatewayBaseUrl(profile.baseUrl);
    if (normalizedBaseUrl == null) {
      final next = profile.copyWith(
        syncState: 'invalid',
        syncMessage: 'Missing AI Gateway URL',
      );
      _aiGatewayStatus = next.syncMessage;
      _snapshot = _snapshot.copyWith(aiGateway: next);
      await _store.saveSettingsSnapshot(_snapshot);
      notifyListeners();
      return next;
    }
    final apiKey = apiKeyOverride.trim().isNotEmpty
        ? apiKeyOverride.trim()
        : (await _store.loadAiGatewayApiKey())?.trim() ?? '';
    if (apiKey.isEmpty) {
      final next = profile.copyWith(
        baseUrl: normalizedBaseUrl.toString(),
        syncState: 'invalid',
        syncMessage: 'Missing AI Gateway API key',
      );
      _aiGatewayStatus = next.syncMessage;
      _snapshot = _snapshot.copyWith(aiGateway: next);
      await _store.saveSettingsSnapshot(_snapshot);
      notifyListeners();
      return next;
    }
    try {
      final models = await loadAiGatewayModels(
        profile: profile.copyWith(baseUrl: normalizedBaseUrl.toString()),
        apiKeyOverride: apiKey,
      );
      final availableModels = models
          .map((item) => item.id)
          .toList(growable: false);
      final retainedSelected = profile.selectedModels
          .where(availableModels.contains)
          .toList(growable: false);
      final selectedModels = retainedSelected.isNotEmpty
          ? retainedSelected
          : availableModels.take(5).toList(growable: false);
      final currentDefaultModel = _snapshot.defaultModel.trim();
      final resolvedDefaultModel = selectedModels.contains(currentDefaultModel)
          ? currentDefaultModel
          : selectedModels.isNotEmpty
          ? selectedModels.first
          : availableModels.isNotEmpty
          ? availableModels.first
          : '';
      final next = profile.copyWith(
        baseUrl: normalizedBaseUrl.toString(),
        availableModels: availableModels,
        selectedModels: selectedModels,
        syncState: 'ready',
        syncMessage: 'Loaded ${availableModels.length} model(s)',
      );
      _aiGatewayStatus = 'Ready (${availableModels.length})';
      _snapshot = _snapshot.copyWith(
        aiGateway: next,
        defaultModel: resolvedDefaultModel,
      );
      await _store.saveSettingsSnapshot(_snapshot);
      await _reloadDerivedState();
      notifyListeners();
      return next;
    } catch (error) {
      final next = profile.copyWith(
        baseUrl: normalizedBaseUrl.toString(),
        syncState: 'error',
        syncMessage: _networkErrorLabel(error),
      );
      _aiGatewayStatus = next.syncMessage;
      _snapshot = _snapshot.copyWith(aiGateway: next);
      await _store.saveSettingsSnapshot(_snapshot);
      notifyListeners();
      return next;
    }
  }

  Future<AiGatewayConnectionCheck> testAiGatewayConnection(
    AiGatewayProfile profile, {
    String apiKeyOverride = '',
  }) async {
    final normalizedBaseUrl = _normalizeAiGatewayBaseUrl(profile.baseUrl);
    if (normalizedBaseUrl == null) {
      return const AiGatewayConnectionCheck(
        state: 'invalid',
        message: 'Missing AI Gateway URL',
        endpoint: '',
        modelCount: 0,
      );
    }
    final apiKey = apiKeyOverride.trim().isNotEmpty
        ? apiKeyOverride.trim()
        : (await _store.loadAiGatewayApiKey())?.trim() ?? '';
    final endpoint = _aiGatewayModelsUri(normalizedBaseUrl).toString();
    if (apiKey.isEmpty) {
      return AiGatewayConnectionCheck(
        state: 'invalid',
        message: 'Missing AI Gateway API key',
        endpoint: endpoint,
        modelCount: 0,
      );
    }
    try {
      final models = await _requestAiGatewayModels(
        uri: _aiGatewayModelsUri(normalizedBaseUrl),
        apiKey: apiKey,
      );
      if (models.isEmpty) {
        return AiGatewayConnectionCheck(
          state: 'empty',
          message: 'Authenticated but no models were returned',
          endpoint: endpoint,
          modelCount: 0,
        );
      }
      return AiGatewayConnectionCheck(
        state: 'ready',
        message: 'Authenticated · ${models.length} model(s) available',
        endpoint: endpoint,
        modelCount: models.length,
      );
    } catch (error) {
      return AiGatewayConnectionCheck(
        state: 'error',
        message: _networkErrorLabel(error),
        endpoint: endpoint,
        modelCount: 0,
      );
    }
  }

  Future<List<GatewayModelSummary>> loadAiGatewayModels({
    AiGatewayProfile? profile,
    String apiKeyOverride = '',
  }) async {
    final activeProfile = profile ?? _snapshot.aiGateway;
    final normalizedBaseUrl = _normalizeAiGatewayBaseUrl(activeProfile.baseUrl);
    if (normalizedBaseUrl == null) {
      return const <GatewayModelSummary>[];
    }
    final apiKey = apiKeyOverride.trim().isNotEmpty
        ? apiKeyOverride.trim()
        : (await _store.loadAiGatewayApiKey())?.trim() ?? '';
    if (apiKey.isEmpty) {
      return const <GatewayModelSummary>[];
    }
    return _requestAiGatewayModels(
      uri: _aiGatewayModelsUri(normalizedBaseUrl),
      apiKey: apiKey,
    );
  }

  List<SecretReferenceEntry> buildSecretReferences() {
    final entries = <SecretReferenceEntry>[
      ..._secureRefs.entries.map(
        (entry) => SecretReferenceEntry(
          name: entry.key,
          provider: _providerNameForSecret(entry.key),
          module: _moduleForSecret(entry.key),
          maskedValue: entry.value,
          status: 'In Use',
        ),
      ),
      SecretReferenceEntry(
        name: _snapshot.aiGateway.name,
        provider: 'AI Gateway',
        module: 'Settings',
        maskedValue: _snapshot.aiGateway.baseUrl.trim().isEmpty
            ? 'Not set'
            : _snapshot.aiGateway.baseUrl,
        status: _snapshot.aiGateway.syncState,
      ),
    ];
    return entries;
  }

  Future<void> _reloadDerivedState() async {
    final refs = await _store.loadSecureRefs();
    _secureRefs = {
      for (final entry in refs.entries)
        entry.key: SecureConfigStore.maskValue(entry.value),
    };
    _auditTrail = await _store.loadAuditTrail();
  }

  String _providerNameForSecret(String key) {
    if (key.contains('vault')) {
      return 'Vault';
    }
    if (key.contains('ollama')) {
      return 'Ollama Cloud';
    }
    if (key.contains('ai_gateway')) {
      return 'AI Gateway';
    }
    if (key.contains('gateway')) {
      return 'Gateway';
    }
    return 'Local Store';
  }

  String _moduleForSecret(String key) {
    if (key.contains('gateway')) {
      return key.contains('device_token') ? 'Devices' : 'Assistant';
    }
    if (key.contains('ollama')) {
      return 'Settings';
    }
    if (key.contains('ai_gateway')) {
      return 'Settings';
    }
    if (key.contains('vault')) {
      return 'Secrets';
    }
    return 'Workspace';
  }

  Uri? _normalizeAiGatewayBaseUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final candidate = trimmed.contains('://') ? trimmed : 'https://$trimmed';
    final uri = Uri.tryParse(candidate);
    if (uri == null || uri.host.trim().isEmpty) {
      return null;
    }
    final pathSegments = uri.pathSegments.where((item) => item.isNotEmpty);
    return uri.replace(
      pathSegments: pathSegments.isEmpty ? const <String>['v1'] : pathSegments,
      query: null,
      fragment: null,
    );
  }

  Uri _aiGatewayModelsUri(Uri baseUrl) {
    final pathSegments = baseUrl.pathSegments
        .where((item) => item.isNotEmpty)
        .toList(growable: true);
    if (pathSegments.isEmpty) {
      pathSegments.add('v1');
    }
    if (pathSegments.last != 'models') {
      pathSegments.add('models');
    }
    return baseUrl.replace(
      pathSegments: pathSegments,
      query: null,
      fragment: null,
    );
  }

  Future<List<GatewayModelSummary>> _requestAiGatewayModels({
    required Uri uri,
    required String apiKey,
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 6));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
      request.headers.set('x-api-key', apiKey);
      final response = await request.close().timeout(
        const Duration(seconds: 6),
      );
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _AiGatewayResponseException(
          statusCode: response.statusCode,
          message: _aiGatewayHttpErrorLabel(
            response.statusCode,
            _extractAiGatewayErrorDetail(body),
          ),
        );
      }
      final decoded = jsonDecode(_extractFirstJsonDocument(body));
      final rawModels = decoded is Map<String, dynamic>
          ? [
              ...asList(decoded['data']),
              if (asList(decoded['data']).isEmpty) ...asList(decoded['models']),
            ]
          : const <Object>[];
      final seen = <String>{};
      final items = <GatewayModelSummary>[];
      for (final item in rawModels) {
        final map = asMap(item);
        final modelId =
            stringValue(map['id']) ?? stringValue(map['name']) ?? '';
        if (modelId.trim().isEmpty || !seen.add(modelId)) {
          continue;
        }
        items.add(
          GatewayModelSummary(
            id: modelId,
            name: stringValue(map['name']) ?? modelId,
            provider:
                stringValue(map['provider']) ??
                stringValue(map['owned_by']) ??
                'AI Gateway',
            contextWindow:
                intValue(map['contextWindow']) ??
                intValue(map['context_window']),
            maxOutputTokens:
                intValue(map['maxOutputTokens']) ??
                intValue(map['max_output_tokens']),
          ),
        );
      }
      return items;
    } finally {
      client.close(force: true);
    }
  }

  String _networkErrorLabel(Object error) {
    if (error is _AiGatewayResponseException) {
      return error.message;
    }
    if (error is SocketException) {
      return 'Unable to reach the AI Gateway';
    }
    if (error is HandshakeException) {
      return 'TLS handshake failed';
    }
    if (error is TimeoutException) {
      return 'Connection timed out';
    }
    if (error is FormatException) {
      return 'AI Gateway returned invalid JSON';
    }
    return 'Failed: $error';
  }

  String _aiGatewayHttpErrorLabel(int statusCode, String detail) {
    final base = switch (statusCode) {
      400 => 'Bad request (400)',
      401 => 'Authentication failed (401)',
      403 => 'Access denied (403)',
      404 => 'Model catalog endpoint not found (404)',
      429 => 'Rate limited by AI Gateway (429)',
      >= 500 => 'AI Gateway unavailable ($statusCode)',
      _ => 'AI Gateway responded $statusCode',
    };
    return detail.isEmpty ? base : '$base · $detail';
  }

  String _extractAiGatewayErrorDetail(String body) {
    if (body.trim().isEmpty) {
      return '';
    }
    try {
      final decoded = jsonDecode(_extractFirstJsonDocument(body));
      final map = asMap(decoded);
      final error = asMap(map['error']);
      return (stringValue(error['message']) ??
              stringValue(map['message']) ??
              stringValue(map['detail']) ??
              '')
          .trim();
    } on FormatException {
      return '';
    }
  }

  String _extractFirstJsonDocument(String body) {
    final trimmed = body.trimLeft();
    if (trimmed.isEmpty) {
      throw const FormatException('Empty response body');
    }
    final start = trimmed.indexOf(RegExp(r'[\{\[]'));
    if (start < 0) {
      throw const FormatException('Missing JSON document');
    }
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var index = start; index < trimmed.length; index++) {
      final char = trimmed[index];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (char == r'\') {
        escaped = true;
        continue;
      }
      if (char == '"') {
        inString = !inString;
        continue;
      }
      if (inString) {
        continue;
      }
      if (char == '{' || char == '[') {
        depth += 1;
      } else if (char == '}' || char == ']') {
        depth -= 1;
        if (depth == 0) {
          return trimmed.substring(start, index + 1);
        }
      }
    }
    throw const FormatException('Unterminated JSON document');
  }

  Future<HttpClientResponse> _simpleGet(
    Uri uri, {
    required Map<String, String> headers,
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 4));
      for (final entry in headers.entries) {
        request.headers.set(entry.key, entry.value);
      }
      return await request.close().timeout(const Duration(seconds: 4));
    } finally {
      client.close(force: true);
    }
  }

  String _timeLabel() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }
}

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

class InstancesController extends ChangeNotifier {
  InstancesController(this._runtime);

  final GatewayRuntime _runtime;

  List<GatewayInstanceSummary> _items = const <GatewayInstanceSummary>[];
  bool _loading = false;
  String? _error;

  List<GatewayInstanceSummary> get items => _items;
  bool get loading => _loading;
  String? get error => _error;

  Future<void> refresh() async {
    if (!_runtime.isConnected) {
      _items = const <GatewayInstanceSummary>[];
      _error = null;
      notifyListeners();
      return;
    }
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _items = await _runtime.listInstances();
    } catch (error) {
      _error = error.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}

class SkillsController extends ChangeNotifier {
  SkillsController(this._runtime);

  final GatewayRuntime _runtime;

  List<GatewaySkillSummary> _items = const <GatewaySkillSummary>[];
  bool _loading = false;
  String? _error;

  List<GatewaySkillSummary> get items => _items;
  bool get loading => _loading;
  String? get error => _error;

  Future<void> refresh({String? agentId}) async {
    if (!_runtime.isConnected) {
      _items = const <GatewaySkillSummary>[];
      _error = null;
      notifyListeners();
      return;
    }
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _items = await _runtime.listSkills(agentId: agentId);
    } catch (error) {
      _error = error.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}

class ConnectorsController extends ChangeNotifier {
  ConnectorsController(this._runtime);

  final GatewayRuntime _runtime;

  List<GatewayConnectorSummary> _items = const <GatewayConnectorSummary>[];
  bool _loading = false;
  String? _error;

  List<GatewayConnectorSummary> get items => _items;
  bool get loading => _loading;
  String? get error => _error;

  Future<void> refresh() async {
    if (!_runtime.isConnected) {
      _items = const <GatewayConnectorSummary>[];
      _error = null;
      notifyListeners();
      return;
    }
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _items = await _runtime.listConnectors();
    } catch (error) {
      _error = error.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}

class ModelsController extends ChangeNotifier {
  ModelsController(this._runtime, this._settingsController);

  final GatewayRuntime _runtime;
  final SettingsController _settingsController;

  List<GatewayModelSummary> _items = const <GatewayModelSummary>[];
  bool _loading = false;
  String? _error;

  List<GatewayModelSummary> get items => _items;
  bool get loading => _loading;
  String? get error => _error;

  void restoreFromSettings(AiGatewayProfile profile) {
    final models = _modelsFromProfile(profile);
    if (models.length == _items.length &&
        models.every(
          (item) => _items.any((current) => current.id == item.id),
        )) {
      return;
    }
    _items = models;
    notifyListeners();
  }

  Future<void> refresh() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final profile = _settingsController.snapshot.aiGateway;
      if (profile.baseUrl.trim().isNotEmpty) {
        final synced = await _settingsController.syncAiGatewayCatalog(profile);
        _items = _modelsFromProfile(synced);
      } else if (_runtime.isConnected) {
        _items = await _runtime.listModels();
      } else {
        _items = _modelsFromProfile(profile);
      }
    } catch (error) {
      _error = error.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  List<GatewayModelSummary> _modelsFromProfile(AiGatewayProfile profile) {
    final selected = profile.selectedModels
        .where(profile.availableModels.contains)
        .toList(growable: false);
    final candidates = selected.isNotEmpty
        ? selected
        : profile.availableModels.take(5).toList(growable: false);
    return candidates
        .map(
          (item) => GatewayModelSummary(
            id: item,
            name: item,
            provider: 'AI Gateway',
            contextWindow: null,
            maxOutputTokens: null,
          ),
        )
        .toList(growable: false);
  }
}

class CronJobsController extends ChangeNotifier {
  CronJobsController(this._runtime);

  final GatewayRuntime _runtime;

  List<GatewayCronJobSummary> _items = const <GatewayCronJobSummary>[];
  bool _loading = false;
  String? _error;

  List<GatewayCronJobSummary> get items => _items;
  bool get loading => _loading;
  String? get error => _error;

  Future<void> refresh() async {
    if (!_runtime.isConnected) {
      _items = const <GatewayCronJobSummary>[];
      _error = null;
      notifyListeners();
      return;
    }
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _items = await _runtime.listCronJobs();
    } catch (error) {
      _error = error.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}

class DevicesController extends ChangeNotifier {
  DevicesController(this._runtime);

  final GatewayRuntime _runtime;

  GatewayDevicePairingList _items = const GatewayDevicePairingList.empty();
  bool _loading = false;
  String? _error;

  GatewayDevicePairingList get items => _items;
  bool get loading => _loading;
  String? get error => _error;

  Future<void> refresh({bool quiet = false}) async {
    if (!_runtime.isConnected) {
      _items = const GatewayDevicePairingList.empty();
      if (!quiet) {
        _error = null;
      }
      notifyListeners();
      return;
    }
    if (_loading) {
      return;
    }
    _loading = true;
    if (!quiet) {
      _error = null;
    }
    notifyListeners();
    try {
      _items = await _runtime.listDevicePairing();
    } catch (error) {
      if (!quiet) {
        _error = error.toString();
      }
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> approve(String requestId) async {
    _error = null;
    notifyListeners();
    try {
      await _runtime.approveDevicePairing(requestId);
      await refresh(quiet: true);
    } catch (error) {
      _error = error.toString();
      notifyListeners();
    }
  }

  Future<void> reject(String requestId) async {
    _error = null;
    notifyListeners();
    try {
      await _runtime.rejectDevicePairing(requestId);
      await refresh(quiet: true);
    } catch (error) {
      _error = error.toString();
      notifyListeners();
    }
  }

  Future<void> remove(String deviceId) async {
    _error = null;
    notifyListeners();
    try {
      await _runtime.removePairedDevice(deviceId);
      await refresh(quiet: true);
    } catch (error) {
      _error = error.toString();
      notifyListeners();
    }
  }

  Future<String?> rotateToken({
    required String deviceId,
    required String role,
    List<String> scopes = const <String>[],
  }) async {
    _error = null;
    notifyListeners();
    try {
      final token = await _runtime.rotateDeviceToken(
        deviceId: deviceId,
        role: role,
        scopes: scopes,
      );
      await refresh(quiet: true);
      return token;
    } catch (error) {
      _error = error.toString();
      notifyListeners();
      return null;
    }
  }

  Future<void> revokeToken({
    required String deviceId,
    required String role,
  }) async {
    _error = null;
    notifyListeners();
    try {
      await _runtime.revokeDeviceToken(deviceId: deviceId, role: role);
      await refresh(quiet: true);
    } catch (error) {
      _error = error.toString();
      notifyListeners();
    }
  }

  void clear() {
    _items = const GatewayDevicePairingList.empty();
    _error = null;
    _loading = false;
    notifyListeners();
  }
}

class DerivedTasksController extends ChangeNotifier {
  List<DerivedTaskItem> _queue = const <DerivedTaskItem>[];
  List<DerivedTaskItem> _running = const <DerivedTaskItem>[];
  List<DerivedTaskItem> _history = const <DerivedTaskItem>[];
  List<DerivedTaskItem> _failed = const <DerivedTaskItem>[];
  List<DerivedTaskItem> _scheduled = const <DerivedTaskItem>[];

  List<DerivedTaskItem> get queue => _queue;
  List<DerivedTaskItem> get running => _running;
  List<DerivedTaskItem> get history => _history;
  List<DerivedTaskItem> get failed => _failed;
  List<DerivedTaskItem> get scheduled => _scheduled;

  int get totalCount =>
      _queue.length + _running.length + _history.length + _failed.length;

  void recompute({
    required List<GatewaySessionSummary> sessions,
    required List<GatewayCronJobSummary> cronJobs,
    required String currentSessionKey,
    required bool hasPendingRun,
    required String activeAgentName,
  }) {
    final sorted = sessions.toList(growable: false)
      ..sort(
        (left, right) =>
            (right.updatedAtMs ?? 0).compareTo(left.updatedAtMs ?? 0),
      );
    final queue = <DerivedTaskItem>[];
    final running = <DerivedTaskItem>[];
    final history = <DerivedTaskItem>[];
    final failed = <DerivedTaskItem>[];
    for (final session in sorted) {
      final item = DerivedTaskItem(
        id: session.key,
        title: session.label,
        owner: activeAgentName,
        status: _statusForSession(
          session: session,
          currentSessionKey: currentSessionKey,
          hasPendingRun: hasPendingRun,
        ),
        surface: session.surface ?? session.kind ?? 'Assistant',
        startedAtLabel: _timeLabel(session.updatedAtMs),
        durationLabel: _durationLabel(session.updatedAtMs),
        summary:
            session.lastMessagePreview ?? session.subject ?? 'Session activity',
        sessionKey: session.key,
      );
      switch (item.status) {
        case 'Running':
          running.add(item);
        case 'Failed':
          failed.add(item);
        case 'Queued':
          queue.add(item);
        default:
          history.add(item);
      }
    }
    _queue = queue;
    _running = running;
    _history = history;
    _failed = failed;
    _scheduled = cronJobs
        .map(
          (job) => DerivedTaskItem(
            id: job.id,
            title: job.name,
            owner: job.agentId?.trim().isNotEmpty == true
                ? job.agentId!
                : activeAgentName,
            status: job.enabled ? 'Scheduled' : 'Disabled',
            surface: 'Cron',
            startedAtLabel: _timeLabel(job.nextRunAtMs?.toDouble()),
            durationLabel: job.scheduleLabel,
            summary:
                job.description ??
                job.lastError ??
                job.lastStatus ??
                'Scheduled automation',
            sessionKey: 'cron:${job.id}',
          ),
        )
        .toList(growable: false);
    notifyListeners();
  }

  String _statusForSession({
    required GatewaySessionSummary session,
    required String currentSessionKey,
    required bool hasPendingRun,
  }) {
    if (session.abortedLastRun == true) {
      return 'Failed';
    }
    if (hasPendingRun && matchesSessionKey(session.key, currentSessionKey)) {
      return 'Running';
    }
    if ((session.lastMessagePreview ?? '').isEmpty) {
      return 'Queued';
    }
    return 'Open';
  }

  String _timeLabel(double? timestampMs) {
    if (timestampMs == null) {
      return 'Unknown';
    }
    final date = DateTime.fromMillisecondsSinceEpoch(timestampMs.toInt());
    return '${date.month}/${date.day} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _durationLabel(double? timestampMs) {
    if (timestampMs == null) {
      return 'n/a';
    }
    final delta = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(timestampMs.toInt()),
    );
    if (delta.inMinutes < 1) {
      return 'just now';
    }
    if (delta.inHours < 1) {
      return '${delta.inMinutes}m ago';
    }
    if (delta.inDays < 1) {
      return '${delta.inHours}h ago';
    }
    return '${delta.inDays}d ago';
  }
}

String normalizeMainSessionKey(String? value) {
  final trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? 'main' : trimmed;
}

String makeAgentSessionKey({required String agentId, required String baseKey}) {
  final trimmedAgent = agentId.trim();
  final trimmedBase = baseKey.trim();
  if (trimmedAgent.isEmpty) {
    return normalizeMainSessionKey(trimmedBase);
  }
  return 'agent:$trimmedAgent:${normalizeMainSessionKey(trimmedBase)}';
}

bool matchesSessionKey(String incoming, String current) {
  final left = incoming.trim().toLowerCase();
  final right = current.trim().toLowerCase();
  if (left == right) {
    return true;
  }
  return (left == 'agent:main:main' && right == 'main') ||
      (left == 'main' && right == 'agent:main:main');
}

String encodePrettyJson(Object value) {
  const encoder = JsonEncoder.withIndent('  ');
  return encoder.convert(value);
}

String _ephemeralId() => DateTime.now().microsecondsSinceEpoch.toString();
