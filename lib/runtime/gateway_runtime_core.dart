// ignore_for_file: unused_import, unnecessary_import

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
import 'gateway_runtime_protocol.dart';
import 'gateway_runtime_events.dart';
import 'gateway_runtime_errors.dart';
import 'gateway_runtime_helpers.dart';

class GatewayRuntime extends ChangeNotifier with GatewayRuntimeHelpersInternal {
  GatewayRuntime({
    required SecureConfigStore store,
    required DeviceIdentityStore identityStore,
  }) : storeInternal = store,
       identityStoreInternal = identityStore;

  final SecureConfigStore storeInternal;
  final DeviceIdentityStore identityStoreInternal;
  final StreamController<GatewayPushEvent> eventsInternal =
      StreamController<GatewayPushEvent>.broadcast();
  final Map<String, Completer<RpcResponseInternal>> pendingInternal =
      <String, Completer<RpcResponseInternal>>{};
  final List<RuntimeLogEntry> logsInternal = <RuntimeLogEntry>[];

  IOWebSocketChannel? channelInternal;
  StreamSubscription<dynamic>? socketSubscriptionInternal;
  Timer? reconnectTimerInternal;
  GatewayConnectionProfile? desiredProfileInternal;
  bool manualDisconnectInternal = false;
  bool suppressReconnectInternal = false;
  int requestCounterInternal = 0;

  GatewayConnectionSnapshot snapshotInternal =
      GatewayConnectionSnapshot.initial(
        mode: GatewayConnectionProfile.defaults().mode,
      );
  RuntimePackageInfo packageInfoInternal = const RuntimePackageInfo(
    appName: kSystemAppName,
    packageName: 'plus.svc.xworkmate',
    version: kAppVersion,
    buildNumber: kAppBuildNumber,
  );
  RuntimeDeviceInfo deviceInfoInternal = RuntimeDeviceInfo(
    platform: Platform.operatingSystem,
    platformVersion: '',
    deviceFamily: 'Desktop',
    modelIdentifier: 'unknown',
  );

  GatewayConnectionSnapshot get snapshot => snapshotInternal;
  RuntimePackageInfo get packageInfo => packageInfoInternal;
  RuntimeDeviceInfo get deviceInfo => deviceInfoInternal;
  Stream<GatewayPushEvent> get events => eventsInternal.stream;
  List<RuntimeLogEntry> get logs =>
      List<RuntimeLogEntry>.unmodifiable(logsInternal);
  bool get isConnected =>
      snapshotInternal.status == RuntimeConnectionStatus.connected;

  void clearLogs() {
    if (logsInternal.isEmpty) {
      return;
    }
    logsInternal.clear();
    notifyListeners();
  }

  @visibleForTesting
  void addRuntimeLogForTest({
    required String level,
    required String category,
    required String message,
  }) {
    appendLogInternal(this, level, category, message);
  }

  Future<void> initialize() async {
    await storeInternal.initialize();
    packageInfoInternal = await loadPackageInfoInternal();
    deviceInfoInternal = await loadDeviceInfoInternal();
    notifyListeners();
  }

