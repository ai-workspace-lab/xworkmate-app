import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'runtime_models.dart';

class GatewayAcpException implements Exception {
  const GatewayAcpException(this.message, {this.code, this.details});

  final String message;
  final String? code;
  final Object? details;

  @override
  String toString() => code == null ? message : '$code: $message';
}

class GatewayAcpCapabilities {
  const GatewayAcpCapabilities({
    required this.singleAgent,
    required this.multiAgent,
    required this.providers,
    required this.raw,
  });

  const GatewayAcpCapabilities.empty()
    : singleAgent = false,
      multiAgent = false,
      providers = const <SingleAgentProvider>{},
      raw = const <String, dynamic>{};

  final bool singleAgent;
  final bool multiAgent;
  final Set<SingleAgentProvider> providers;
  final Map<String, dynamic> raw;
}

class _GatewayAcpSessionUpdate {
  const _GatewayAcpSessionUpdate({
    required this.method,
    required this.sessionId,
    required this.threadId,
    required this.turnId,
    required this.type,
    required this.textDelta,
    required this.sequence,
    required this.payload,
  });

  final String method;
  final String sessionId;
  final String threadId;
  final String turnId;
  final String type;
  final String textDelta;
  final int? sequence;
  final Map<String, dynamic> payload;
}

class GatewayAcpMultiAgentRequest {
  const GatewayAcpMultiAgentRequest({
    required this.sessionId,
    required this.threadId,
    required this.prompt,
    required this.workingDirectory,
    required this.attachments,
    required this.selectedSkills,
    required this.aiGatewayBaseUrl,
    required this.aiGatewayApiKey,
    required this.resumeSession,
  });

  final String sessionId;
  final String threadId;
  final String prompt;
  final String workingDirectory;
  final List<CollaborationAttachment> attachments;
  final List<String> selectedSkills;
  final String aiGatewayBaseUrl;
  final String aiGatewayApiKey;
  final bool resumeSession;
}

class GatewayAcpClient {
  GatewayAcpClient({required this.endpointResolver});

  final Uri? Function() endpointResolver;

  int _requestCounter = 0;
  GatewayAcpCapabilities _cachedCapabilities =
      const GatewayAcpCapabilities.empty();
  DateTime? _capabilitiesRefreshedAt;

  Future<GatewayAcpCapabilities> loadCapabilities({
    bool forceRefresh = false,
    Uri? endpointOverride,
  }) async {
    if (!forceRefresh &&
        _capabilitiesRefreshedAt != null &&
        DateTime.now().difference(_capabilitiesRefreshedAt!) <
            const Duration(seconds: 15)) {
      return _cachedCapabilities;
    }

    final response = await _requestWithFallback(
      _GatewayAcpRpcRequest(
        id: _nextRequestId('capabilities'),
        method: 'acp.capabilities',
        params: const <String, dynamic>{},
      ),
      onNotification: (_) {},
      endpointOverride: endpointOverride,
    );
    final result = asMap(response['result']);
    final caps = asMap(result['capabilities']);
    final providers = <SingleAgentProvider>{};
    for (final raw in <Object?>[
      ...asList(result['providers']),
      ...asList(caps['providers']),
    ]) {
      if (raw == null) {
        continue;
      }
      final provider = SingleAgentProviderCopy.fromJsonValue(
        raw.toString().trim().toLowerCase(),
      );
      if (provider != SingleAgentProvider.auto) {
        providers.add(provider);
      }
    }
    final singleAgent =
        boolValue(result['singleAgent']) ??
        boolValue(caps['single_agent']) ??
        providers.isNotEmpty;
    final multiAgent =
        boolValue(result['multiAgent']) ??
        boolValue(caps['multi_agent']) ??
        true;
    _cachedCapabilities = GatewayAcpCapabilities(
      singleAgent: singleAgent,
      multiAgent: multiAgent,
      providers: providers,
      raw: result,
    );
    _capabilitiesRefreshedAt = DateTime.now();
    return _cachedCapabilities;
  }

