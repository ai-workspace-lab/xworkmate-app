import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:web_socket_channel/io.dart';

import '../app/app_metadata.dart';
import 'device_identity_store.dart';
import 'platform_environment.dart';
import 'runtime_models.dart';
import 'secure_config_store.dart';

const kGatewayProtocolVersion = 3;
const kDefaultOperatorConnectScopes = <String>[
  'operator.admin',
  'operator.read',
  'operator.write',
  'operator.approvals',
  'operator.pairing',
];

class GatewayPushEvent {
  const GatewayPushEvent({
    required this.event,
    required this.payload,
    this.sequence,
  });

  final String event;
  final dynamic payload;
  final int? sequence;
}

class GatewayRuntimeException implements Exception {
  GatewayRuntimeException(this.message, {this.code, this.details});

  final String message;
  final String? code;
  final Object? details;

  String? get detailCode => stringValue(asMap(details)['code']);

  @override
  String toString() => code == null ? message : '$code: $message';
}

class GatewayRuntime extends ChangeNotifier {
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
    _appendLog(level, category, message);
  }

  Future<void> initialize() async {
    await _store.initialize();
    _packageInfo = await _loadPackageInfo();
    _deviceInfo = await _loadDeviceInfo();
    notifyListeners();
  }

  Future<void> connectProfile(
    GatewayConnectionProfile profile, {
    String authTokenOverride = '',
    String authPasswordOverride = '',
  }) async {
    _desiredProfile = profile;
    _manualDisconnect = false;
    _suppressReconnect = false;
    await _closeSocket();

    final endpoint = _resolveEndpoint(profile);
    final setupPayload = decodeGatewaySetupCode(profile.setupCode);
    final storedToken = (await _store.loadGatewayToken())?.trim() ?? '';
    final storedPassword = (await _store.loadGatewayPassword())?.trim() ?? '';
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
      _appendLog(
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

    _appendLog(
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
        (dynamic raw) => _handleIncoming(raw, challenge),
        onError: (Object error, StackTrace stackTrace) {
          _handleSocketFailure(error.toString());
        },
        onDone: () {
          _handleSocketClosed();
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
      final connectResult = await _requestRaw(
        'connect',
        params: await _buildConnectParams(
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
        _appendLog(
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
      _appendLog(
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
        _appendLog(
          'warn',
          'auth',
          'cleared stale device token after pairing-required response',
        );
      }
      if (!_shouldAutoReconnect(runtimeError)) {
        _suppressReconnect = true;
        _appendLog(
          'warn',
          'socket',
          'auto reconnect suppressed | code: ${runtimeError?.code ?? 'unknown'} | detail: ${runtimeError?.detailCode ?? 'none'}',
        );
      }
      await _closeSocket();
      _appendLog(
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
        _appendLog(
          'warn',
          'socket',
          'scheduling reconnect in 2s | code: ${runtimeError?.code ?? 'unknown'}',
        );
        _scheduleReconnect();
      }
      rethrow;
    }
  }

  Future<void> disconnect({bool clearDesiredProfile = true}) async {
    _manualDisconnect = true;
    _appendLog('info', 'connect', 'manual disconnect');
    if (clearDesiredProfile) {
      _desiredProfile = null;
    }
    _reconnectTimer?.cancel();
    await _closeSocket();
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
    _appendLog('debug', 'health', 'health snapshot refreshed');
    notifyListeners();
    return payload;
  }

  Future<Map<String, dynamic>> status() async {
    final payload = asMap(await request('status'));
    _snapshot = _snapshot.copyWith(statusPayload: payload);
    _appendLog('debug', 'health', 'status snapshot refreshed');
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
    _appendLog('info', 'pairing', 'approve request $requestId');
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
    _appendLog('info', 'pairing', 'reject request $requestId');
    await request(
      'device.pair.reject',
      params: <String, dynamic>{'requestId': requestId},
      timeout: const Duration(seconds: 12),
    );
  }

  Future<void> removePairedDevice(String deviceId) async {
    _appendLog('info', 'pairing', 'remove device $deviceId');
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
    _appendLog(
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
    _appendLog(
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
      _appendLog('warn', 'rpc', 'blocked request $method | offline');
      throw GatewayRuntimeException('gateway not connected', code: 'OFFLINE');
    }
    final result = await _requestRaw(method, params: params, timeout: timeout);
    return result.payload;
  }

  @override
  void dispose() {
    _events.close();
    _reconnectTimer?.cancel();
    unawaited(_closeSocket());
    super.dispose();
  }

  Future<_RpcResponse> _requestRaw(
    String method, {
    Map<String, dynamic>? params,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final channel = _channel;
    if (channel == null) {
      throw GatewayRuntimeException('gateway not connected', code: 'OFFLINE');
    }
    final id = '${DateTime.now().microsecondsSinceEpoch}-${_requestCounter++}';
    final completer = Completer<_RpcResponse>();
    _pending[id] = completer;
    final frame = <String, dynamic>{
      'type': 'req',
      'id': id,
      'method': method,
      ...?params == null ? null : <String, dynamic>{'params': params},
    };
    channel.sink.add(jsonEncode(frame));
    try {
      return await completer.future.timeout(
        timeout,
        onTimeout: () => throw GatewayRuntimeException(
          '$method request timeout',
          code: 'RPC_TIMEOUT',
        ),
      );
    } finally {
      _pending.remove(id);
    }
  }

  GatewayPendingDevice _parsePendingDevice(Map<String, dynamic> map) {
    return GatewayPendingDevice(
      requestId: stringValue(map['requestId']) ?? _randomId(),
      deviceId: stringValue(map['deviceId']) ?? 'unknown-device',
      displayName: stringValue(map['displayName']),
      role: stringValue(map['role']),
      scopes: stringList(map['scopes']),
      remoteIp: stringValue(map['remoteIp']),
      isRepair: boolValue(map['isRepair']) ?? false,
      requestedAtMs: intValue(map['ts']),
    );
  }

  GatewayPairedDevice _parsePairedDevice(
    Map<String, dynamic> map, {
    String? currentDeviceId,
  }) {
    return GatewayPairedDevice(
      deviceId: stringValue(map['deviceId']) ?? 'unknown-device',
      displayName: stringValue(map['displayName']),
      roles: stringList(map['roles']),
      scopes: stringList(map['scopes']),
      remoteIp: stringValue(map['remoteIp']),
      tokens: asList(
        map['tokens'],
      ).map((item) => _parseTokenSummary(asMap(item))).toList(growable: false),
      createdAtMs: intValue(map['createdAtMs']),
      approvedAtMs: intValue(map['approvedAtMs']),
      currentDevice:
          currentDeviceId != null &&
          currentDeviceId.isNotEmpty &&
          currentDeviceId == stringValue(map['deviceId']),
    );
  }

  GatewayDeviceTokenSummary _parseTokenSummary(Map<String, dynamic> map) {
    return GatewayDeviceTokenSummary(
      role: stringValue(map['role']) ?? 'operator',
      scopes: stringList(map['scopes']),
      createdAtMs: intValue(map['createdAtMs']),
      rotatedAtMs: intValue(map['rotatedAtMs']),
      revokedAtMs: intValue(map['revokedAtMs']),
      lastUsedAtMs: intValue(map['lastUsedAtMs']),
    );
  }

  Future<Map<String, dynamic>> _buildConnectParams({
    required GatewayConnectionProfile profile,
    required LocalDeviceIdentity identity,
    required String nonce,
    required String authToken,
    required String authDeviceToken,
    required String authPassword,
  }) async {
    final clientId = _resolveClientId();
    final clientMode = 'ui';
    final signedAtMs = DateTime.now().millisecondsSinceEpoch;
    final signaturePayload = _identityStore.buildDeviceAuthPayloadV3(
      deviceId: identity.deviceId,
      clientId: clientId,
      clientMode: clientMode,
      role: 'operator',
      scopes: kDefaultOperatorConnectScopes,
      signedAtMs: signedAtMs,
      token: authToken,
      nonce: nonce,
      platform: _deviceInfo.platformLabel,
      deviceFamily: _deviceInfo.deviceFamily,
    );
    final signature = await _identityStore.signPayload(
      identity: identity,
      payload: signaturePayload,
    );

    return <String, dynamic>{
      'minProtocol': kGatewayProtocolVersion,
      'maxProtocol': kGatewayProtocolVersion,
      'client': <String, dynamic>{
        'id': clientId,
        'displayName': '$kSystemAppName ${_deviceInfo.deviceFamily}',
        'version': _packageInfo.version,
        'platform': _deviceInfo.platformLabel,
        'deviceFamily': _deviceInfo.deviceFamily,
        'modelIdentifier': _deviceInfo.modelIdentifier,
        'mode': clientMode,
        'instanceId':
            '$clientId-${identity.deviceId.substring(0, min(8, identity.deviceId.length))}',
      },
      'caps': const <String>['tool-events'],
      'commands': const <String>[],
      'permissions': const <String, bool>{},
      'role': 'operator',
      'scopes': kDefaultOperatorConnectScopes,
      if (authToken.isNotEmpty ||
          authDeviceToken.isNotEmpty ||
          authPassword.isNotEmpty)
        'auth': <String, dynamic>{
          if (authToken.isNotEmpty) 'token': authToken,
          if (authDeviceToken.isNotEmpty) 'deviceToken': authDeviceToken,
          if (authPassword.isNotEmpty) 'password': authPassword,
        },
      'locale': Platform.localeName,
      'userAgent': '$kSystemAppName/$_packageInfo.version',
      'device': <String, dynamic>{
        'id': identity.deviceId,
        'publicKey': identity.publicKeyBase64Url,
        'signature': signature,
        'signedAt': signedAtMs,
        'nonce': nonce,
      },
    };
  }

  (String, int, bool)? _resolveEndpoint(GatewayConnectionProfile profile) {
    final payload = decodeGatewaySetupCode(profile.setupCode);
    if (profile.useSetupCode && payload != null) {
      return (payload.host, payload.port, payload.tls);
    }
    final host = profile.host.trim();
    if (host.isEmpty) {
      return null;
    }
    final normalized = parseGatewayEndpoint(
      host.contains('://')
          ? host
          : _composeManualUrl(host, profile.port, profile.tls),
    );
    return normalized ?? (host, profile.port, profile.tls);
  }

  void _handleIncoming(dynamic raw, Completer<String> challenge) {
    final text = raw is String ? raw : utf8.decode(raw as List<int>);
    final decoded = jsonDecode(text) as Map<String, dynamic>;
    final type = stringValue(decoded['type']);
    if (type == 'event') {
      final event = stringValue(decoded['event']) ?? '';
      final payload = decoded['payload'];
      if (event == 'connect.challenge') {
        final nonce = stringValue(asMap(payload)['nonce']);
        if (nonce != null && !challenge.isCompleted) {
          challenge.complete(nonce);
        }
        _appendLog('debug', 'connect', 'challenge received');
        return;
      }
      if (event == 'health') {
        _snapshot = _snapshot.copyWith(healthPayload: asMap(payload));
        _appendLog('debug', 'health', 'push health update');
        notifyListeners();
      } else if (event == 'device.pair.requested' ||
          event == 'device.pair.resolved') {
        final eventPayload = asMap(payload);
        _appendLog(
          'info',
          'pairing',
          '$event | request: ${stringValue(eventPayload['requestId']) ?? 'unknown'} | device: ${stringValue(eventPayload['deviceId']) ?? 'unknown'}',
        );
      } else if (event == 'seqGap') {
        _appendLog('warn', 'sync', 'sequence gap detected');
      }
      _events.add(
        GatewayPushEvent(
          event: event,
          payload: payload,
          sequence: intValue(decoded['seq']),
        ),
      );
      return;
    }
    if (type != 'res') {
      return;
    }
    final id = stringValue(decoded['id']);
    if (id == null) {
      return;
    }
    final completer = _pending.remove(id);
    if (completer == null || completer.isCompleted) {
      return;
    }
    final ok = boolValue(decoded['ok']) ?? false;
    final payload = decoded['payload'];
    final error = asMap(decoded['error']);
    if (!ok) {
      _appendLog(
        'error',
        'rpc',
        'request failed | code: ${stringValue(error['code']) ?? 'unknown'} | detail: ${stringValue(asMap(error['details'])['code']) ?? 'none'} | message: ${stringValue(error['message']) ?? 'gateway request failed'}',
      );
      if (!_shouldAutoReconnectForCodes(
        stringValue(error['code']),
        stringValue(asMap(error['details'])['code']),
      )) {
        _suppressReconnect = true;
      }
      completer.completeError(
        GatewayRuntimeException(
          stringValue(error['message']) ?? 'gateway request failed',
          code: stringValue(error['code']),
          details: error['details'],
        ),
      );
      return;
    }
    completer.complete(_RpcResponse(ok: ok, payload: payload, error: error));
  }

  void _handleSocketFailure(String message) {
    _failPending(GatewayRuntimeException(message, code: 'SOCKET_FAILURE'));
    if (_manualDisconnect || _suppressReconnect) {
      _appendLog(
        'warn',
        'socket',
        'failure ignored for reconnect | manual: $_manualDisconnect | suppressed: $_suppressReconnect | message: $message',
      );
      return;
    }
    _appendLog('error', 'socket', 'failure | $message');
    _snapshot = _snapshot.copyWith(
      status: RuntimeConnectionStatus.error,
      statusText: 'Gateway error',
      lastError: message,
      lastErrorCode: 'SOCKET_FAILURE',
      lastErrorDetailCode: null,
    );
    notifyListeners();
    _scheduleReconnect();
  }

  void _handleSocketClosed() {
    _failPending(
      GatewayRuntimeException('socket closed', code: 'SOCKET_CLOSED'),
    );
    if (_manualDisconnect || _suppressReconnect) {
      _appendLog(
        'warn',
        'socket',
        'closed without reconnect | manual: $_manualDisconnect | suppressed: $_suppressReconnect',
      );
      return;
    }
    _appendLog('warn', 'socket', 'closed by gateway');
    _snapshot = _snapshot.copyWith(
      status: RuntimeConnectionStatus.error,
      statusText: 'Disconnected',
      lastError: 'Gateway connection closed',
      lastErrorCode: 'SOCKET_CLOSED',
      lastErrorDetailCode: null,
    );
    notifyListeners();
    _scheduleReconnect();
  }

  String _cronScheduleLabel(Map<String, dynamic> schedule) {
    final kind = stringValue(schedule['kind']) ?? '';
    return switch (kind) {
      'at' => stringValue(schedule['at']) ?? 'at',
      'every' => '${intValue(schedule['everyMs']) ?? 0}ms',
      'cron' => stringValue(schedule['expr']) ?? 'cron',
      _ => 'unknown',
    };
  }

  void _scheduleReconnect() {
    final profile = _desiredProfile;
    if (_manualDisconnect || _suppressReconnect || profile == null) {
      return;
    }
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 2), () {
      _appendLog(
        'info',
        'socket',
        'reconnect firing | host: ${profile.host.trim().isEmpty ? 'setup-code' : profile.host.trim()} | port: ${profile.port}',
      );
      unawaited(connectProfile(profile));
    });
  }

  bool _shouldAutoReconnect(GatewayRuntimeException? error) {
    return _shouldAutoReconnectForCodes(error?.code, error?.detailCode);
  }

  bool _shouldAutoReconnectForCodes(String? code, String? detailCode) {
    final resolvedCode = code?.trim().toUpperCase();
    final resolvedDetailCode = detailCode?.trim().toUpperCase();
    const nonRetryableCodes = <String>{
      'INVALID_REQUEST',
      'UNAUTHORIZED',
      'NOT_PAIRED',
      'AUTH_REQUIRED',
    };
    const nonRetryableDetailCodes = <String>{
      'AUTH_REQUIRED',
      'AUTH_UNAUTHORIZED',
      'AUTH_TOKEN_MISSING',
      'AUTH_TOKEN_MISMATCH',
      'AUTH_PASSWORD_MISSING',
      'AUTH_PASSWORD_MISMATCH',
      'AUTH_DEVICE_TOKEN_MISMATCH',
      'PAIRING_REQUIRED',
      'DEVICE_IDENTITY_REQUIRED',
      'CONTROL_UI_DEVICE_IDENTITY_REQUIRED',
    };
    if (resolvedCode != null && nonRetryableCodes.contains(resolvedCode)) {
      return false;
    }
    if (resolvedDetailCode != null &&
        nonRetryableDetailCodes.contains(resolvedDetailCode)) {
      return false;
    }
    return true;
  }

  bool _isPairingRequiredError(String? code, String? detailCode) {
    final resolvedCode = code?.trim().toUpperCase();
    final resolvedDetailCode = detailCode?.trim().toUpperCase();
    return resolvedCode == 'NOT_PAIRED' ||
        resolvedDetailCode == 'PAIRING_REQUIRED';
  }

  Future<void> _closeSocket() async {
    _reconnectTimer?.cancel();
    final subscription = _socketSubscription;
    _socketSubscription = null;
    await subscription?.cancel();
    await _channel?.sink.close();
    _channel = null;
    _failPending(GatewayRuntimeException('socket reset', code: 'SOCKET_RESET'));
  }

  void _appendLog(String level, String category, String message) {
    _logs.add(
      RuntimeLogEntry(
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        level: level,
        category: category,
        message: message,
      ),
    );
    const maxLogEntries = 250;
    if (_logs.length > maxLogEntries) {
      _logs.removeRange(0, _logs.length - maxLogEntries);
    }
    notifyListeners();
  }

  String _connectAuthSummary({
    required String mode,
    required List<String> fields,
    required List<String> sources,
  }) {
    final resolvedFields = fields.isEmpty ? 'none' : fields.join(', ');
    final resolvedSources = sources.isEmpty ? 'none' : sources.join(' · ');
    return '$mode | fields: $resolvedFields | sources: $resolvedSources';
  }

  void _failPending(Object error) {
    final values = _pending.values.toList(growable: false);
    _pending.clear();
    for (final completer in values) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }
  }

  String _resolveClientId() {
    return resolveGatewayClientId();
  }

  Future<RuntimePackageInfo> _loadPackageInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return RuntimePackageInfo(
        appName: info.appName,
        packageName: info.packageName,
        version: info.version,
        buildNumber: info.buildNumber,
      );
    } catch (_) {
      return const RuntimePackageInfo(
        appName: kSystemAppName,
        packageName: 'plus.svc.xworkmate',
        version: kAppVersion,
        buildNumber: kAppBuildNumber,
      );
    }
  }

  Future<RuntimeDeviceInfo> _loadDeviceInfo() async {
    final plugin = DeviceInfoPlugin();
    try {
      if (Platform.isIOS) {
        final info = await plugin.iosInfo;
        return RuntimeDeviceInfo(
          platform: 'ios',
          platformVersion: info.systemVersion,
          deviceFamily: info.model,
          modelIdentifier: info.utsname.machine,
        );
      }
      if (Platform.isMacOS) {
        final info = await plugin.macOsInfo;
        return RuntimeDeviceInfo(
          platform: 'macos',
          platformVersion:
              '${info.majorVersion}.${info.minorVersion}.${info.patchVersion}',
          deviceFamily: 'Mac',
          modelIdentifier: info.model,
        );
      }
      if (Platform.isAndroid) {
        final info = await plugin.androidInfo;
        return RuntimeDeviceInfo(
          platform: 'android',
          platformVersion: info.version.release,
          deviceFamily: info.model,
          modelIdentifier: info.id,
        );
      }
      if (Platform.isWindows) {
        final info = await plugin.windowsInfo;
        return RuntimeDeviceInfo(
          platform: 'windows',
          platformVersion: info.displayVersion,
          deviceFamily: 'Windows',
          modelIdentifier: info.computerName,
        );
      }
      if (Platform.isLinux) {
        final info = await plugin.linuxInfo;
        return RuntimeDeviceInfo(
          platform: 'linux',
          platformVersion: info.version ?? '',
          deviceFamily: 'Linux',
          modelIdentifier: info.machineId ?? 'linux',
        );
      }
    } catch (_) {
      // Fall through to generic info.
    }
    return RuntimeDeviceInfo(
      platform: Platform.operatingSystem,
      platformVersion: Platform.operatingSystemVersion,
      deviceFamily: Platform.operatingSystem,
      modelIdentifier: Platform.localHostname,
    );
  }
}

class GatewaySetupPayload {
  const GatewaySetupPayload({
    required this.host,
    required this.port,
    required this.tls,
    required this.token,
    required this.password,
  });

  final String host;
  final int port;
  final bool tls;
  final String token;
  final String password;
}

GatewaySetupPayload? decodeGatewaySetupCode(String rawInput) {
  final trimmed = rawInput.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  final candidate = _resolveSetupCodeCandidate(trimmed);
  final direct = _decodeSetupPayloadJson(candidate);
  if (direct != null) {
    return direct;
  }
  try {
    final normalized = candidate.replaceAll('-', '+').replaceAll('_', '/');
    final padded = normalized + '=' * ((4 - normalized.length % 4) % 4);
    final decoded = utf8.decode(base64.decode(padded));
    return _decodeSetupPayloadJson(decoded);
  } catch (_) {
    return null;
  }
}

GatewaySetupPayload? _decodeSetupPayloadJson(String raw) {
  try {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final url = stringValue(json['url']);
    final host = stringValue(json['host']);
    final port = intValue(json['port']);
    final tls = boolValue(json['tls']);
    final resolved = parseGatewayEndpoint(
      url ?? _composeManualUrl(host, port, tls),
    );
    if (resolved == null) {
      return null;
    }
    return GatewaySetupPayload(
      host: resolved.$1,
      port: resolved.$2,
      tls: resolved.$3,
      token: stringValue(json['token']) ?? '',
      password: stringValue(json['password']) ?? '',
    );
  } catch (_) {
    return null;
  }
}

String _resolveSetupCodeCandidate(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      return stringValue(decoded['setupCode']) ?? raw;
    }
  } catch (_) {
    // Leave raw as-is.
  }
  return raw;
}

