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
  WebRelayGatewayClient(this._store);

  final WebStore _store;
  final StreamController<GatewayPushEvent> _events =
      StreamController<GatewayPushEvent>.broadcast();
  final Map<String, Completer<_RelayRpcResponse>> _pending =
      <String, Completer<_RelayRpcResponse>>{};
  final _WebRelayIdentityManager _identityManager = _WebRelayIdentityManager();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  int _requestCounter = 0;
  GatewayConnectionSnapshot _snapshot = GatewayConnectionSnapshot.initial(
    mode: RuntimeConnectionMode.unconfigured,
  );

  Stream<GatewayPushEvent> get events => _events.stream;
  GatewayConnectionSnapshot get snapshot => _snapshot;
  bool get isConnected => _snapshot.status == RuntimeConnectionStatus.connected;
  String get mainSessionKey => _snapshot.mainSessionKey ?? 'main';

  Future<void> connect({
    required GatewayConnectionProfile profile,
    required String authToken,
    required String authPassword,
  }) async {
    await disconnect();
    final targetMode = profile.mode == RuntimeConnectionMode.local
        ? RuntimeConnectionMode.local
        : RuntimeConnectionMode.remote;
    final endpoint = _resolveEndpoint(profile);
    if (endpoint == null) {
      _snapshot =
          GatewayConnectionSnapshot.initial(
            mode: targetMode,
          ).copyWith(
            status: RuntimeConnectionStatus.error,
            statusText: 'Missing relay endpoint',
            lastError: 'Configure relay host / port first.',
            lastErrorCode: 'MISSING_ENDPOINT',
          );
      throw const WebRelayGatewayException('Missing relay endpoint');
    }

    final identity = await _identityManager.loadOrCreate(_store);
    _snapshot =
        GatewayConnectionSnapshot.initial(
          mode: targetMode,
        ).copyWith(
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

    _channel = channel;
    _subscription = channel.stream.listen(
      (dynamic raw) => _handleIncoming(raw, challenge),
      onError: (Object error, StackTrace stackTrace) {
        _snapshot = _snapshot.copyWith(
          status: RuntimeConnectionStatus.error,
          statusText: 'Relay error',
          lastError: error.toString(),
          lastErrorCode: 'SOCKET_FAILURE',
        );
      },
      onDone: () {
        if (_snapshot.status == RuntimeConnectionStatus.connected) {
          _snapshot = _snapshot.copyWith(
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
      final result = await _requestRaw(
        'connect',
        params: await _buildConnectParams(
          identity: identity,
          nonce: nonce,
          authToken: authToken.trim(),
          authPassword: authPassword.trim(),
        ),
        timeout: const Duration(seconds: 12),
      );
      final payload = _asMap(result.payload);
      final auth = _asMap(payload['auth']);
      final snapshot = _asMap(payload['snapshot']);
      final sessionDefaults = _asMap(snapshot['sessionDefaults']);
      final server = _asMap(payload['server']);
      _snapshot = _snapshot.copyWith(
        status: RuntimeConnectionStatus.connected,
        statusText: 'Connected',
        mode: targetMode,
        serverName: _stringValue(server['host']),
        remoteAddress: '${endpoint.host}:${endpoint.port}',
        mainSessionKey:
            _stringValue(sessionDefaults['mainSessionKey']) ?? 'main',
        lastConnectedAtMs: DateTime.now().millisecondsSinceEpoch,
        authRole: _stringValue(auth['role']) ?? 'operator',
        authScopes: _stringList(auth['scopes']),
        clearLastError: true,
        clearLastErrorCode: true,
        clearLastErrorDetailCode: true,
      );
    } catch (error) {
      await disconnect();
      _snapshot = _snapshot.copyWith(
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
    for (final pending in _pending.values) {
      if (!pending.isCompleted) {
        pending.completeError(
          const WebRelayGatewayException('Relay request cancelled'),
        );
      }
    }
    _pending.clear();
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
    if (_snapshot.status != RuntimeConnectionStatus.offline) {
      _snapshot = _snapshot.copyWith(
        status: RuntimeConnectionStatus.offline,
        statusText: 'Offline',
        clearRemoteAddress: true,
      );
    }
  }

  Future<List<GatewaySessionSummary>> listSessions({int limit = 50}) async {
    final payload = _asMap(
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
    return _asList(payload['sessions'])
        .map((item) {
          final map = _asMap(item);
          return GatewaySessionSummary(
            key: _stringValue(map['key']) ?? 'main',
            kind: _stringValue(map['kind']),
            displayName:
                _stringValue(map['displayName']) ?? _stringValue(map['label']),
            surface: _stringValue(map['surface']),
            subject: _stringValue(map['subject']),
            room: _stringValue(map['room']),
            space: _stringValue(map['space']),
            updatedAtMs: _doubleValue(map['updatedAt']),
            sessionId: _stringValue(map['sessionId']),
            systemSent: _boolValue(map['systemSent']),
            abortedLastRun: _boolValue(map['abortedLastRun']),
            thinkingLevel: _stringValue(map['thinkingLevel']),
            verboseLevel: _stringValue(map['verboseLevel']),
            inputTokens: _intValue(map['inputTokens']),
            outputTokens: _intValue(map['outputTokens']),
            totalTokens: _intValue(map['totalTokens']),
            model: _stringValue(map['model']),
            contextTokens: _intValue(map['contextTokens']),
            derivedTitle: _stringValue(map['derivedTitle']),
            lastMessagePreview: _stringValue(map['lastMessagePreview']),
          );
        })
        .toList(growable: false);
  }

  Future<List<GatewayChatMessage>> loadHistory(
    String sessionKey, {
    int limit = 120,
  }) async {
    final payload = _asMap(
      await request(
        'chat.history',
        params: <String, dynamic>{'sessionKey': sessionKey, 'limit': limit},
      ),
    );
    return _asList(payload['messages'])
        .map((item) {
          final map = _asMap(item);
          return GatewayChatMessage(
            id: _randomId(),
            role: _stringValue(map['role']) ?? 'assistant',
            text: _extractMessageText(map),
            timestampMs: _doubleValue(map['timestamp']),
            toolCallId:
                _stringValue(map['toolCallId']) ??
                _stringValue(map['tool_call_id']),
            toolName:
                _stringValue(map['toolName']) ?? _stringValue(map['tool_name']),
            stopReason: _stringValue(map['stopReason']),
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
    final runId = _randomId();
    final normalizedMetadata = <String, dynamic>{
      for (final entry in metadata.entries)
        if (entry.key.trim().isNotEmpty) entry.key: entry.value,
    };
    final payload = _asMap(
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
    return _stringValue(payload['runId']) ?? runId;
  }

  Future<List<GatewayModelSummary>> listModels() async {
    final payload = _asMap(await request('models.list'));
    return _asList(payload['models'])
        .map((item) {
          final map = _asMap(item);
          return GatewayModelSummary(
            id: _stringValue(map['id']) ?? 'unknown',
            name:
                _stringValue(map['name']) ??
                _stringValue(map['id']) ??
                'unknown',
            provider: _stringValue(map['provider']) ?? 'relay',
            contextWindow: _intValue(map['contextWindow']),
            maxOutputTokens: _intValue(map['maxOutputTokens']),
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
      throw const WebRelayGatewayException('Relay not connected');
    }
    final result = await _requestRaw(method, params: params, timeout: timeout);
    return result.payload;
  }

  Future<_RelayRpcResponse> _requestRaw(
    String method, {
    Map<String, dynamic>? params,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final channel = _channel;
    if (channel == null) {
      throw const WebRelayGatewayException('Relay not connected');
    }
    final id = '${DateTime.now().microsecondsSinceEpoch}-${_requestCounter++}';
    final completer = Completer<_RelayRpcResponse>();
    _pending[id] = completer;
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
      _pending.remove(id);
    }
  }

  Future<Map<String, dynamic>> _buildConnectParams({
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
    final signaturePayload = _identityManager.buildDeviceAuthPayloadV3(
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
    final signature = await _identityManager.signPayload(
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

  void _handleIncoming(dynamic raw, Completer<String> challenge) {
    final text = raw is String ? raw : utf8.decode(raw as List<int>);
    final decoded = jsonDecode(text) as Map<String, dynamic>;
    final type = _stringValue(decoded['type']);
    if (type == 'event') {
      final event = _stringValue(decoded['event']) ?? '';
      final payload = decoded['payload'];
      if (event == 'connect.challenge') {
        final nonce = _stringValue(_asMap(payload)['nonce']);
        if (nonce != null && !challenge.isCompleted) {
          challenge.complete(nonce);
        }
        return;
      }
      _events.add(
        GatewayPushEvent(
          event: event,
          payload: payload,
          sequence: _intValue(decoded['seq']),
        ),
      );
      return;
    }
    if (type != 'res') {
      return;
    }
    final id = _stringValue(decoded['id']);
    if (id == null) {
      return;
    }
    final completer = _pending.remove(id);
    if (completer == null || completer.isCompleted) {
      return;
    }
    final ok = _boolValue(decoded['ok']) ?? false;
    if (!ok) {
      final error = _asMap(decoded['error']);
      completer.completeError(
        WebRelayGatewayException(
          _stringValue(error['message']) ?? 'Relay request failed',
        ),
      );
      return;
    }
    completer.complete(
      _RelayRpcResponse(
        ok: true,
        payload: decoded['payload'],
        error: _asMap(decoded['error']),
      ),
    );
  }

  _ResolvedRelayEndpoint? _resolveEndpoint(GatewayConnectionProfile profile) {
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
    return _ResolvedRelayEndpoint(
      host: uri.host.trim(),
      port: uri.hasPort ? uri.port : (tls ? 443 : 80),
      tls: tls,
    );
  }

  Future<void> dispose() async {
    await disconnect();
    await _events.close();
  }
}

class WebRelayGatewayException implements Exception {
  const WebRelayGatewayException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _ResolvedRelayEndpoint {
  const _ResolvedRelayEndpoint({
    required this.host,
    required this.port,
    required this.tls,
  });

  final String host;
  final int port;
  final bool tls;
}

class _RelayRpcResponse {
  const _RelayRpcResponse({
    required this.ok,
    required this.payload,
    required this.error,
  });

  final bool ok;
  final dynamic payload;
  final Map<String, dynamic> error;
}

class _WebRelayIdentityManager {
  final Ed25519 _algorithm = Ed25519();

  Future<LocalDeviceIdentity> loadOrCreate(WebStore store) async {
    final existing = await store.loadRelayDeviceIdentity();
    if (existing != null &&
        existing.deviceId.isNotEmpty &&
        existing.publicKeyBase64Url.isNotEmpty &&
        existing.privateKeyBase64Url.isNotEmpty) {
      return existing;
    }
    final keyPair = await _algorithm.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    final privateKeyBytes = await keyPair.extractPrivateKeyBytes();
    final publicKeyBytes = publicKey.bytes;
    final identity = LocalDeviceIdentity(
      deviceId: _deriveDeviceId(publicKeyBytes),
      publicKeyBase64Url: _base64UrlEncode(publicKeyBytes),
      privateKeyBase64Url: _base64UrlEncode(privateKeyBytes),
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    await store.saveRelayDeviceIdentity(identity);
    return identity;
  }

  Future<String> signPayload({
    required LocalDeviceIdentity identity,
    required String payload,
  }) async {
    final publicKeyBytes = _base64UrlDecode(identity.publicKeyBase64Url);
    final privateKeyBytes = _base64UrlDecode(identity.privateKeyBase64Url);
    final keyPair = SimpleKeyPairData(
      privateKeyBytes,
      publicKey: SimplePublicKey(publicKeyBytes, type: KeyPairType.ed25519),
      type: KeyPairType.ed25519,
    );
    final signature = await _algorithm.sign(
      utf8.encode(payload),
      keyPair: keyPair,
    );
    return _base64UrlEncode(signature.bytes);
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
      _normalizeMetadata(platform),
      _normalizeMetadata(deviceFamily),
    ].join('|');
  }

  String _normalizeMetadata(String value) {
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

  String _deriveDeviceId(List<int> publicKeyBytes) {
    return crypto.sha256.convert(publicKeyBytes).toString();
  }

  String _base64UrlEncode(List<int> value) {
    return base64Url.encode(value).replaceAll('=', '');
  }

  Uint8List _base64UrlDecode(String value) {
    final normalized = value.replaceAll('-', '+').replaceAll('_', '/');
    final padded = normalized + '=' * ((4 - normalized.length % 4) % 4);
    return Uint8List.fromList(base64.decode(padded));
  }
}

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.cast<String, dynamic>();
  }
  return const <String, dynamic>{};
}

List<Object?> _asList(Object? value) {
  if (value is List<Object?>) {
    return value;
  }
  if (value is List) {
    return value.cast<Object?>();
  }
  return const <Object?>[];
}

String? _stringValue(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

int? _intValue(Object? value) {
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '');
}

double? _doubleValue(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse(value?.toString() ?? '');
}

bool? _boolValue(Object? value) {
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

List<String> _stringList(Object? value) {
  return _asList(
    value,
  ).map(_stringValue).whereType<String>().toList(growable: false);
}

String _extractMessageText(Map<String, dynamic> message) {
  final directContent = message['content'];
  if (directContent is String) {
    return directContent;
  }
  final parts = <String>[];
  for (final part in _asList(directContent)) {
    final map = _asMap(part);
    final text = _stringValue(map['text']) ?? _stringValue(map['thinking']);
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