  Stream<MultiAgentRunEvent> runMultiAgent(
    GatewayAcpMultiAgentRequest request,
  ) {
    final controller = StreamController<MultiAgentRunEvent>();
    unawaited(() async {
      final capabilities = await loadCapabilities();
      if (!capabilities.multiAgent) {
        throw const GatewayAcpException(
          'Multi-agent capability is unavailable from ACP',
          code: 'ACP_MULTI_AGENT_UNAVAILABLE',
        );
      }
      final rpcRequest = _GatewayAcpRpcRequest(
        id: _nextRequestId('multi-agent'),
        method: request.resumeSession ? 'session.message' : 'session.start',
        params: <String, dynamic>{
          'sessionId': request.sessionId,
          'threadId': request.threadId,
          'mode': 'multi-agent',
          'taskPrompt': request.prompt,
          'workingDirectory': request.workingDirectory,
          'attachments': request.attachments
              .map(
                (item) => <String, dynamic>{
                  'name': item.name,
                  'description': item.description,
                  'path': item.path,
                },
              )
              .toList(growable: false),
          'selectedSkills': request.selectedSkills,
          'aiGatewayBaseUrl': request.aiGatewayBaseUrl,
          'aiGatewayApiKey': request.aiGatewayApiKey,
        },
      );
      var lastSequence = -1;
      try {
        final response = await _requestWithFallback(
          rpcRequest,
          onNotification: (notification) {
            final event = _multiAgentEventFromNotification(notification);
            if (event == null) {
              return;
            }
            final seq =
                (event.data['seq'] as num?)?.toInt() ??
                (event.data['sequence'] as num?)?.toInt();
            if (seq != null && seq <= lastSequence) {
              return;
            }
            if (seq != null) {
              lastSequence = seq;
            }
            if (!controller.isClosed) {
              controller.add(event);
            }
          },
        );
        final result = asMap(response['result']);
        if (!controller.isClosed) {
          controller.add(
            MultiAgentRunEvent(
              type: 'result',
              title: '',
              message: stringValue(result['summary']) ?? '',
              pending: false,
              error: !(boolValue(result['success']) ?? false),
              data: result,
            ),
          );
        }
      } catch (error) {
        if (!controller.isClosed) {
          controller.add(
            MultiAgentRunEvent(
              type: 'result',
              title: '',
              message: error.toString(),
              pending: false,
              error: true,
              data: <String, dynamic>{'error': error.toString()},
            ),
          );
        }
      } finally {
        await controller.close();
      }
    }());
    return controller.stream;
  }

  Future<void> cancelSession({
    required String sessionId,
    required String threadId,
    Uri? endpointOverride,
  }) async {
    await _requestWithFallback(
      _GatewayAcpRpcRequest(
        id: _nextRequestId('cancel'),
        method: 'session.cancel',
        params: <String, dynamic>{'sessionId': sessionId, 'threadId': threadId},
      ),
      onNotification: (_) {},
      endpointOverride: endpointOverride,
    );
  }

  Future<void> closeSession({
    required String sessionId,
    required String threadId,
    Uri? endpointOverride,
  }) async {
    await _requestWithFallback(
      _GatewayAcpRpcRequest(
        id: _nextRequestId('close'),
        method: 'session.close',
        params: <String, dynamic>{'sessionId': sessionId, 'threadId': threadId},
      ),
      onNotification: (_) {},
      endpointOverride: endpointOverride,
    );
  }

  Future<Map<String, dynamic>> request({
    required String method,
    required Map<String, dynamic> params,
    void Function(Map<String, dynamic>)? onNotification,
    Uri? endpointOverride,
  }) async {
    return _requestWithFallback(
      _GatewayAcpRpcRequest(
        id: _nextRequestId(method),
        method: method,
        params: params,
      ),
      onNotification: onNotification ?? (_) {},
      endpointOverride: endpointOverride,
    );
  }

