import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../app/app_metadata.dart';
import '../runtime/runtime_models.dart';
import 'web_store.dart';

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

class WebRelayGatewayClient {
  WebRelayGatewayClient(this.storeInternal);

  final WebStore storeInternal;
  final StreamController<GatewayPushEvent> eventsInternal =
      StreamController<GatewayPushEvent>.broadcast();
  final Map<String, Completer<RelayRpcResponseInternal>> pendingInternal =
      <String, Completer<RelayRpcResponseInternal>>{};
  final WebRelayIdentityManagerInternal identityManagerInternal =
      WebRelayIdentityManagerInternal();

  WebSocketChannel? channelInternal;
  StreamSubscription<dynamic>? subscriptionInternal;
  int requestCounterInternal = 0;
  GatewayConnectionSnapshot snapshotInternal =
      GatewayConnectionSnapshot.initial(
        mode: RuntimeConnectionMode.unconfigured,
      );

  Stream<GatewayPushEvent> get events => eventsInternal.stream;
  GatewayConnectionSnapshot get snapshot => snapshotInternal;
  bool get isConnected =>
      snapshotInternal.status == RuntimeConnectionStatus.connected;
  String get mainSessionKey => snapshotInternal.mainSessionKey ?? 'main';

  Future<void> connect({
    required GatewayConnectionProfile profile,
    required String authToken,
    required String authPassword,
  }) async {
    await disconnect();
    final targetMode = profile.mode == RuntimeConnectionMode.local
        ? RuntimeConnectionMode.local
        : RuntimeConnectionMode.remote;
    final endpoint = resolveEndpointInternal(profile);
    if (endpoint == null) {
      snapshotInternal = GatewayConnectionSnapshot.initial(mode: targetMode)
          .copyWith(
            status: RuntimeConnectionStatus.error,
            statusText: 'Missing relay endpoint',
            lastError: 'Configure relay host / port first.',
            lastErrorCode: 'MISSING_ENDPOINT',
          );
      throw const WebRelayGatewayException('Missing relay endpoint');
    }

    final identity = await identityManagerInternal.loadOrCreate(storeInternal);
    snapshotInternal = GatewayConnectionSnapshot.initial(mode: targetMode)
        .copyWith(
          status: RuntimeConnectionStatus.connecting,
          statusText: 'Connecting…',
          remoteAddress: '${endpoint.host}:${endpoint.port}',
          deviceId: identity.deviceId,
          authRole: 'operator',
          authScopes: const <String>[
            'operator.admin',
            'operator.read',
            'operator.write',
            'operator.approvals',
            'operator.pairing',
          ],
          connectAuthMode: authToken.trim().isNotEmpty
              ? 'shared-token'
              : authPassword.trim().isNotEmpty
              ? 'password'
              : 'none',
          connectAuthFields: <String>[
            if (authToken.trim().isNotEmpty) 'token',
            if (authPassword.trim().isNotEmpty) 'password',
          ],
          connectAuthSources: <String>[
            if (authToken.trim().isNotEmpty) 'browser-store',
            if (authPassword.trim().isNotEmpty) 'browser-store',
          ],
          hasSharedAuth:
              authToken.trim().isNotEmpty || authPassword.trim().isNotEmpty,
          hasDeviceToken: false,
          clearLastError: true,
          clearLastErrorCode: true,
          clearLastErrorDetailCode: true,
        );

    final uri = Uri(
      scheme: endpoint.tls ? 'wss' : 'ws',
      host: endpoint.host,
      port: endpoint.port,
    );
    final channel = WebSocketChannel.connect(uri);
    final challenge = Completer<String>();

    channelInternal = channel;
    subscriptionInternal = channel.stream.listen(
      (dynamic raw) => handleIncomingInternal(raw, challenge),
      onError: (Object error, StackTrace stackTrace) {
        snapshotInternal = snapshotInternal.copyWith(
          status: RuntimeConnectionStatus.error,
          statusText: 'Relay error',
          lastError: error.toString(),
          lastErrorCode: 'SOCKET_FAILURE',
        );
      },
      onDone: () {
        if (snapshotInternal.status == RuntimeConnectionStatus.connected) {
          snapshotInternal = snapshotInternal.copyWith(
            status: RuntimeConnectionStatus.error,
            statusText: 'Disconnected',
            lastError: 'Relay connection closed',
            lastErrorCode: 'SOCKET_CLOSED',
          );
        }
      },
      cancelOnError: true,
    );

    try {
      await channel.ready;
      final nonce = await challenge.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () =>
            throw const WebRelayGatewayException('Relay challenge timeout'),
      );
      final result = await requestRawInternal(
        'connect',
        params: await buildConnectParamsInternal(
          identity: identity,
          nonce: nonce,
          authToken: authToken.trim(),
          authPassword: authPassword.trim(),
        ),
        timeout: const Duration(seconds: 12),
      );
      final payload = asMapInternal(result.payload);
      final auth = asMapInternal(payload['auth']);
      final snapshot = asMapInternal(payload['snapshot']);
      final sessionDefaults = asMapInternal(snapshot['sessionDefaults']);
      final server = asMapInternal(payload['server']);
      snapshotInternal = snapshotInternal.copyWith(
        status: RuntimeConnectionStatus.connected,
        statusText: 'Connected',
        mode: targetMode,
        serverName: stringValueInternal(server['host']),
        remoteAddress: '${endpoint.host}:${endpoint.port}',
        mainSessionKey:
            stringValueInternal(sessionDefaults['mainSessionKey']) ?? 'main',
        lastConnectedAtMs: DateTime.now().millisecondsSinceEpoch,
        authRole: stringValueInternal(auth['role']) ?? 'operator',
        authScopes: stringListInternal(auth['scopes']),
        clearLastError: true,
        clearLastErrorCode: true,
        clearLastErrorDetailCode: true,
      );
    } catch (error) {
      await disconnect();
      snapshotInternal = snapshotInternal.copyWith(
        mode: targetMode,
        status: RuntimeConnectionStatus.error,
        statusText: 'Connection failed',
        lastError: error.toString(),
        lastErrorCode: 'CONNECT_FAILED',
      );
      rethrow;
    }
  }

  Future<void> disconnect() async {
    for (final pending in pendingInternal.values) {
      if (!pending.isCompleted) {
        pending.completeError(
          const WebRelayGatewayException('Relay request cancelled'),
        );
      }
    }
    pendingInternal.clear();
    await subscriptionInternal?.cancel();
    subscriptionInternal = null;
    await channelInternal?.sink.close();
    channelInternal = null;
    if (snapshotInternal.status != RuntimeConnectionStatus.offline) {
      snapshotInternal = snapshotInternal.copyWith(
        status: RuntimeConnectionStatus.offline,
        statusText: 'Offline',
        clearRemoteAddress: true,
      );
    }
  }

  Future<List<GatewaySessionSummary>> listSessions({int limit = 50}) async {
    final payload = asMapInternal(
      await request(
        'sessions.list',
        params: <String, dynamic>{
          'includeGlobal': true,
          'includeUnknown': false,
          'includeDerivedTitles': true,
          'includeLastMessage': true,
          'limit': limit,
        },
      ),
    );
    return asListInternal(payload['sessions'])
        .map((item) {
          final map = asMapInternal(item);
          return GatewaySessionSummary(
            key: stringValueInternal(map['key']) ?? 'main',
            kind: stringValueInternal(map['kind']),
            displayName:
                stringValueInternal(map['displayName']) ??
                stringValueInternal(map['label']),
            surface: stringValueInternal(map['surface']),
            subject: stringValueInternal(map['subject']),
            room: stringValueInternal(map['room']),
            space: stringValueInternal(map['space']),
            updatedAtMs: doubleValueInternal(map['updatedAt']),
            sessionId: stringValueInternal(map['sessionId']),
            systemSent: boolValueInternal(map['systemSent']),
            abortedLastRun: boolValueInternal(map['abortedLastRun']),
            thinkingLevel: stringValueInternal(map['thinkingLevel']),
            verboseLevel: stringValueInternal(map['verboseLevel']),
            inputTokens: intValueInternal(map['inputTokens']),
            outputTokens: intValueInternal(map['outputTokens']),
            totalTokens: intValueInternal(map['totalTokens']),
            model: stringValueInternal(map['model']),
            contextTokens: intValueInternal(map['contextTokens']),
            derivedTitle: stringValueInternal(map['derivedTitle']),
            lastMessagePreview: stringValueInternal(map['lastMessagePreview']),
          );
        })
        .toList(growable: false);
  }

  Future<List<GatewayChatMessage>> loadHistory(
    String sessionKey, {
    int limit = 120,
  }) async {
    final payload = asMapInternal(
      await request(
        'chat.history',
        params: <String, dynamic>{'sessionKey': sessionKey, 'limit': limit},
      ),
    );
    return asListInternal(payload['messages'])
        .map((item) {
          final map = asMapInternal(item);
          return GatewayChatMessage(
            id: randomIdInternal(),
            role: stringValueInternal(map['role']) ?? 'assistant',
            text: extractMessageTextInternal(map),
            timestampMs: doubleValueInternal(map['timestamp']),
            toolCallId:
                stringValueInternal(map['toolCallId']) ??
                stringValueInternal(map['tool_call_id']),
            toolName:
                stringValueInternal(map['toolName']) ??
                stringValueInternal(map['tool_name']),
            stopReason: stringValueInternal(map['stopReason']),
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
    Map<String, dynamic> metadata = const <String, dynamic>{},
  }) async {
    final runId = randomIdInternal();
    final normalizedMetadata = <String, dynamic>{
      for (final entry in metadata.entries)
        if (entry.key.trim().isNotEmpty) entry.key: entry.value,
    };
    final payload = asMapInternal(
      await request(
        'chat.send',
        params: <String, dynamic>{
          'sessionKey': sessionKey,
          'message': message,
          'thinking': thinking,
          if (attachments.isNotEmpty)
            'attachments': attachments
                .map((item) => item.toJson())
                .toList(growable: false),
          if (normalizedMetadata.isNotEmpty) 'metadata': normalizedMetadata,
          'timeoutMs': 30000,
          'idempotencyKey': runId,
        },
        timeout: const Duration(seconds: 35),
      ),
    );
    return stringValueInternal(payload['runId']) ?? runId;
  }

  Future<List<GatewayModelSummary>> listModels() async {
    final payload = asMapInternal(await request('models.list'));
    return asListInternal(payload['models'])
        .map((item) {
          final map = asMapInternal(item);
          return GatewayModelSummary(
            id: stringValueInternal(map['id']) ?? 'unknown',
            name:
                stringValueInternal(map['name']) ??
                stringValueInternal(map['id']) ??
                'unknown',
            provider: stringValueInternal(map['provider']) ?? 'relay',
            contextWindow: intValueInternal(map['contextWindow']),
            maxOutputTokens: intValueInternal(map['maxOutputTokens']),
          );
        })
        .toList(growable: false);
  }

  Future<List<GatewayAgentSummary>> listAgents() async {
    final payload = asMapInternal(
      await request('agents.list', params: const <String, dynamic>{}),
    );
    return asListInternal(payload['agents'])
        .map((item) {
          final map = asMapInternal(item);
          final identity = asMapInternal(map['identity']);
          return GatewayAgentSummary(
            id: stringValueInternal(map['id']) ?? 'unknown',
            name:
                stringValueInternal(map['name']) ??
                stringValueInternal(identity['name']) ??
                'Agent',
            emoji: stringValueInternal(identity['emoji']) ?? '·',
            theme: stringValueInternal(identity['theme']) ?? 'default',
          );
        })
        .toList(growable: false);
  }

  Future<List<GatewayInstanceSummary>> listInstances() async {
    final payload = await request(
      'system-presence',
      params: const <String, dynamic>{},
    );
    return asListInternal(payload)
        .map((item) {
          final map = asMapInternal(item);
          return GatewayInstanceSummary(
            id: stringValueInternal(map['id']) ?? randomIdInternal(),
            host: stringValueInternal(map['host']),
            ip: stringValueInternal(map['ip']),
            version: stringValueInternal(map['version']),
            platform: stringValueInternal(map['platform']),
            deviceFamily: stringValueInternal(map['deviceFamily']),
            modelIdentifier: stringValueInternal(map['modelIdentifier']),
            lastInputSeconds: intValueInternal(map['lastInputSeconds']),
            mode: stringValueInternal(map['mode']),
            reason: stringValueInternal(map['reason']),
            text: stringValueInternal(map['text']) ?? '',
            timestampMs:
                doubleValueInternal(map['ts']) ??
                DateTime.now().millisecondsSinceEpoch.toDouble(),
          );
        })
        .toList(growable: false);
  }

  Future<List<GatewayConnectorSummary>> listConnectors() async {
    final payload = asMapInternal(
      await request(
        'channels.status',
        params: const <String, dynamic>{'probe': true, 'timeoutMs': 8000},
        timeout: const Duration(seconds: 16),
      ),
    );
    final channelMeta = <String, Map<String, dynamic>>{
      for (final entry in asListInternal(payload['channelMeta']))
        if (stringValueInternal(asMapInternal(entry)['id']) != null)
          stringValueInternal(asMapInternal(entry)['id'])!: asMapInternal(
            entry,
          ),
    };
    final labels = asMapInternal(payload['channelLabels']);
    final detailLabels = asMapInternal(payload['channelDetailLabels']);
    final accounts = asMapInternal(payload['channelAccounts']);
    final order = stringListInternal(payload['channelOrder']);
    final summaries = <GatewayConnectorSummary>[];

    for (final channelId in order) {
      final channelAccounts = asListInternal(accounts[channelId]);
      if (channelAccounts.isEmpty) {
        final meta = channelMeta[channelId] ?? const <String, dynamic>{};
        summaries.add(
          GatewayConnectorSummary(
            id: channelId,
            label:
                stringValueInternal(meta['label']) ??
                stringValueInternal(labels[channelId]) ??
                channelId,
            detailLabel:
                stringValueInternal(meta['detailLabel']) ??
                stringValueInternal(detailLabels[channelId]) ??
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
        final map = asMapInternal(account);
        final configured = boolValueInternal(map['configured']) ?? false;
        final enabled = boolValueInternal(map['enabled']) ?? configured;
        final running = boolValueInternal(map['running']) ?? false;
        final connected =
            boolValueInternal(map['connected']) ??
            boolValueInternal(map['linked']) ??
            false;
        final lastError = stringValueInternal(map['lastError']);
        final status = lastError != null && lastError.trim().isNotEmpty
            ? 'error'
            : connected
            ? 'connected'
            : running
            ? 'running'
            : configured
            ? 'configured'
            : 'idle';
        final mode = stringValueInternal(map['mode']);
        final tokenSource = stringValueInternal(map['tokenSource']);
        final baseUrl = stringValueInternal(map['baseUrl']);
        summaries.add(
          GatewayConnectorSummary(
            id: channelId,
            label:
                stringValueInternal(channelMeta[channelId]?['label']) ??
                stringValueInternal(labels[channelId]) ??
                channelId,
            detailLabel:
                stringValueInternal(channelMeta[channelId]?['detailLabel']) ??
                stringValueInternal(detailLabels[channelId]) ??
                channelId,
            accountName:
                stringValueInternal(map['name']) ??
                stringValueInternal(map['accountId']),
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

  Future<List<GatewayCronJobSummary>> listCronJobs() async {
    final payload = asMapInternal(
      await request(
        'cron.list',
        params: const <String, dynamic>{'includeDisabled': true},
        timeout: const Duration(seconds: 16),
      ),
    );
    return asListInternal(payload['jobs'])
        .map((item) {
          final map = asMapInternal(item);
          final state = asMapInternal(map['state']);
          return GatewayCronJobSummary(
            id: stringValueInternal(map['id']) ?? randomIdInternal(),
            name: stringValueInternal(map['name']) ?? 'Untitled job',
            description: stringValueInternal(map['description']),
            enabled: boolValueInternal(map['enabled']) ?? true,
            agentId: stringValueInternal(map['agentId']),
            scheduleLabel: cronScheduleLabelInternal(
              asMapInternal(map['schedule']),
            ),
            nextRunAtMs: intValueInternal(state['nextRunAtMs']),
            lastRunAtMs: intValueInternal(state['lastRunAtMs']),
            lastStatus: stringValueInternal(state['lastStatus']),
            lastError: stringValueInternal(state['lastError']),
          );
        })
        .toList(growable: false);
  }

  Future<dynamic> request(
    String method, {
    Map<String, dynamic>? params,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (channelInternal == null || !isConnected) {
      throw const WebRelayGatewayException('Relay not connected');
    }
    final result = await requestRawInternal(
      method,
      params: params,
      timeout: timeout,
    );
    return result.payload;
  }

  Future<RelayRpcResponseInternal> requestRawInternal(
    String method, {
    Map<String, dynamic>? params,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final channel = channelInternal;
    if (channel == null) {
      throw const WebRelayGatewayException('Relay not connected');
    }
    final id =
        '${DateTime.now().microsecondsSinceEpoch}-${requestCounterInternal++}';
    final completer = Completer<RelayRpcResponseInternal>();
    pendingInternal[id] = completer;
    channel.sink.add(
      jsonEncode(<String, dynamic>{
        'type': 'req',
        'id': id,
        'method': method,
        if (params != null && params.isNotEmpty) 'params': params,
      }),
    );
    try {
      return await completer.future.timeout(
        timeout,
        onTimeout: () =>
            throw WebRelayGatewayException('$method request timeout'),
      );
    } finally {
      pendingInternal.remove(id);
    }
  }

  Future<Map<String, dynamic>> buildConnectParamsInternal({
    required LocalDeviceIdentity identity,
    required String nonce,
    required String authToken,
    required String authPassword,
  }) async {
    const scopes = <String>[
      'operator.admin',
      'operator.read',
      'operator.write',
      'operator.approvals',
      'operator.pairing',
    ];
    const clientId = 'xworkmate-web';
    const clientMode = 'ui';
    final signedAtMs = DateTime.now().millisecondsSinceEpoch;
    final signaturePayload = identityManagerInternal.buildDeviceAuthPayloadV3(
      deviceId: identity.deviceId,
      clientId: clientId,
      clientMode: clientMode,
      role: 'operator',
      scopes: scopes,
      signedAtMs: signedAtMs,
      token: authToken,
      nonce: nonce,
      platform: 'web',
      deviceFamily: 'Browser',
    );
    final signature = await identityManagerInternal.signPayload(
      identity: identity,
      payload: signaturePayload,
    );

    return <String, dynamic>{
      'minProtocol': 3,
      'maxProtocol': 3,
      'client': <String, dynamic>{
        'id': clientId,
        'displayName': '$kSystemAppName Browser',
        'version': kAppVersion,
        'platform': 'web',
        'deviceFamily': 'Browser',
        'modelIdentifier': 'browser',
        'mode': clientMode,
        'instanceId':
            '$clientId-${identity.deviceId.substring(0, min(8, identity.deviceId.length))}',
      },
      'caps': const <String>['tool-events'],
      'commands': const <String>[],
      'permissions': const <String, bool>{},
      'role': 'operator',
      'scopes': scopes,
      if (authToken.isNotEmpty || authPassword.isNotEmpty)
        'auth': <String, dynamic>{
          if (authToken.isNotEmpty) 'token': authToken,
          if (authPassword.isNotEmpty) 'password': authPassword,
        },
      'locale': 'web',
      'userAgent': '$kSystemAppName/$kAppVersion web',
      'device': <String, dynamic>{
        'id': identity.deviceId,
        'publicKey': identity.publicKeyBase64Url,
        'signature': signature,
        'signedAt': signedAtMs,
        'nonce': nonce,
      },
    };
  }

  void handleIncomingInternal(dynamic raw, Completer<String> challenge) {
    final text = raw is String ? raw : utf8.decode(raw as List<int>);
    final decoded = jsonDecode(text) as Map<String, dynamic>;
    final type = stringValueInternal(decoded['type']);
    if (type == 'event') {
      final event = stringValueInternal(decoded['event']) ?? '';
      final payload = decoded['payload'];
      if (event == 'connect.challenge') {
        final nonce = stringValueInternal(asMapInternal(payload)['nonce']);
        if (nonce != null && !challenge.isCompleted) {
          challenge.complete(nonce);
        }
        return;
      }
      eventsInternal.add(
        GatewayPushEvent(
          event: event,
          payload: payload,
          sequence: intValueInternal(decoded['seq']),
        ),
      );
      return;
    }
    if (type != 'res') {
      return;
    }
    final id = stringValueInternal(decoded['id']);
    if (id == null) {
      return;
    }
    final completer = pendingInternal.remove(id);
    if (completer == null || completer.isCompleted) {
      return;
    }
    final ok = boolValueInternal(decoded['ok']) ?? false;
    if (!ok) {
      final error = asMapInternal(decoded['error']);
      completer.completeError(
        WebRelayGatewayException(
          stringValueInternal(error['message']) ?? 'Relay request failed',
        ),
      );
      return;
    }
    completer.complete(
      RelayRpcResponseInternal(
        ok: true,
        payload: decoded['payload'],
        error: asMapInternal(decoded['error']),
      ),
    );
  }

  ResolvedRelayEndpointInternal? resolveEndpointInternal(
    GatewayConnectionProfile profile,
  ) {
    final rawHost = profile.host.trim();
    if (rawHost.isEmpty) {
      return null;
    }
    final candidate = rawHost.contains('://')
        ? rawHost
        : '${profile.tls ? 'https' : 'http'}://$rawHost:${profile.port}';
    final uri = Uri.tryParse(candidate);
    if (uri == null || uri.host.trim().isEmpty) {
      return null;
    }
    final tls = switch (uri.scheme.trim().toLowerCase()) {
      'http' || 'ws' => false,
      _ => true,
    };
    return ResolvedRelayEndpointInternal(
      host: uri.host.trim(),
      port: uri.hasPort ? uri.port : (tls ? 443 : 80),
      tls: tls,
    );
  }

  Future<void> dispose() async {
    await disconnect();
    await eventsInternal.close();
  }
}

class WebRelayGatewayException implements Exception {
  const WebRelayGatewayException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ResolvedRelayEndpointInternal {
  const ResolvedRelayEndpointInternal({
    required this.host,
    required this.port,
    required this.tls,
  });

  final String host;
  final int port;
  final bool tls;
}

class RelayRpcResponseInternal {
  const RelayRpcResponseInternal({
    required this.ok,
    required this.payload,
    required this.error,
  });

  final bool ok;
  final dynamic payload;
  final Map<String, dynamic> error;
}

class WebRelayIdentityManagerInternal {
  final Ed25519 algorithmInternal = Ed25519();

  Future<LocalDeviceIdentity> loadOrCreate(WebStore store) async {
    final existing = await store.loadRelayDeviceIdentity();
    if (existing != null &&
        existing.deviceId.isNotEmpty &&
        existing.publicKeyBase64Url.isNotEmpty &&
        existing.privateKeyBase64Url.isNotEmpty) {
      return existing;
    }
    final keyPair = await algorithmInternal.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    final privateKeyBytes = await keyPair.extractPrivateKeyBytes();
    final publicKeyBytes = publicKey.bytes;
    final identity = LocalDeviceIdentity(
      deviceId: deriveDeviceIdInternal(publicKeyBytes),
      publicKeyBase64Url: base64UrlEncodeInternal(publicKeyBytes),
      privateKeyBase64Url: base64UrlEncodeInternal(privateKeyBytes),
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    await store.saveRelayDeviceIdentity(identity);
    return identity;
  }

  Future<String> signPayload({
    required LocalDeviceIdentity identity,
    required String payload,
  }) async {
    final publicKeyBytes = base64UrlDecodeInternal(identity.publicKeyBase64Url);
    final privateKeyBytes = base64UrlDecodeInternal(
      identity.privateKeyBase64Url,
    );
    final keyPair = SimpleKeyPairData(
      privateKeyBytes,
      publicKey: SimplePublicKey(publicKeyBytes, type: KeyPairType.ed25519),
      type: KeyPairType.ed25519,
    );
    final signature = await algorithmInternal.sign(
      utf8.encode(payload),
      keyPair: keyPair,
    );
    return base64UrlEncodeInternal(signature.bytes);
  }

  String buildDeviceAuthPayloadV3({
    required String deviceId,
    required String clientId,
    required String clientMode,
    required String role,
    required List<String> scopes,
    required int signedAtMs,
    required String token,
    required String nonce,
    required String platform,
    required String deviceFamily,
  }) {
    return <String>[
      'v3',
      deviceId,
      clientId,
      clientMode,
      role,
      scopes.join(','),
      '$signedAtMs',
      token,
      nonce,
      normalizeMetadataInternal(platform),
      normalizeMetadataInternal(deviceFamily),
    ].join('|');
  }

  String normalizeMetadataInternal(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    final buffer = StringBuffer();
    for (final rune in trimmed.runes) {
      if (rune >= 65 && rune <= 90) {
        buffer.writeCharCode(rune + 32);
      } else {
        buffer.writeCharCode(rune);
      }
    }
    return buffer.toString();
  }

  String deriveDeviceIdInternal(List<int> publicKeyBytes) {
    return crypto.sha256.convert(publicKeyBytes).toString();
  }

  String base64UrlEncodeInternal(List<int> value) {
    return base64Url.encode(value).replaceAll('=', '');
  }

  Uint8List base64UrlDecodeInternal(String value) {
    final normalized = value.replaceAll('-', '+').replaceAll('_', '/');
    final padded = normalized + '=' * ((4 - normalized.length % 4) % 4);
    return Uint8List.fromList(base64.decode(padded));
  }
}

Map<String, dynamic> asMapInternal(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.cast<String, dynamic>();
  }
  return const <String, dynamic>{};
}

List<Object?> asListInternal(Object? value) {
  if (value is List<Object?>) {
    return value;
  }
  if (value is List) {
    return value.cast<Object?>();
  }
  return const <Object?>[];
}

String? stringValueInternal(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

int? intValueInternal(Object? value) {
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '');
}

double? doubleValueInternal(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse(value?.toString() ?? '');
}

bool? boolValueInternal(Object? value) {
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  final normalized = value?.toString().trim().toLowerCase();
  if (normalized == 'true') {
    return true;
  }
  if (normalized == 'false') {
    return false;
  }
  return null;
}

List<String> stringListInternal(Object? value) {
  return asListInternal(
    value,
  ).map(stringValueInternal).whereType<String>().toList(growable: false);
}

String extractMessageTextInternal(Map<String, dynamic> message) {
  final directContent = message['content'];
  if (directContent is String) {
    return directContent;
  }
  final parts = <String>[];
  for (final part in asListInternal(directContent)) {
    final map = asMapInternal(part);
    final text =
        stringValueInternal(map['text']) ??
        stringValueInternal(map['thinking']);
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

String cronScheduleLabelInternal(Map<String, dynamic> schedule) {
  final type = stringValueInternal(schedule['type']) ?? 'cron';
  final every = intValueInternal(schedule['every']);
  final at = stringValueInternal(schedule['at']);
  final weekdays = stringListInternal(schedule['weekdays']);
  final parts = <String>[type];
  if (every != null && every > 0) {
    parts.add('every $every');
  }
  if (weekdays.isNotEmpty) {
    parts.add(weekdays.join(','));
  }
  if (at != null && at.isNotEmpty) {
    parts.add(at);
  }
  return parts.join(' · ');
}

String randomIdInternal() {
  final random = Random.secure();
  final timestamp = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
  final suffix = List<int>.generate(
    6,
    (_) => random.nextInt(256),
  ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  return '$timestamp-$suffix';
}