  Future<void> connectProfile(
    GatewayConnectionProfile profile, {
    int? profileIndex,
    String authTokenOverride = '',
    String authPasswordOverride = '',
  }) async {
    desiredProfileInternal = profile;
    manualDisconnectInternal = false;
    suppressReconnectInternal = false;
    await closeSocketInternal(this);

    final endpoint = resolveEndpointInternal(profile);
    final setupPayload = decodeGatewaySetupCode(profile.setupCode);
    final storedToken =
        (await storeInternal.loadGatewayToken(
          profileIndex: profileIndex,
        ))?.trim() ??
        '';
    final storedPassword =
        (await storeInternal.loadGatewayPassword(
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
    final identity = await identityStoreInternal.loadOrCreate();
    final storedDeviceToken =
        (await storeInternal.loadDeviceToken(
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
    final connectAuthSummary = connectAuthSummaryInternal(
      mode: connectAuthMode,
      fields: connectAuthFields,
      sources: connectAuthSources,
    );
    final usedStoredDeviceTokenOnly =
        sharedToken.isEmpty && deviceToken.isNotEmpty;

    if (endpoint == null) {
      appendLogInternal(
        this,
        'warn',
        'connect',
        'missing endpoint | auth: $connectAuthSummary',
      );
      snapshotInternal = GatewayConnectionSnapshot.initial(mode: profile.mode)
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

    appendLogInternal(
      this,
      'info',
      'connect',
      'attempt ${endpoint.$1}:${endpoint.$2} tls:${endpoint.$3} | auth: $connectAuthSummary',
    );

    snapshotInternal = GatewayConnectionSnapshot.initial(mode: profile.mode)
        .copyWith(
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
      channelInternal = IOWebSocketChannel.connect(
        Uri.parse('$scheme://${endpoint.$1}:${endpoint.$2}'),
        pingInterval: const Duration(seconds: 30),
        connectTimeout: const Duration(seconds: 10),
      );
      final challenge = Completer<String>();
      socketSubscriptionInternal = channelInternal!.stream.listen(
        (dynamic raw) => handleIncomingInternal(this, raw, challenge),
        onError: (Object error, StackTrace stackTrace) {
          handleSocketFailureInternal(this, error.toString());
        },
        onDone: () {
          handleSocketClosedInternal(this);
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
      final connectResult = await requestRawInternal(
        this,
        'connect',
        params: await buildConnectParamsInternal(
          this,
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
        await storeInternal.saveDeviceToken(
          deviceId: identity.deviceId,
          role: stringValue(auth['role']) ?? 'operator',
          token: returnedDeviceToken,
        );
        appendLogInternal(
          this,
          'info',
          'auth',
          'stored device token for role ${stringValue(auth['role']) ?? 'operator'}',
        );
      }
      final negotiatedRole = stringValue(auth['role']) ?? 'operator';
      final negotiatedScopes = stringList(auth['scopes']);
      snapshotInternal = snapshotInternal.copyWith(
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
      appendLogInternal(
        this,
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
        await storeInternal.clearDeviceToken(
          deviceId: identity.deviceId,
          role: 'operator',
        );
      } else if (usedStoredDeviceTokenOnly &&
          isPairingRequiredErrorInternal(
            runtimeError?.code,
            runtimeError?.detailCode,
          )) {
        await storeInternal.clearDeviceToken(
          deviceId: identity.deviceId,
          role: 'operator',
        );
        appendLogInternal(
          this,
          'warn',
          'auth',
          'cleared stale device token after pairing-required response',
        );
      }
      if (!shouldAutoReconnectInternal(runtimeError)) {
        suppressReconnectInternal = true;
        appendLogInternal(
          this,
          'warn',
          'socket',
          'auto reconnect suppressed | code: ${runtimeError?.code ?? 'unknown'} | detail: ${runtimeError?.detailCode ?? 'none'}',
        );
      }
      await closeSocketInternal(this);
      appendLogInternal(
        this,
        'error',
        'connect',
        'failed ${endpoint.$1}:${endpoint.$2} | code: ${runtimeError?.code ?? 'unknown'} | detail: ${runtimeError?.detailCode ?? 'none'} | message: ${error.toString()}',
      );
      snapshotInternal = snapshotInternal.copyWith(
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
      if (shouldAutoReconnectInternal(runtimeError)) {
        appendLogInternal(
          this,
          'warn',
          'socket',
          'scheduling reconnect in 2s | code: ${runtimeError?.code ?? 'unknown'}',
        );
        scheduleReconnectInternal(this);
      }
      rethrow;
    }
  }

  Future<void> disconnect({bool clearDesiredProfile = true}) async {
    manualDisconnectInternal = true;
    appendLogInternal(this, 'info', 'connect', 'manual disconnect');
    if (clearDesiredProfile) {
      desiredProfileInternal = null;
    }
    reconnectTimerInternal?.cancel();
    await closeSocketInternal(this);
    snapshotInternal =
        GatewayConnectionSnapshot.initial(mode: snapshotInternal.mode).copyWith(
          statusText: 'Offline',
          deviceId: snapshotInternal.deviceId,
          authRole: snapshotInternal.authRole,
          authScopes: snapshotInternal.authScopes,
          hasSharedAuth: snapshotInternal.hasSharedAuth,
          hasDeviceToken: snapshotInternal.hasDeviceToken,
        );
    notifyListeners();
  }

  Future<Map<String, dynamic>> health() async {
    final payload = asMap(await request('health'));
    snapshotInternal = snapshotInternal.copyWith(healthPayload: payload);
    appendLogInternal(this, 'debug', 'health', 'health snapshot refreshed');
    notifyListeners();
    return payload;
  }

  Future<Map<String, dynamic>> status() async {
    final payload = asMap(await request('status'));
    snapshotInternal = snapshotInternal.copyWith(statusPayload: payload);
    appendLogInternal(this, 'debug', 'health', 'status snapshot refreshed');
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
    if (snapshotInternal.mainSessionKey == null ||
        snapshotInternal.mainSessionKey!.trim().isEmpty) {
      snapshotInternal = snapshotInternal.copyWith(
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
            id: randomIdInternal(),
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
    final runId = randomIdInternal();
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
            id: stringValue(map['id']) ?? randomIdInternal(),
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
            id: stringValue(map['id']) ?? randomIdInternal(),
            name: stringValue(map['name']) ?? 'Untitled job',
            description: stringValue(map['description']),
            enabled: boolValue(map['enabled']) ?? true,
            agentId: stringValue(map['agentId']),
            scheduleLabel: cronScheduleLabelInternal(asMap(map['schedule'])),
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
    final identity = await storeInternal.loadDeviceIdentity();
    return GatewayDevicePairingList(
      pending: asList(payload['pending'])
          .map((item) => parsePendingDeviceInternal(asMap(item)))
          .toList(growable: false),
      paired: asList(payload['paired'])
          .map(
            (item) => parsePairedDeviceInternal(
              asMap(item),
              currentDeviceId: identity?.deviceId,
            ),
          )
          .toList(growable: false),
    );
  }

  Future<GatewayPairedDevice?> approveDevicePairing(String requestId) async {
    appendLogInternal(this, 'info', 'pairing', 'approve request $requestId');
    final payload = asMap(
      await request(
        'device.pair.approve',
        params: <String, dynamic>{'requestId': requestId},
        timeout: const Duration(seconds: 12),
      ),
    );
    final identity = await storeInternal.loadDeviceIdentity();
    final device = asMap(payload['device']);
    if (device.isEmpty) {
      return null;
    }
    return parsePairedDeviceInternal(
      device,
      currentDeviceId: identity?.deviceId,
    );
  }

  Future<void> rejectDevicePairing(String requestId) async {
    appendLogInternal(this, 'info', 'pairing', 'reject request $requestId');
    await request(
      'device.pair.reject',
      params: <String, dynamic>{'requestId': requestId},
      timeout: const Duration(seconds: 12),
    );
  }

  Future<void> removePairedDevice(String deviceId) async {
    appendLogInternal(this, 'info', 'pairing', 'remove device $deviceId');
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
    appendLogInternal(
      this,
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
    final identity = await storeInternal.loadDeviceIdentity();
    final resolvedRole = stringValue(payload['role']) ?? role;
    if (token.isNotEmpty &&
        identity != null &&
        (stringValue(payload['deviceId']) ?? deviceId) == identity.deviceId) {
      await storeInternal.saveDeviceToken(
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
    appendLogInternal(
      this,
      'info',
      'token',
      'revoke role token | device: $deviceId | role: $role',
    );
    await request(
      'device.token.revoke',
      params: <String, dynamic>{'deviceId': deviceId, 'role': role},
      timeout: const Duration(seconds: 12),
    );
    final identity = await storeInternal.loadDeviceIdentity();
    if (identity != null && deviceId == identity.deviceId) {
      await storeInternal.clearDeviceToken(
        deviceId: identity.deviceId,
        role: role,
      );
    }
  }

  Future<dynamic> request(
    String method, {
    Map<String, dynamic>? params,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (channelInternal == null || !isConnected) {
      appendLogInternal(
        this,
        'warn',
        'rpc',
        'blocked request $method | offline',
      );
      throw GatewayRuntimeException('gateway not connected', code: 'OFFLINE');
    }
    final result = await requestRawInternal(
      this,
      method,
      params: params,
      timeout: timeout,
    );
    return result.payload;
  }

  @override
  void dispose() {
    eventsInternal.close();
    reconnectTimerInternal?.cancel();
    unawaited(closeSocketInternal(this));
    super.dispose();
  }
}
