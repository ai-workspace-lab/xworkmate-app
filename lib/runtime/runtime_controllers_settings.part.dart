part of 'runtime_controllers.dart';

class SettingsController extends ChangeNotifier {
  SettingsController(this._store);

  final SecureConfigStore _store;
  bool _disposed = false;
  final List<StreamSubscription<FileSystemEvent>> _settingsWatchSubscriptions =
      <StreamSubscription<FileSystemEvent>>[];
  Timer? _settingsReloadDebounce;
  Timer? _settingsPollTimer;

  SettingsSnapshot _snapshot = SettingsSnapshot.defaults();
  String _lastSnapshotJson = SettingsSnapshot.defaults().toJsonString();
  String _lastSettingsFileStamp = '';
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

  @override
  void notifyListeners() {
    if (_disposed) {
      return;
    }
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _settingsReloadDebounce?.cancel();
    _settingsPollTimer?.cancel();
    for (final subscription in _settingsWatchSubscriptions) {
      unawaited(subscription.cancel());
    }
    _settingsWatchSubscriptions.clear();
    super.dispose();
  }

  Future<void> initialize() async {
    _snapshot = await _store.loadSettingsSnapshot();
    _lastSnapshotJson = _snapshot.toJsonString();
    await _reloadDerivedState();
    await _startSettingsWatcher();
    await _refreshSettingsFileStamp();
    _startSettingsPolling();
    notifyListeners();
  }

  Future<void> refreshDerivedState() async {
    await _reloadDerivedState();
    notifyListeners();
  }

  Future<void> saveSnapshot(SettingsSnapshot snapshot) async {
    _snapshot = snapshot;
    _lastSnapshotJson = _snapshot.toJsonString();
    await _store.saveSettingsSnapshot(snapshot);
    await _refreshSettingsFileStamp();
    await _reloadDerivedState();
    notifyListeners();
  }

  Future<void> resetSnapshot(SettingsSnapshot snapshot) async {
    _snapshot = snapshot;
    _lastSnapshotJson = _snapshot.toJsonString();
    await _refreshSettingsFileStamp();
    await _reloadDerivedState();
    notifyListeners();
  }

  Future<void> saveGatewaySecrets({
    int? profileIndex,
    required String token,
    required String password,
  }) async {
    final trimmedToken = token.trim();
    final trimmedPassword = password.trim();
    if (trimmedToken.isNotEmpty) {
      await _store.saveGatewayToken(trimmedToken, profileIndex: profileIndex);
      await appendAudit(
        SecretAuditEntry(
          timeLabel: _timeLabel(),
          action: 'Updated',
          provider: 'Gateway',
          target: _gatewaySecretTarget('gateway_token', profileIndex),
          module: 'Assistant',
          status: 'Success',
        ),
      );
    }
    if (trimmedPassword.isNotEmpty) {
      await _store.saveGatewayPassword(
        trimmedPassword,
        profileIndex: profileIndex,
      );
      await appendAudit(
        SecretAuditEntry(
          timeLabel: _timeLabel(),
          action: 'Updated',
          provider: 'Gateway',
          target: _gatewaySecretTarget('gateway_password', profileIndex),
          module: 'Assistant',
          status: 'Success',
        ),
      );
    }
    await _reloadDerivedState();
    notifyListeners();
  }

  Future<void> clearGatewaySecrets({
    int? profileIndex,
    bool token = false,
    bool password = false,
  }) async {
    if (token) {
      await _store.clearGatewayToken(profileIndex: profileIndex);
      await appendAudit(
        SecretAuditEntry(
          timeLabel: _timeLabel(),
          action: 'Cleared',
          provider: 'Gateway',
          target: _gatewaySecretTarget('gateway_token', profileIndex),
          module: 'Assistant',
          status: 'Success',
        ),
      );
    }
    if (password) {
      await _store.clearGatewayPassword(profileIndex: profileIndex);
      await appendAudit(
        SecretAuditEntry(
          timeLabel: _timeLabel(),
          action: 'Cleared',
          provider: 'Gateway',
          target: _gatewaySecretTarget('gateway_password', profileIndex),
          module: 'Assistant',
          status: 'Success',
        ),
      );
    }
    await _reloadDerivedState();
    notifyListeners();
  }

