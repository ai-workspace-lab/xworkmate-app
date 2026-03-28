part of 'gateway_runtime.dart';

class GatewayRuntime extends ChangeNotifier with _GatewayRuntimeHelpers {
  GatewayRuntime({
    required SecureConfigStore store,
    required DeviceIdentityStore identityStore,
  }) : _store = store,
       _identityStore = identityStore;

  final SecureConfigStore _store;
  final DeviceIdentityStore _identityStore;
  final StreamController<GatewayPushEvent> _events =
      StreamController<GatewayPushEvent>.broadcast();
  final Map<String, Completer<_RpcResponse>> _pending =
      <String, Completer<_RpcResponse>>{};
  final List<RuntimeLogEntry> _logs = <RuntimeLogEntry>[];

  IOWebSocketChannel? _channel;
  StreamSubscription<dynamic>? _socketSubscription;
  Timer? _reconnectTimer;
  GatewayConnectionProfile? _desiredProfile;
  bool _manualDisconnect = false;
  bool _suppressReconnect = false;
  int _requestCounter = 0;

  GatewayConnectionSnapshot _snapshot = GatewayConnectionSnapshot.initial(
    mode: GatewayConnectionProfile.defaults().mode,
  );
  RuntimePackageInfo _packageInfo = const RuntimePackageInfo(
    appName: kSystemAppName,
    packageName: 'plus.svc.xworkmate',
    version: kAppVersion,
    buildNumber: kAppBuildNumber,
  );
  RuntimeDeviceInfo _deviceInfo = RuntimeDeviceInfo(
    platform: Platform.operatingSystem,
    platformVersion: '',
    deviceFamily: 'Desktop',
    modelIdentifier: 'unknown',
  );

  GatewayConnectionSnapshot get snapshot => _snapshot;
  RuntimePackageInfo get packageInfo => _packageInfo;
  RuntimeDeviceInfo get deviceInfo => _deviceInfo;
  Stream<GatewayPushEvent> get events => _events.stream;
  List<RuntimeLogEntry> get logs => List<RuntimeLogEntry>.unmodifiable(_logs);
  bool get isConnected => _snapshot.status == RuntimeConnectionStatus.connected;

  void clearLogs() {
    if (_logs.isEmpty) {
      return;
    }
    _logs.clear();
    notifyListeners();
  }

  @visibleForTesting
  void addRuntimeLogForTest({
    required String level,
    required String category,
    required String message,
  }) {
    _appendLog(this, level, category, message);
  }

  Future<void> initialize() async {
    await _store.initialize();
    _packageInfo = await _loadPackageInfo();
    _deviceInfo = await _loadDeviceInfo();
    notifyListeners();
  }