(String, int, bool)? parseGatewayEndpoint(String? rawInput) {
  final raw = rawInput?.trim() ?? '';
  if (raw.isEmpty) {
    return null;
  }
  final normalized = raw.contains('://') ? raw : 'https://$raw';
  final uri = Uri.tryParse(normalized);
  final host = uri?.host.trim() ?? '';
  if (host.isEmpty) {
    return null;
  }
  final scheme = uri?.scheme.trim().toLowerCase() ?? 'https';
  final tls = switch (scheme) {
    'ws' || 'http' => false,
    _ => true,
  };
  final parsedPort = uri?.port;
  final port = parsedPort != null && parsedPort >= 1 && parsedPort <= 65535
      ? parsedPort
      : (tls ? 443 : 18789);
  return (host, port, tls);
}

String? _composeManualUrl(String? host, int? port, bool? tls) {
  final trimmedHost = host?.trim() ?? '';
  if (trimmedHost.isEmpty) {
    return null;
  }
  final resolvedPort = port ?? 18789;
  final scheme = tls == false ? 'http' : 'https';
  return '$scheme://$trimmedHost:$resolvedPort';
}

Map<String, dynamic> asMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.cast<String, dynamic>();
  }
  return const <String, dynamic>{};
}

List<dynamic> asList(Object? value) {
  if (value is List<dynamic>) {
    return value;
  }
  if (value is List) {
    return value.cast<dynamic>();
  }
  return const <dynamic>[];
}