  Future<String> loadGatewayToken({int? profileIndex}) async {
    return (await _store.loadGatewayToken(
          profileIndex: profileIndex,
        ))?.trim() ??
        '';
  }

  Future<String> loadGatewayPassword({int? profileIndex}) async {
    return (await _store.loadGatewayPassword(
          profileIndex: profileIndex,
        ))?.trim() ??
        '';
  }

  bool hasStoredGatewayTokenForProfile(int profileIndex) =>
      _secureRefs.containsKey(SecretStore.gatewayTokenRefKey(profileIndex)) ||
      _secureRefs.containsKey('gateway_token');

  bool hasStoredGatewayPasswordForProfile(int profileIndex) =>
      _secureRefs.containsKey(
        SecretStore.gatewayPasswordRefKey(profileIndex),
      ) ||
      _secureRefs.containsKey('gateway_password');

  String? storedGatewayTokenMaskForProfile(int profileIndex) =>
      _secureRefs[SecretStore.gatewayTokenRefKey(profileIndex)] ??
      _secureRefs['gateway_token'];

  String? storedGatewayPasswordMaskForProfile(int profileIndex) =>
      _secureRefs[SecretStore.gatewayPasswordRefKey(profileIndex)] ??
      _secureRefs['gateway_password'];

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
        provider: 'LLM API',
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
    return testOllamaConnectionDraft(
      cloud: cloud,
      localConfig: _snapshot.ollamaLocal,
      cloudConfig: _snapshot.ollamaCloud,
    );
  }

  Future<String> testOllamaConnectionDraft({
    required bool cloud,
    required OllamaLocalConfig localConfig,
    required OllamaCloudConfig cloudConfig,
    String apiKeyOverride = '',
  }) async {
    final base = cloud
        ? cloudConfig.baseUrl.trim()
        : localConfig.endpoint.trim();
    if (base.isEmpty) {
      final message = 'Missing endpoint';
      _ollamaStatus = message;
      notifyListeners();
      return message;
    }
    final cloudApiKey = apiKeyOverride.trim().isNotEmpty
        ? apiKeyOverride.trim()
        : (await _store.loadOllamaCloudApiKey())?.trim() ?? '';
    try {
      final uri = Uri.parse(
        cloud ? base : '$base${base.endsWith('/') ? '' : '/'}api/tags',
      );
      final response = await _simpleGet(
        uri,
        headers: cloud
            ? <String, String>{
                if (cloudApiKey.isNotEmpty)
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
    return testVaultConnectionDraft(_snapshot.vault);
  }

  Future<String> testVaultConnectionDraft(
    VaultConfig profile, {
    String tokenOverride = '',
  }) async {
    final address = profile.address.trim();
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
        if (profile.namespace.trim().isNotEmpty)
          'X-Vault-Namespace': profile.namespace.trim(),
      };
      final token = tokenOverride.trim().isNotEmpty
          ? tokenOverride.trim()
          : (await _store.loadVaultToken())?.trim() ?? '';
      if (token.trim().isNotEmpty) {
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
        syncMessage: 'Missing LLM API Endpoint',
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
        syncMessage: 'Missing LLM API Token',
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
        message: 'Missing LLM API Endpoint',
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
        message: 'Missing LLM API Token',
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
        provider: 'LLM API',
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
      return 'LLM API';
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
                'LLM API',
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
      return 'Unable to reach the LLM API';
    }
    if (error is HandshakeException) {
      return 'TLS handshake failed';
    }
    if (error is TimeoutException) {
      return 'Connection timed out';
    }
    if (error is FormatException) {
      return 'LLM API returned invalid JSON';
    }
    return 'Failed: $error';
  }

  String _aiGatewayHttpErrorLabel(int statusCode, String detail) {
    final base = switch (statusCode) {
      400 => 'Bad request (400)',
      401 => 'Authentication failed (401)',
      403 => 'Access denied (403)',
      404 => 'Model catalog endpoint not found (404)',
      429 => 'Rate limited by LLM API (429)',
      >= 500 => 'LLM API unavailable ($statusCode)',
      _ => 'LLM API responded $statusCode',
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

  String _gatewaySecretTarget(String base, int? profileIndex) {
    if (profileIndex == null) {
      return base;
    }
    return '$base.$profileIndex';
  }

  Future<void> _startSettingsWatcher() async {
    for (final subscription in _settingsWatchSubscriptions) {
      await subscription.cancel();
    }
    _settingsWatchSubscriptions.clear();
    final files = await _store.resolvedSettingsFiles();
    final directories = await _store.resolvedSettingsWatchDirectories();
    void scheduleReload() {
      _settingsReloadDebounce?.cancel();
      _settingsReloadDebounce = Timer(
        const Duration(milliseconds: 160),
        () => unawaited(_reloadSettingsFromDiskIfChanged()),
      );
    }

    for (final file in files) {
      try {
        if (await file.exists()) {
          _settingsWatchSubscriptions.add(
            file.watch().listen((_) {
              scheduleReload();
            }),
          );
        }
      } catch (_) {
        // Best effort only. Directory watch below remains as a fallback.
      }
    }
    for (final directory in directories) {
      try {
        if (!await directory.exists()) {
          await directory.create(recursive: true);
        }
        _settingsWatchSubscriptions.add(
          directory.watch().listen((_) {
            scheduleReload();
          }),
        );
      } catch (_) {
        // Best effort only. Missing watch support should not block runtime.
      }
    }
  }

  Future<void> _reloadSettingsFromDiskIfChanged() async {
    if (_disposed) {
      return;
    }
    final nextStamp = await _resolveStableSettingsFileStamp();
    if (nextStamp == _lastSettingsFileStamp) {
      return;
    }
    final reload = await _store.reloadSettingsSnapshotResult();
    if (!reload.applied) {
      return;
    }
    _lastSettingsFileStamp = nextStamp;
    final next = reload.snapshot;
    final nextJson = next.toJsonString();
    if (nextJson == _lastSnapshotJson) {
      return;
    }
    _snapshot = next;
    _lastSnapshotJson = nextJson;
    await _reloadDerivedState();
    notifyListeners();
  }

  void _startSettingsPolling() {
    _settingsPollTimer?.cancel();
    _settingsPollTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(_pollSettingsFileChanges());
    });
  }

  Future<void> _pollSettingsFileChanges() async {
    if (_disposed) {
      return;
    }
    final previousStamp = _lastSettingsFileStamp;
    final nextStamp = await _computeSettingsFileStamp();
    if (nextStamp == previousStamp) {
      return;
    }
    await _reloadSettingsFromDiskIfChanged();
  }

  Future<void> _refreshSettingsFileStamp() async {
    _lastSettingsFileStamp = await _computeSettingsFileStamp();
  }

  Future<String> _resolveStableSettingsFileStamp() async {
    var current = await _computeSettingsFileStamp();
    for (var attempt = 0; attempt < 4; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      final next = await _computeSettingsFileStamp();
      if (next == current) {
        return next;
      }
      current = next;
    }
    return current;
  }

  Future<String> _computeSettingsFileStamp() async {
    final files = await _store.resolvedSettingsFiles();
    final buffer = StringBuffer();
    for (final file in files) {
      buffer.write(file.path);
      if (await file.exists()) {
        final stat = await file.stat();
        buffer
          ..write(':')
          ..write(stat.modified.millisecondsSinceEpoch)
          ..write(':')
          ..write(stat.size);
      } else {
        buffer.write(':missing');
      }
      buffer.write('|');
    }
    return buffer.toString();
  }
}