  Future<void> connectProfile(
    GatewayConnectionProfile profile, {
    int? profileIndex,
    String authTokenOverride = '',
    String authPasswordOverride = '',
  }) async {
    _desiredProfile = profile;
    _manualDisconnect = false;
    _suppressReconnect = false;
    await _closeSocket(this);

    final endpoint = _resolveEndpoint(profile);
    final setupPayload = decodeGatewaySetupCode(profile.setupCode);
    final storedToken =
        (await _store.loadGatewayToken(profileIndex: profileIndex))?.trim() ??
        '';
    final storedPassword =
        (await _store.loadGatewayPassword(
          profileIndex: profileIndex,
        ))?.trim() ??
        '';
    final explicitToken = authTokenOverride.trim();
    final explicitPassword = authPasswordOverride.trim();
    final sharedTokenSource = explicitToken.isNotEmpty
        ? 'shared:form'
        : storedToken.isNotEmpty
        ? 'shared:store'
        : (setupPayload?.token.trim().isNotEmpty ?? false)
        ? 'shared:setup-code'
        : null;
    final sharedToken = explicitToken.isNotEmpty
        ? explicitToken
        : storedToken.isNotEmpty
        ? storedToken
        : (setupPayload?.token.trim() ?? '');
    final passwordSource = explicitPassword.isNotEmpty
        ? 'password:form'
        : storedPassword.isNotEmpty
        ? 'password:store'
        : (setupPayload?.password.trim().isNotEmpty ?? false)
        ? 'password:setup-code'
        : null;
    final password = explicitPassword.isNotEmpty
        ? explicitPassword
        : storedPassword.isNotEmpty
        ? storedPassword
        : (setupPayload?.password.trim() ?? '');
    final identity = await _identityStore.loadOrCreate();
    final storedDeviceToken =
        (await _store.loadDeviceToken(
          deviceId: identity.deviceId,
          role: 'operator',
        ))?.trim() ??
        '';
    final explicitDeviceToken = '';
    final deviceTokenSource = explicitDeviceToken.isNotEmpty
        ? 'device:form'
        : sharedToken.isEmpty && storedDeviceToken.isNotEmpty
        ? 'device:store'
        : null;
    final deviceToken = explicitDeviceToken.isNotEmpty
        ? explicitDeviceToken
        : sharedToken.isEmpty
        ? storedDeviceToken
        : '';
    final authToken = sharedToken.isNotEmpty ? sharedToken : deviceToken;
    final connectAuthMode = sharedToken.isNotEmpty
        ? 'shared-token'
        : deviceToken.isNotEmpty
        ? 'device-token'
        : password.isNotEmpty
        ? 'password'
        : 'none';
    final connectAuthFields = <String>[
      if (authToken.isNotEmpty) 'token',
      if (deviceToken.isNotEmpty) 'deviceToken',
      if (password.isNotEmpty) 'password',
    ];
    final connectAuthSources = <String>[
      ...?sharedTokenSource == null ? null : <String>[sharedTokenSource],
      ...?deviceTokenSource == null ? null : <String>[deviceTokenSource],
      ...?passwordSource == null ? null : <String>[passwordSource],
    ];
    final connectAuthSummary = _connectAuthSummary(
      mode: connectAuthMode,
      fields: connectAuthFields,
      sources: connectAuthSources,
    );
    final usedStoredDeviceTokenOnly =
        sharedToken.isEmpty && deviceToken.isNotEmpty;

    if (endpoint == null) {
      _appendLog(this, 
        'warn',
        'connect',
        'missing endpoint | auth: $connectAuthSummary',
      );
      _snapshot = GatewayConnectionSnapshot.initial(mode: profile.mode)
          .copyWith(
            statusText: 'Missing gateway endpoint',
            lastError: 'Configure setup code or manual host / port first.',
            lastErrorCode: 'MISSING_ENDPOINT',
            deviceId: identity.deviceId,
            connectAuthMode: connectAuthMode,
            connectAuthFields: connectAuthFields,
            connectAuthSources: connectAuthSources,
          );
      notifyListeners();
      return;
    }

    _appendLog(this, 
      'info',
      'connect',
      'attempt ${endpoint.$1}:${endpoint.$2} tls:${endpoint.$3} | auth: $connectAuthSummary',
    );

    _snapshot = GatewayConnectionSnapshot.initial(mode: profile.mode).copyWith(
      status: RuntimeConnectionStatus.connecting,
      statusText: 'Connecting…',
      remoteAddress: '${endpoint.$1}:${endpoint.$2}',
      deviceId: identity.deviceId,
      authRole: 'operator',
      authScopes: kDefaultOperatorConnectScopes,
      connectAuthMode: connectAuthMode,
      connectAuthFields: connectAuthFields,
      connectAuthSources: connectAuthSources,
      hasSharedAuth: sharedToken.isNotEmpty || password.isNotEmpty,
      hasDeviceToken: deviceToken.isNotEmpty,
      clearLastError: true,
      clearLastErrorCode: true,
      clearLastErrorDetailCode: true,
    );
    notifyListeners();

    try {
      final scheme = endpoint.$3 ? 'wss' : 'ws';
      _channel = IOWebSocketChannel.connect(
        Uri.parse('$scheme://${endpoint.$1}:${endpoint.$2}'),
        pingInterval: const Duration(seconds: 30),
        connectTimeout: const Duration(seconds: 10),
      );
      final challenge = Completer<String>();
      _socketSubscription = _channel!.stream.listen(
        (dynamic raw) => _handleIncoming(this, raw, challenge),
        onError: (Object error, StackTrace stackTrace) {
          _handleSocketFailure(this, error.toString());
        },
        onDone: () {
          _handleSocketClosed(this);
        },
        cancelOnError: true,
      );

      final nonce = await challenge.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () => throw GatewayRuntimeException(
          'connect challenge timeout',
          code: 'CONNECT_CHALLENGE_TIMEOUT',
        ),
      );
      final connectResult = await _requestRaw(this, 
        'connect',
        params: await _buildConnectParams(this, 
          profile: profile,
          identity: identity,
          nonce: nonce,
          authToken: authToken,
          authDeviceToken: deviceToken,
          authPassword: password,
        ),
        timeout: const Duration(seconds: 12),
      );

      final payload = asMap(connectResult.payload);
      final auth = asMap(payload['auth']);
      final snapshot = asMap(payload['snapshot']);
      final sessionDefaults = asMap(snapshot['sessionDefaults']);
      final server = asMap(payload['server']);
      final returnedDeviceToken = stringValue(auth['deviceToken']);
      if (returnedDeviceToken != null && returnedDeviceToken.isNotEmpty) {
        await _store.saveDeviceToken(
          deviceId: identity.deviceId,
          role: stringValue(auth['role']) ?? 'operator',
          token: returnedDeviceToken,
        );
        _appendLog(this, 
          'info',
          'auth',
          'stored device token for role ${stringValue(auth['role']) ?? 'operator'}',
        );
      }
      final negotiatedRole = stringValue(auth['role']) ?? 'operator';
      final negotiatedScopes = stringList(auth['scopes']);
      _snapshot = _snapshot.copyWith(
        status: RuntimeConnectionStatus.connected,
        statusText: 'Connected',
        serverName: stringValue(server['host']),
        remoteAddress: '${endpoint.$1}:${endpoint.$2}',
        mainSessionKey:
            stringValue(sessionDefaults['mainSessionKey']) ?? 'main',
        lastConnectedAtMs: DateTime.now().millisecondsSinceEpoch,
        authRole: negotiatedRole,
        authScopes: negotiatedScopes,
        connectAuthMode: connectAuthMode,
        connectAuthFields: connectAuthFields,
        connectAuthSources: connectAuthSources,
        hasSharedAuth: sharedToken.isNotEmpty || password.isNotEmpty,
        hasDeviceToken:
            (returnedDeviceToken != null && returnedDeviceToken.isNotEmpty) ||
            deviceToken.isNotEmpty,
        clearLastError: true,
        clearLastErrorCode: true,
        clearLastErrorDetailCode: true,
      );
      _appendLog(this, 
        'info',
        'connect',
        'connected ${endpoint.$1}:${endpoint.$2} | role: $negotiatedRole | scopes: ${negotiatedScopes.length}',
      );
      notifyListeners();
    } catch (error) {
      final runtimeError = error is GatewayRuntimeException ? error : null;
      if (runtimeError?.detailCode == 'AUTH_DEVICE_TOKEN_MISMATCH' &&
          deviceToken.isNotEmpty &&
          sharedToken.isEmpty) {
        await _store.clearDeviceToken(
          deviceId: identity.deviceId,
          role: 'operator',
        );
      } else if (usedStoredDeviceTokenOnly &&
          _isPairingRequiredError(
            runtimeError?.code,
            runtimeError?.detailCode,
          )) {
        await _store.clearDeviceToken(
          deviceId: identity.deviceId,
          role: 'operator',
        );
        _appendLog(this, 
          'warn',
          'auth',
          'cleared stale device token after pairing-required response',
        );
      }
      if (!_shouldAutoReconnect(runtimeError)) {
        _suppressReconnect = true;
        _appendLog(this, 
          'warn',
          'socket',
          'auto reconnect suppressed | code: ${runtimeError?.code ?? 'unknown'} | detail: ${runtimeError?.detailCode ?? 'none'}',
        );
      }
      await _closeSocket(this);
      _appendLog(this, 
        'error',
        'connect',
        'failed ${endpoint.$1}:${endpoint.$2} | code: ${runtimeError?.code ?? 'unknown'} | detail: ${runtimeError?.detailCode ?? 'none'} | message: ${error.toString()}',
      );
      _snapshot = _snapshot.copyWith(
        status: RuntimeConnectionStatus.error,
        statusText: 'Connection failed',
        lastError: error.toString(),
        lastErrorCode: runtimeError?.code,
        lastErrorDetailCode: runtimeError?.detailCode,
        connectAuthMode: connectAuthMode,
        connectAuthFields: connectAuthFields,
        connectAuthSources: connectAuthSources,
        hasSharedAuth: sharedToken.isNotEmpty || password.isNotEmpty,
        hasDeviceToken: deviceToken.isNotEmpty,
      );
      notifyListeners();
      if (_shouldAutoReconnect(runtimeError)) {
        _appendLog(this, 
          'warn',
          'socket',
          'scheduling reconnect in 2s | code: ${runtimeError?.code ?? 'unknown'}',
        );
        _scheduleReconnect(this);
      }
      rethrow;
    }
  }

  Future<void> disconnect({bool clearDesiredProfile = true}) async {
    _manualDisconnect = true;
    _appendLog(this, 'info', 'connect', 'manual disconnect');
    if (clearDesiredProfile) {
      _desiredProfile = null;
    }
    _reconnectTimer?.cancel();
    await _closeSocket(this);
    _snapshot = GatewayConnectionSnapshot.initial(mode: _snapshot.mode)
        .copyWith(
          statusText: 'Offline',
          deviceId: _snapshot.deviceId,
          authRole: _snapshot.authRole,
          authScopes: _snapshot.authScopes,
          hasSharedAuth: _snapshot.hasSharedAuth,
          hasDeviceToken: _snapshot.hasDeviceToken,
        );
    notifyListeners();
  }

  Future<Map<String, dynamic>> health() async {
    final payload = asMap(await request('health'));
    _snapshot = _snapshot.copyWith(healthPayload: payload);
    _appendLog(this, 'debug', 'health', 'health snapshot refreshed');
    notifyListeners();
    return payload;
  }

  Future<Map<String, dynamic>> status() async {
    final payload = asMap(await request('status'));
    _snapshot = _snapshot.copyWith(statusPayload: payload);
    _appendLog(this, 'debug', 'health', 'status snapshot refreshed');
    notifyListeners();
    return payload;
  }

  Future<List<GatewayAgentSummary>> listAgents() async {
    final payload = asMap(
      await request('agents.list', params: const <String, dynamic>{}),
    );
    final agents = asList(payload['agents'])
        .map((item) {
          final map = asMap(item);
          final identity = asMap(map['identity']);
          return GatewayAgentSummary(
            id: stringValue(map['id']) ?? 'unknown',
            name:
                stringValue(map['name']) ??
                stringValue(identity['name']) ??
                'Agent',
            emoji: stringValue(identity['emoji']) ?? '·',
            theme: stringValue(identity['theme']) ?? 'default',
          );
        })
        .toList(growable: false);
    if (_snapshot.mainSessionKey == null ||
        _snapshot.mainSessionKey!.trim().isEmpty) {
      _snapshot = _snapshot.copyWith(
        mainSessionKey: stringValue(payload['mainKey']) ?? 'main',
      );
      notifyListeners();
    }
    return agents;
  }

  Future<List<GatewaySessionSummary>> listSessions({
    String? agentId,
    int limit = 24,
  }) async {
    final payload = asMap(
      await request(
        'sessions.list',
        params: <String, dynamic>{
          'includeGlobal': true,
          'includeUnknown': false,
          'includeDerivedTitles': true,
          'includeLastMessage': true,
          'limit': limit,
          if (agentId != null && agentId.trim().isNotEmpty)
            'agentId': agentId.trim(),
        },
      ),
    );
    return asList(payload['sessions'])
        .map((item) {
          final map = asMap(item);
          return GatewaySessionSummary(
            key: stringValue(map['key']) ?? 'main',
            kind: stringValue(map['kind']),
            displayName:
                stringValue(map['displayName']) ?? stringValue(map['label']),
            surface: stringValue(map['surface']),
            subject: stringValue(map['subject']),
            room: stringValue(map['room']),
            space: stringValue(map['space']),
            updatedAtMs: doubleValue(map['updatedAt']),
            sessionId: stringValue(map['sessionId']),
            systemSent: boolValue(map['systemSent']),
            abortedLastRun: boolValue(map['abortedLastRun']),
            thinkingLevel: stringValue(map['thinkingLevel']),
            verboseLevel: stringValue(map['verboseLevel']),
            inputTokens: intValue(map['inputTokens']),
            outputTokens: intValue(map['outputTokens']),
            totalTokens: intValue(map['totalTokens']),
            model: stringValue(map['model']),
            contextTokens: intValue(map['contextTokens']),
            derivedTitle: stringValue(map['derivedTitle']),
            lastMessagePreview: stringValue(map['lastMessagePreview']),
          );
        })
        .toList(growable: false);
  }

  Future<List<GatewayChatMessage>> loadHistory(
    String sessionKey, {
    int limit = 120,
  }) async {
    final payload = asMap(
      await request(
        'chat.history',
        params: <String, dynamic>{'sessionKey': sessionKey, 'limit': limit},
      ),
    );
    return asList(payload['messages'])
        .map((item) {
          final map = asMap(item);
          return GatewayChatMessage(
            id: _randomId(),
            role: stringValue(map['role']) ?? 'assistant',
            text: extractMessageText(map),
            timestampMs: doubleValue(map['timestamp']),
            toolCallId:
                stringValue(map['toolCallId']) ??
                stringValue(map['tool_call_id']),
            toolName:
                stringValue(map['toolName']) ?? stringValue(map['tool_name']),
            stopReason: stringValue(map['stopReason']),
            pending: false,
            error: false,
          );
        })
        .toList(growable: false);
  }

  Future<String> sendChat({
    required String sessionKey,
    required String message,
    required String thinking,
    List<GatewayChatAttachmentPayload> attachments =
        const <GatewayChatAttachmentPayload>[],
    String? agentId,
    Map<String, dynamic>? metadata,
  }) async {
    final runId = _randomId();
    final payload = asMap(
      await request(
        'chat.send',
        params: <String, dynamic>{
          'sessionKey': sessionKey,
          'message': message,
          'thinking': thinking,
          'timeoutMs': 30000,
          'idempotencyKey': runId,
          if (agentId != null && agentId.trim().isNotEmpty)
            'agentId': agentId.trim(),
          if (metadata != null && metadata.isNotEmpty) 'metadata': metadata,
          if (attachments.isNotEmpty)
            'attachments': attachments
                .map((attachment) => attachment.toJson())
                .toList(growable: false),
        },
        timeout: const Duration(seconds: 35),
      ),
    );
    return stringValue(payload['runId']) ?? runId;
  }

  Future<void> abortChat({
    required String sessionKey,
    required String runId,
  }) async {
    await request(
      'chat.abort',
      params: <String, dynamic>{'sessionKey': sessionKey, 'runId': runId},
      timeout: const Duration(seconds: 10),
    );
  }

  Future<List<GatewayInstanceSummary>> listInstances() async {
    final payload = await request(
      'system-presence',
      params: const <String, dynamic>{},
    );
    return asList(payload)
        .map((item) {
          final map = asMap(item);
          return GatewayInstanceSummary(
            id: stringValue(map['id']) ?? _randomId(),
            host: stringValue(map['host']),
            ip: stringValue(map['ip']),
            version: stringValue(map['version']),
            platform: stringValue(map['platform']),
            deviceFamily: stringValue(map['deviceFamily']),
            modelIdentifier: stringValue(map['modelIdentifier']),
            lastInputSeconds: intValue(map['lastInputSeconds']),
            mode: stringValue(map['mode']),
            reason: stringValue(map['reason']),
            text: stringValue(map['text']) ?? '',
            timestampMs:
                doubleValue(map['ts']) ??
                DateTime.now().millisecondsSinceEpoch.toDouble(),
          );
        })
        .toList(growable: false);
  }

  Future<List<GatewaySkillSummary>> listSkills({String? agentId}) async {
    final payload = asMap(
      await request(
        'skills.status',
        params: <String, dynamic>{
          if (agentId != null && agentId.trim().isNotEmpty)
            'agentId': agentId.trim(),
        },
      ),
    );
    return asList(payload['skills'])
        .map((item) {
          final map = asMap(item);
          return GatewaySkillSummary(
            name: stringValue(map['name']) ?? 'Skill',
            description: stringValue(map['description']) ?? '',
            source: stringValue(map['source']) ?? 'workspace',
            skillKey:
                stringValue(map['skillKey']) ??
                stringValue(map['name']) ??
                'skill',
            primaryEnv: stringValue(map['primaryEnv']),
            eligible: boolValue(map['eligible']) ?? false,
            disabled: boolValue(map['disabled']) ?? false,
            missingBins: stringList(asMap(map['missing'])['bins']),
            missingEnv: stringList(asMap(map['missing'])['env']),
            missingConfig: stringList(asMap(map['missing'])['config']),
          );
        })
        .toList(growable: false);
  }

  Future<List<GatewayConnectorSummary>> listConnectors() async {
    final payload = asMap(
      await request(
        'channels.status',
        params: const <String, dynamic>{'probe': true, 'timeoutMs': 8000},
        timeout: const Duration(seconds: 16),
      ),
    );
    final channelMeta = <String, Map<String, dynamic>>{
      for (final entry in asList(payload['channelMeta']))
        if (stringValue(asMap(entry)['id']) != null)
          stringValue(asMap(entry)['id'])!: asMap(entry),
    };
    final labels = asMap(payload['channelLabels']);
    final detailLabels = asMap(payload['channelDetailLabels']);
    final accounts = asMap(payload['channelAccounts']);
    final order = stringList(payload['channelOrder']);

    final summaries = <GatewayConnectorSummary>[];
    for (final channelId in order) {
      final channelAccounts = asList(accounts[channelId]);
      if (channelAccounts.isEmpty) {
        final meta = channelMeta[channelId] ?? const <String, dynamic>{};
        summaries.add(
          GatewayConnectorSummary(
            id: channelId,
            label:
                stringValue(meta['label']) ??
                stringValue(labels[channelId]) ??
                channelId,
            detailLabel:
                stringValue(meta['detailLabel']) ??
                stringValue(detailLabels[channelId]) ??
                channelId,
            accountName: null,
            configured: false,
            enabled: false,
            running: false,
            connected: false,
            status: 'idle',
            lastError: null,
            meta: const <String>[],
          ),
        );
        continue;
      }
      for (final account in channelAccounts) {
        final map = asMap(account);
        final configured = boolValue(map['configured']) ?? false;
        final enabled = boolValue(map['enabled']) ?? configured;
        final running = boolValue(map['running']) ?? false;
        final connected =
            boolValue(map['connected']) ?? boolValue(map['linked']) ?? false;
        final lastError = stringValue(map['lastError']);
        final status = lastError != null && lastError.trim().isNotEmpty
            ? 'error'
            : connected
            ? 'connected'
            : running
            ? 'running'
            : configured
            ? 'configured'
            : 'idle';
        final mode = stringValue(map['mode']);
        final tokenSource = stringValue(map['tokenSource']);
        final baseUrl = stringValue(map['baseUrl']);
        summaries.add(
          GatewayConnectorSummary(
            id: channelId,
            label:
                stringValue(channelMeta[channelId]?['label']) ??
                stringValue(labels[channelId]) ??
                channelId,
            detailLabel:
                stringValue(channelMeta[channelId]?['detailLabel']) ??
                stringValue(detailLabels[channelId]) ??
                channelId,
            accountName:
                stringValue(map['name']) ?? stringValue(map['accountId']),
            configured: configured,
            enabled: enabled,
            running: running,
            connected: connected,
            status: status,
            lastError: lastError,
            meta: [
              ...?(mode == null ? null : <String>[mode]),
              ...?(tokenSource == null ? null : <String>[tokenSource]),
              ...?(baseUrl == null ? null : <String>[baseUrl]),
            ],
          ),
        );
      }
    }
    return summaries;
  }

  Future<List<GatewayModelSummary>> listModels() async {
    final payload = asMap(
      await request(
        'models.list',
        params: const <String, dynamic>{},
        timeout: const Duration(seconds: 16),
      ),
    );
    return asList(payload['models'])
        .map((item) {
          final map = asMap(item);
          return GatewayModelSummary(
            id: stringValue(map['id']) ?? 'unknown',
            name:
                stringValue(map['name']) ?? stringValue(map['id']) ?? 'unknown',
            provider: stringValue(map['provider']) ?? 'unknown',
            contextWindow: intValue(map['contextWindow']),
            maxOutputTokens: intValue(map['maxOutputTokens']),
          );
        })
        .toList(growable: false);
  }

  Future<List<GatewayCronJobSummary>> listCronJobs() async {
    final payload = asMap(
      await request(
        'cron.list',
        params: const <String, dynamic>{'includeDisabled': true},
        timeout: const Duration(seconds: 16),
      ),
    );
    return asList(payload['jobs'])
        .map((item) {
          final map = asMap(item);
          final state = asMap(map['state']);
          return GatewayCronJobSummary(
            id: stringValue(map['id']) ?? _randomId(),
            name: stringValue(map['name']) ?? 'Untitled job',
            description: stringValue(map['description']),
            enabled: boolValue(map['enabled']) ?? true,
            agentId: stringValue(map['agentId']),
            scheduleLabel: _cronScheduleLabel(asMap(map['schedule'])),
            nextRunAtMs: intValue(state['nextRunAtMs']),
            lastRunAtMs: intValue(state['lastRunAtMs']),
            lastStatus: stringValue(state['lastStatus']),
            lastError: stringValue(state['lastError']),
          );
        })
        .toList(growable: false);
  }

  Future<GatewayDevicePairingList> listDevicePairing() async {
    final payload = asMap(
      await request(
        'device.pair.list',
        params: const <String, dynamic>{},
        timeout: const Duration(seconds: 12),
      ),
    );
    final identity = await _store.loadDeviceIdentity();
    return GatewayDevicePairingList(
      pending: asList(
        payload['pending'],
      ).map((item) => _parsePendingDevice(asMap(item))).toList(growable: false),
      paired: asList(payload['paired'])
          .map(
            (item) => _parsePairedDevice(
              asMap(item),
              currentDeviceId: identity?.deviceId,
            ),
          )
          .toList(growable: false),
    );
  }

  Future<GatewayPairedDevice?> approveDevicePairing(String requestId) async {
    _appendLog(this, 'info', 'pairing', 'approve request $requestId');
    final payload = asMap(
      await request(
        'device.pair.approve',
        params: <String, dynamic>{'requestId': requestId},
        timeout: const Duration(seconds: 12),
      ),
    );
    final identity = await _store.loadDeviceIdentity();
    final device = asMap(payload['device']);
    if (device.isEmpty) {
      return null;
    }
    return _parsePairedDevice(device, currentDeviceId: identity?.deviceId);
  }

  Future<void> rejectDevicePairing(String requestId) async {
    _appendLog(this, 'info', 'pairing', 'reject request $requestId');
    await request(
      'device.pair.reject',
      params: <String, dynamic>{'requestId': requestId},
      timeout: const Duration(seconds: 12),
    );
  }

  Future<void> removePairedDevice(String deviceId) async {
    _appendLog(this, 'info', 'pairing', 'remove device $deviceId');
    await request(
      'device.pair.remove',
      params: <String, dynamic>{'deviceId': deviceId},
      timeout: const Duration(seconds: 12),
    );
  }

  Future<String> rotateDeviceToken({
    required String deviceId,
    required String role,
    List<String> scopes = const <String>[],
  }) async {
    _appendLog(this, 
      'info',
      'token',
      'rotate role token | device: $deviceId | role: $role',
    );
    final payload = asMap(
      await request(
        'device.token.rotate',
        params: <String, dynamic>{
          'deviceId': deviceId,
          'role': role,
          if (scopes.isNotEmpty) 'scopes': scopes,
        },
        timeout: const Duration(seconds: 12),
      ),
    );
    final token = stringValue(payload['token']) ?? '';
    final identity = await _store.loadDeviceIdentity();
    final resolvedRole = stringValue(payload['role']) ?? role;
    if (token.isNotEmpty &&
        identity != null &&
        (stringValue(payload['deviceId']) ?? deviceId) == identity.deviceId) {
      await _store.saveDeviceToken(
        deviceId: identity.deviceId,
        role: resolvedRole,
        token: token,
      );
    }
    return token;
  }

  Future<void> revokeDeviceToken({
    required String deviceId,
    required String role,
  }) async {
    _appendLog(this, 
      'info',
      'token',
      'revoke role token | device: $deviceId | role: $role',
    );
    await request(
      'device.token.revoke',
      params: <String, dynamic>{'deviceId': deviceId, 'role': role},
      timeout: const Duration(seconds: 12),
    );
    final identity = await _store.loadDeviceIdentity();
    if (identity != null && deviceId == identity.deviceId) {
      await _store.clearDeviceToken(deviceId: identity.deviceId, role: role);
    }
  }

  Future<dynamic> request(
    String method, {
    Map<String, dynamic>? params,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (_channel == null || !isConnected) {
      _appendLog(this, 'warn', 'rpc', 'blocked request $method | offline');
      throw GatewayRuntimeException('gateway not connected', code: 'OFFLINE');
    }
    final result = await _requestRaw(this, method, params: params, timeout: timeout);
    return result.payload;
  }

  @override
  void dispose() {
    _events.close();
    _reconnectTimer?.cancel();
    unawaited(_closeSocket(this));
    super.dispose();
  }
}