String? stringValue(Object? value) {
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
  return null;
}

bool? boolValue(Object? value) {
  if (value is bool) {
    return value;
  }
  if (value is String) {
    switch (value.trim().toLowerCase()) {
      case 'true':
        return true;
      case 'false':
        return false;
    }
  }
  return null;
}

int? intValue(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is double) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}

double? doubleValue(Object? value) {
  if (value is double) {
    return value;
  }
  if (value is int) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value);
  }
  return null;
}

List<String> stringList(Object? value) {
  return asList(
    value,
  ).map(stringValue).whereType<String>().toList(growable: false);
}

String extractMessageText(Map<String, dynamic> message) {
  final directContent = message['content'];
  if (directContent is String) {
    return directContent;
  }
  final parts = <String>[];
  for (final part in asList(directContent)) {
    final map = asMap(part);
    final text = stringValue(map['text']) ?? stringValue(map['thinking']);
    if (text != null && text.isNotEmpty) {
      parts.add(text);
      continue;
    }
    final nestedContent = map['content'];
    if (nestedContent is String && nestedContent.trim().isNotEmpty) {
      parts.add(nestedContent.trim());
    }
  }
  return parts.join('\n').trim();
}

String _randomId() {
  final random = Random.secure();
  final timestamp = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
  final suffix = List<int>.generate(
    6,
    (_) => random.nextInt(256),
  ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  return '$timestamp-$suffix';
}

class _RpcResponse {
  const _RpcResponse({
    required this.ok,
    required this.payload,
    required this.error,
  });

  final bool ok;
  final dynamic payload;
  final Map<String, dynamic> error;
}