  Future<void> dispose() async {}

  Future<Map<String, dynamic>> _requestWithFallback(
    _GatewayAcpRpcRequest request, {
    required void Function(Map<String, dynamic>) onNotification,
    Uri? endpointOverride,
  }) async {
    try {
      return await _requestViaWebSocket(
        request,
        onNotification: onNotification,
        endpointOverride: endpointOverride,
      );
    } catch (_) {
      return _requestViaHttp(
        request,
        onNotification: onNotification,
        endpointOverride: endpointOverride,
      );
    }
  }

  Future<Map<String, dynamic>> _requestViaWebSocket(
    _GatewayAcpRpcRequest request, {
    required void Function(Map<String, dynamic>) onNotification,
    Uri? endpointOverride,
  }) async {
    final endpoint = _resolveWebSocketRpcEndpoint(endpointOverride);
    if (endpoint == null) {
      throw const GatewayAcpException(
        'Missing ACP endpoint',
        code: 'ACP_ENDPOINT_MISSING',
      );
    }

    final socket = await WebSocket.connect(endpoint.toString()).timeout(
      const Duration(seconds: 6),
      onTimeout: () => throw const GatewayAcpException(
        'ACP websocket connect timeout',
        code: 'ACP_WS_CONNECT_TIMEOUT',
      ),
    );
    final completer = Completer<Map<String, dynamic>>();
    late final StreamSubscription<dynamic> subscription;
    subscription = socket.listen(
      (raw) {
        final json = _decodeMap(raw);
        final id = stringValue(json['id']);
        final method = stringValue(json['method']) ?? '';
        if (id == request.id &&
            (json.containsKey('result') || json.containsKey('error'))) {
          if (!completer.isCompleted) {
            completer.complete(json);
          }
          return;
        }
        if (method.isNotEmpty) {
          onNotification(json);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(
            GatewayAcpException(error.toString(), code: 'ACP_WS_RUNTIME_ERROR'),
          );
        }
      },
      onDone: () {
        if (!completer.isCompleted) {
          completer.completeError(
            const GatewayAcpException(
              'ACP websocket closed before response',
              code: 'ACP_WS_EARLY_CLOSE',
            ),
          );
        }
      },
      cancelOnError: true,
    );

    socket.add(
      jsonEncode(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': request.id,
        'method': request.method,
        'params': request.params,
      }),
    );
    try {
      final response = await completer.future.timeout(
        const Duration(seconds: 120),
      );
      _throwIfJsonRpcError(response);
      return response;
    } finally {
      await subscription.cancel();
      await socket.close();
    }
  }

  Future<Map<String, dynamic>> _requestViaHttp(
    _GatewayAcpRpcRequest request, {
    required void Function(Map<String, dynamic>) onNotification,
    Uri? endpointOverride,
  }) async {
    final endpoint = _resolveHttpRpcEndpoint(endpointOverride);
    if (endpoint == null) {
      throw const GatewayAcpException(
        'Missing ACP HTTP endpoint',
        code: 'ACP_HTTP_ENDPOINT_MISSING',
      );
    }

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final httpRequest = await client.postUrl(endpoint);
      httpRequest.headers.set(
        HttpHeaders.contentTypeHeader,
        'application/json; charset=utf-8',
      );
      httpRequest.headers.set(
        HttpHeaders.acceptHeader,
        'text/event-stream, application/json',
      );
      httpRequest.add(
        utf8.encode(
          jsonEncode(<String, dynamic>{
            'jsonrpc': '2.0',
            'id': request.id,
            'method': request.method,
            'params': request.params,
          }),
        ),
      );
      final response = await httpRequest.close().timeout(
        const Duration(seconds: 120),
      );
      final contentType =
          response.headers.contentType?.mimeType.toLowerCase() ??
          response.headers
              .value(HttpHeaders.contentTypeHeader)
              ?.toLowerCase() ??
          '';
      if (contentType.contains('text/event-stream')) {
        return _consumeSseRpcResponse(
          response: response,
          requestId: request.id,
          onNotification: onNotification,
        );
      }
      final body = await response.transform(utf8.decoder).join();
      final decoded = _decodeMap(body);
      _throwIfJsonRpcError(decoded);
      return decoded;
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> _consumeSseRpcResponse({
    required HttpClientResponse response,
    required String requestId,
    required void Function(Map<String, dynamic>) onNotification,
  }) async {
    final completer = Completer<Map<String, dynamic>>();
    final eventLines = <String>[];

    void consumeEventPayload(String payload) {
      final trimmed = payload.trim();
      if (trimmed.isEmpty || trimmed == '[DONE]') {
        return;
      }
      final json = _decodeMap(trimmed);
      if (stringValue(json['id']) == requestId &&
          (json.containsKey('result') || json.containsKey('error'))) {
        if (!completer.isCompleted) {
          completer.complete(json);
        }
        return;
      }
      if ((stringValue(json['method']) ?? '').isNotEmpty) {
        onNotification(json);
      }
    }

    await for (final line
        in response.transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.isEmpty) {
        if (eventLines.isNotEmpty) {
          consumeEventPayload(eventLines.join('\n'));
          eventLines.clear();
        }
        continue;
      }
      if (line.startsWith('data:')) {
        eventLines.add(line.substring(5).trimLeft());
      }
    }

    if (eventLines.isNotEmpty) {
      consumeEventPayload(eventLines.join('\n'));
    }
    if (!completer.isCompleted) {
      throw const GatewayAcpException(
        'ACP SSE ended without JSON-RPC response',
        code: 'ACP_SSE_NO_RESULT',
      );
    }
    final resolved = await completer.future;
    _throwIfJsonRpcError(resolved);
    return resolved;
  }

  _GatewayAcpSessionUpdate? _sessionUpdateFromNotification(
    Map<String, dynamic> notification,
  ) {
    final method = stringValue(notification['method']) ?? '';
    if (method != 'session.update' && method != 'acp.session.update') {
      return null;
    }
    final params = asMap(notification['params']);
    return _GatewayAcpSessionUpdate(
      method: method,
      sessionId: stringValue(params['sessionId']) ?? '',
      threadId: stringValue(params['threadId']) ?? '',
      turnId: stringValue(params['turnId']) ?? '',
      type:
          stringValue(params['type']) ??
          stringValue(params['event']) ??
          'status',
      textDelta:
          stringValue(params['delta']) ??
          stringValue(params['text']) ??
          stringValue(asMap(params['message'])['content']) ??
          '',
      sequence: intValue(params['seq']) ?? intValue(notification['seq']),
      payload: params,
    );
  }

  MultiAgentRunEvent? _multiAgentEventFromNotification(
    Map<String, dynamic> notification,
  ) {
    final method = stringValue(notification['method']) ?? '';
    if (method == 'multi_agent.event' || method == 'acp.multi_agent.event') {
      return MultiAgentRunEvent.fromJson(asMap(notification['params']));
    }
    final update = _sessionUpdateFromNotification(notification);
    if (update == null || update.payload['mode'] != 'multi-agent') {
      return null;
    }
    return MultiAgentRunEvent(
      type: update.type,
      title: stringValue(update.payload['title']) ?? '',
      message: update.textDelta.isNotEmpty
          ? update.textDelta
          : stringValue(update.payload['message']) ?? '',
      pending: boolValue(update.payload['pending']) ?? false,
      error: boolValue(update.payload['error']) ?? false,
      role: stringValue(update.payload['role']),
      iteration: intValue(update.payload['iteration']),
      score: intValue(update.payload['score']),
      data: update.payload,
    );
  }

  Map<String, dynamic> asMap(Object? raw) {
    if (raw is Map<String, dynamic>) {
      return raw;
    }
    if (raw is Map) {
      return raw.cast<String, dynamic>();
    }
    return const <String, dynamic>{};
  }

  List<Object?> asList(Object? raw) {
    if (raw is List<Object?>) {
      return raw;
    }
    if (raw is List) {
      return raw.cast<Object?>();
    }
    return const <Object?>[];
  }

  String? stringValue(Object? raw) {
    if (raw == null) {
      return null;
    }
    final value = raw.toString().trim();
    return value.isEmpty ? null : value;
  }

  bool? boolValue(Object? raw) {
    if (raw is bool) {
      return raw;
    }
    if (raw is num) {
      return raw != 0;
    }
    final text = raw?.toString().trim().toLowerCase();
    if (text == null || text.isEmpty) {
      return null;
    }
    if (text == 'true' || text == '1' || text == 'yes') {
      return true;
    }
    if (text == 'false' || text == '0' || text == 'no') {
      return false;
    }
    return null;
  }

  int? intValue(Object? raw) {
    if (raw is int) {
      return raw;
    }
    if (raw is num) {
      return raw.toInt();
    }
    return int.tryParse(raw?.toString().trim() ?? '');
  }

  void _throwIfJsonRpcError(Map<String, dynamic> envelope) {
    final error = asMap(envelope['error']);
    if (error.isEmpty) {
      return;
    }
    throw GatewayAcpException(
      stringValue(error['message']) ?? 'ACP JSON-RPC request failed',
      code: stringValue(error['code']),
      details: error['data'],
    );
  }

  Map<String, dynamic> _decodeMap(dynamic raw) {
    if (raw is Map<String, dynamic>) {
      return raw;
    }
    if (raw is Map) {
      return raw.cast<String, dynamic>();
    }
    final text = raw is String ? raw : utf8.decode(raw as List<int>);
    final decoded = jsonDecode(_extractFirstJsonDocument(text));
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.cast<String, dynamic>();
    }
    return const <String, dynamic>{};
  }

  Uri? _resolveWebSocketRpcEndpoint([Uri? endpointOverride]) {
    final base = endpointOverride ?? endpointResolver();
    if (base == null) {
      return null;
    }
    final secure = base.scheme.toLowerCase() == 'https';
    return base.replace(
      scheme: secure ? 'wss' : 'ws',
      path: '/acp',
      query: null,
      fragment: null,
    );
  }

  Uri? _resolveHttpRpcEndpoint([Uri? endpointOverride]) {
    final base = endpointOverride ?? endpointResolver();
    if (base == null) {
      return null;
    }
    final scheme = base.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      return null;
    }
    return base.replace(path: '/acp/rpc', query: null, fragment: null);
  }

  String _nextRequestId(String method) {
    return '${DateTime.now().microsecondsSinceEpoch}-$method-${_requestCounter++}';
  }

  String _extractFirstJsonDocument(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Empty response body');
    }
    final objectStart = trimmed.indexOf('{');
    final arrayStart = trimmed.indexOf('[');
    var start = -1;
    if (objectStart >= 0 && arrayStart >= 0) {
      start = objectStart < arrayStart ? objectStart : arrayStart;
    } else if (objectStart >= 0) {
      start = objectStart;
    } else if (arrayStart >= 0) {
      start = arrayStart;
    }
    if (start < 0) {
      throw const FormatException('Missing JSON document');
    }

    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var index = start; index < trimmed.length; index++) {
      final char = trimmed[index];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (char == r'\') {
          escaped = true;
        } else if (char == '"') {
          inString = false;
        }
        continue;
      }
      if (char == '"') {
        inString = true;
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
}

class _GatewayAcpRpcRequest {
  const _GatewayAcpRpcRequest({
    required this.id,
    required this.method,
    required this.params,
  });

  final String id;
  final String method;
  final Map<String, dynamic> params;
}
