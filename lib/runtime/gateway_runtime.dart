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
  GatewayRuntimeException(this.message, {this.code});

  final String message;
  final String? code;

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

  IOWebSocketChannel? _channel;
  StreamSubscription<dynamic>? _socketSubscription;
  Timer? _reconnectTimer;
  GatewayConnectionProfile? _desiredProfile;
  bool _manualDisconnect = false;
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
  RuntimeDeviceInfo _deviceInfo = const RuntimeDeviceInfo(
    platform: 'macos',
    platformVersion: '',
    deviceFamily: 'Mac',
    modelIdentifier: 'unknown',
  );

  GatewayConnectionSnapshot get snapshot => _snapshot;
  RuntimePackageInfo get packageInfo => _packageInfo;
  RuntimeDeviceInfo get deviceInfo => _deviceInfo;
  Stream<GatewayPushEvent> get events => _events.stream;
  bool get isConnected => _snapshot.status == RuntimeConnectionStatus.connected;

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
    await _closeSocket();

    final endpoint = _resolveEndpoint(profile);
    final setupPayload = decodeGatewaySetupCode(profile.setupCode);
    final storedToken = (await _store.loadGatewayToken())?.trim() ?? '';
    final storedPassword = (await _store.loadGatewayPassword())?.trim() ?? '';
    final explicitToken = authTokenOverride.trim();
    final explicitPassword = authPasswordOverride.trim();
    final token = explicitToken.isNotEmpty
        ? explicitToken
        : storedToken.isNotEmpty
        ? storedToken
        : (setupPayload?.token.trim() ?? '');
    final password = explicitPassword.isNotEmpty
        ? explicitPassword
        : storedPassword.isNotEmpty
        ? storedPassword
        : (setupPayload?.password.trim() ?? '');

    if (endpoint == null) {
      _snapshot = GatewayConnectionSnapshot.initial(mode: profile.mode)
          .copyWith(
            statusText: 'Missing gateway endpoint',
            lastError: 'Configure setup code or manual host / port first.',
          );
      notifyListeners();
      return;
    }

    _snapshot = GatewayConnectionSnapshot.initial(mode: profile.mode).copyWith(
      status: RuntimeConnectionStatus.connecting,
      statusText: 'Connecting…',
      remoteAddress: '${endpoint.$1}:${endpoint.$2}',
      hasSharedAuth: token.isNotEmpty || password.isNotEmpty,
      clearLastError: true,
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

      final identity = await _identityStore.loadOrCreate();
      final deviceToken =
          (await _store.loadDeviceToken(
            deviceId: identity.deviceId,
            role: 'operator',
          ))?.trim() ??
          '';
      final authToken = token.isNotEmpty ? token : deviceToken;
      final connectResult = await _requestRaw(
        'connect',
        params: await _buildConnectParams(
          profile: profile,
          identity: identity,
          nonce: nonce,
          authToken: authToken,
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
      }
      _snapshot = _snapshot.copyWith(
        status: RuntimeConnectionStatus.connected,
        statusText: 'Connected',
        serverName: stringValue(server['host']),
        remoteAddress: '${endpoint.$1}:${endpoint.$2}',
        mainSessionKey:
            stringValue(sessionDefaults['mainSessionKey']) ?? 'main',
        lastConnectedAtMs: DateTime.now().millisecondsSinceEpoch,
        hasSharedAuth: token.isNotEmpty || password.isNotEmpty,
        hasDeviceToken:
            returnedDeviceToken != null && returnedDeviceToken.isNotEmpty,
        clearLastError: true,
      );
      notifyListeners();
    } catch (error) {
      await _closeSocket();
      _snapshot = _snapshot.copyWith(
        status: RuntimeConnectionStatus.error,
        statusText: 'Connection failed',
        lastError: error.toString(),
      );
      notifyListeners();
      _scheduleReconnect();
      rethrow;
    }
  }

  Future<void> disconnect({bool clearDesiredProfile = true}) async {
    _manualDisconnect = true;
    if (clearDesiredProfile) {
      _desiredProfile = null;
    }
    _reconnectTimer?.cancel();
    await _closeSocket();
    _snapshot = GatewayConnectionSnapshot.initial(mode: _snapshot.mode)
        .copyWith(
          statusText: 'Offline',
          hasSharedAuth: _snapshot.hasSharedAuth,
          hasDeviceToken: _snapshot.hasDeviceToken,
        );
    notifyListeners();
  }

  Future<Map<String, dynamic>> health() async {
    final payload = asMap(await request('health'));
    _snapshot = _snapshot.copyWith(healthPayload: payload);
    notifyListeners();
    return payload;
  }

  Future<Map<String, dynamic>> status() async {
    final payload = asMap(await request('status'));
    _snapshot = _snapshot.copyWith(statusPayload: payload);
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

  Future<dynamic> request(
    String method, {
    Map<String, dynamic>? params,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (_channel == null || !isConnected) {
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

  Future<Map<String, dynamic>> _buildConnectParams({
    required GatewayConnectionProfile profile,
    required LocalDeviceIdentity identity,
    required String nonce,
    required String authToken,
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
      if (authToken.isNotEmpty)
        'auth': <String, dynamic>{'token': authToken}
      else if (authPassword.isNotEmpty)
        'auth': <String, dynamic>{'password': authPassword},
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
    return (host, profile.port, profile.tls);
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
        return;
      }
      if (event == 'health') {
        _snapshot = _snapshot.copyWith(healthPayload: asMap(payload));
        notifyListeners();
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
      completer.completeError(
        GatewayRuntimeException(
          stringValue(error['message']) ?? 'gateway request failed',
          code: stringValue(error['code']),
        ),
      );
      return;
    }
    completer.complete(_RpcResponse(ok: ok, payload: payload, error: error));
  }

  void _handleSocketFailure(String message) {
    _failPending(GatewayRuntimeException(message, code: 'SOCKET_FAILURE'));
    if (_manualDisconnect) {
      return;
    }
    _snapshot = _snapshot.copyWith(
      status: RuntimeConnectionStatus.error,
      statusText: 'Gateway error',
      lastError: message,
    );
    notifyListeners();
    _scheduleReconnect();
  }

  void _handleSocketClosed() {
    _failPending(
      GatewayRuntimeException('socket closed', code: 'SOCKET_CLOSED'),
    );
    if (_manualDisconnect) {
      return;
    }
    _snapshot = _snapshot.copyWith(
      status: RuntimeConnectionStatus.error,
      statusText: 'Disconnected',
      lastError: 'Gateway connection closed',
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
    if (_manualDisconnect || profile == null) {
      return;
    }
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 2), () {
      unawaited(connectProfile(profile));
    });
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
    if (Platform.isMacOS) {
      return 'openclaw-macos';
    }
    if (Platform.isIOS) {
      return 'openclaw-ios';
    }
    if (Platform.isAndroid) {
      return 'openclaw-android';
    }
    return 'gateway-client';
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
      : 18789;
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
