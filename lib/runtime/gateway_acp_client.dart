import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'acp_endpoint_paths.dart';
import 'runtime_models.dart';

const int gatewayAcpHttpHandshakeInterruptedRetryCount = 5;
const int gatewayAcpHttpConnectFailureRetryCount = 2;
const Duration gatewayAcpHttpConnectTimeout = Duration(seconds: 12);
const String gatewayAcpHttpHandshakeInterruptedCode =
    'ACP_HTTP_HANDSHAKE_INTERRUPTED';
const String gatewayAcpHttpConnectTimeoutCode = 'ACP_HTTP_CONNECT_TIMEOUT';
const String gatewayAcpHttpConnectFailedCode = 'ACP_HTTP_CONNECT_FAILED';

class GatewayAcpException implements Exception {
  const GatewayAcpException(
    this.message, {
    this.code,
    this.detailCode,
    this.details,
  });

  final String message;
  final String? code;
  final String? detailCode;
  final Object? details;

  @override
  String toString() => code == null ? message : '$code: $message';
}

class GatewayAcpCapabilities {
  const GatewayAcpCapabilities({
    required this.singleAgent,
    required this.multiAgent,
    required this.availableExecutionTargets,
    required this.providerCatalog,
    required this.gatewayProviderCatalog,
    required this.raw,
    this.diagnostics = const <String, dynamic>{},
  });

  const GatewayAcpCapabilities.empty()
    : singleAgent = false,
      multiAgent = false,
      availableExecutionTargets = const <AssistantExecutionTarget>[],
      providerCatalog = const <SingleAgentProvider>[],
      gatewayProviderCatalog = const <SingleAgentProvider>[],
      raw = const <String, dynamic>{},
      diagnostics = const <String, dynamic>{};

  final bool singleAgent;
  final bool multiAgent;
  final List<AssistantExecutionTarget> availableExecutionTargets;
  final List<SingleAgentProvider> providerCatalog;
  final List<SingleAgentProvider> gatewayProviderCatalog;
  final Map<String, dynamic> raw;
  final Map<String, dynamic> diagnostics;
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

enum _GatewayAcpHttpRequestPhase {
  connect,
  write,
  waitingForResponse,
  bodyRead,
}

class GatewayAcpMultiAgentRequest {
  const GatewayAcpMultiAgentRequest({
    required this.sessionId,
    required this.threadId,
    required this.prompt,
    required this.workingDirectory,
    required this.attachments,
    required this.selectedSkills,
    required this.resumeSession,
  });

  final String sessionId;
  final String threadId;
  final String prompt;
  final String workingDirectory;
  final List<CollaborationAttachment> attachments;
  final List<String> selectedSkills;
  final bool resumeSession;
}

class GatewayAcpClient {
  GatewayAcpClient({
    required this.endpointResolver,
    this.authorizationResolver,
  });

  final Uri? Function() endpointResolver;
  final Future<String?> Function(Uri endpoint)? authorizationResolver;

  int _requestCounter = 0;
  GatewayAcpCapabilities _cachedCapabilities =
      const GatewayAcpCapabilities.empty();
  DateTime? _capabilitiesRefreshedAt;

  Future<GatewayAcpCapabilities> loadCapabilities({
    bool forceRefresh = false,
    Uri? endpointOverride,
    String authorizationOverride = '',
  }) async {
    if (!forceRefresh &&
        _capabilitiesRefreshedAt != null &&
        DateTime.now().difference(_capabilitiesRefreshedAt!) <
            const Duration(seconds: 15)) {
      return _cachedCapabilities;
    }

    final response = await _requestForResolvedEndpoint(
      _GatewayAcpRpcRequest(
        id: _nextRequestId('capabilities'),
        method: 'acp.capabilities',
        params: const <String, dynamic>{},
      ),
      onNotification: (_) {},
      endpointOverride: endpointOverride,
      authorizationOverride: authorizationOverride,
    );
    final result = asMap(response['result']);
    final caps = asMap(result['capabilities']);
    final providerCatalog = _parseProviderCatalog(
      result['providerCatalog'] ?? caps['providerCatalog'],
      defaultTarget: AssistantExecutionTarget.agent,
    );
    final gatewayProviderCatalog = _parseProviderCatalog(
      result['gatewayProviders'] ?? caps['gatewayProviders'],
      defaultTarget: AssistantExecutionTarget.gateway,
    );
    final singleAgent =
        boolValue(result['singleAgent']) ??
        boolValue(caps['single_agent']) ??
        providerCatalog.isNotEmpty;
    final multiAgent =
        boolValue(result['multiAgent']) ??
        boolValue(caps['multi_agent']) ??
        true;
    _cachedCapabilities = GatewayAcpCapabilities(
      singleAgent: singleAgent,
      multiAgent: multiAgent,
      availableExecutionTargets: _parseAvailableExecutionTargets(
        result['availableExecutionTargets'] ??
            caps['availableExecutionTargets'],
        singleAgent: singleAgent,
        gatewayProviderCatalog: gatewayProviderCatalog,
      ),
      providerCatalog: providerCatalog,
      gatewayProviderCatalog: gatewayProviderCatalog,
      raw: result,
      diagnostics: asMap(response['_xworkmateDiagnostics']),
    );
    _capabilitiesRefreshedAt = DateTime.now();
    return _cachedCapabilities;
  }

  List<SingleAgentProvider> _parseProviderCatalog(
    Object? raw, {
    required AssistantExecutionTarget defaultTarget,
  }) {
    final providers = <SingleAgentProvider>[];
    for (final item in asList(raw)) {
      final entry = asMap(item);
      final providerId = entry['providerId']?.toString().trim() ?? '';
      if (providerId.isEmpty) {
        continue;
      }
      final label = entry['label']?.toString().trim();
      final providerDisplay = asMap(entry['providerDisplay']);
      final targets = _parseProviderTargets(
        entry['targets'] ?? entry['executionTarget'],
        defaultTarget: defaultTarget,
      );
      final provider = SingleAgentProviderCopy.fromJsonValue(
        providerId,
        label: label?.isNotEmpty == true ? label : null,
        badge: entry['badge']?.toString().trim().isNotEmpty == true
            ? entry['badge']?.toString().trim()
            : providerDisplay['badge']?.toString().trim(),
        logoEmoji: entry['logoEmoji']?.toString().trim().isNotEmpty == true
            ? entry['logoEmoji']?.toString().trim()
            : providerDisplay['logoEmoji']?.toString().trim(),
        supportedTargets: targets,
        enabled: boolValue(entry['enabled']) ?? true,
        unavailableReason:
            entry['unavailableReason']?.toString().trim().isNotEmpty == true
            ? entry['unavailableReason']?.toString().trim()
            : '',
      );
      if (!provider.isUnspecified) {
        providers.add(provider);
      }
    }
    return normalizeSingleAgentProviderList(providers);
  }

  List<AssistantExecutionTarget> _parseAvailableExecutionTargets(
    Object? raw, {
    required bool singleAgent,
    required List<SingleAgentProvider> gatewayProviderCatalog,
  }) {
    final parsed = <AssistantExecutionTarget>[];
    for (final item in asList(raw)) {
      final normalized = item?.toString().trim().toLowerCase() ?? '';
      if (normalized == 'agent' || normalized == 'single-agent') {
        if (!parsed.contains(AssistantExecutionTarget.agent)) {
          parsed.add(AssistantExecutionTarget.agent);
        }
      } else if (normalized == 'gateway') {
        if (!parsed.contains(AssistantExecutionTarget.gateway)) {
          parsed.add(AssistantExecutionTarget.gateway);
        }
      }
    }
    if (parsed.isNotEmpty) {
      return parsed;
    }
    if (singleAgent) {
      parsed.add(AssistantExecutionTarget.agent);
    }
    if (gatewayProviderCatalog.isNotEmpty) {
      parsed.add(AssistantExecutionTarget.gateway);
    }
    return parsed;
  }

  List<AssistantExecutionTarget> _parseProviderTargets(
    Object? raw, {
    required AssistantExecutionTarget defaultTarget,
  }) {
    final parsed = <AssistantExecutionTarget>[];
    final items = raw is List ? raw : <Object?>[raw];
    for (final item in items) {
      final normalized = item?.toString().trim().toLowerCase() ?? '';
      if (normalized == 'agent' || normalized == 'single-agent') {
        if (!parsed.contains(AssistantExecutionTarget.agent)) {
          parsed.add(AssistantExecutionTarget.agent);
        }
      } else if (normalized == 'gateway') {
        if (!parsed.contains(AssistantExecutionTarget.gateway)) {
          parsed.add(AssistantExecutionTarget.gateway);
        }
      }
    }
    if (parsed.isNotEmpty) {
      return parsed;
    }
    return <AssistantExecutionTarget>[defaultTarget];
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
        },
      );
      var lastSequence = -1;
      try {
        final response = await _requestForResolvedEndpoint(
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
    String authorizationOverride = '',
  }) async {
    await _requestForResolvedEndpoint(
      _GatewayAcpRpcRequest(
        id: _nextRequestId('cancel'),
        method: 'session.cancel',
        params: <String, dynamic>{'sessionId': sessionId, 'threadId': threadId},
      ),
      onNotification: (_) {},
      endpointOverride: endpointOverride,
      authorizationOverride: authorizationOverride,
    );
  }

  Future<void> closeSession({
    required String sessionId,
    required String threadId,
    Uri? endpointOverride,
    String authorizationOverride = '',
  }) async {
    await _requestForResolvedEndpoint(
      _GatewayAcpRpcRequest(
        id: _nextRequestId('close'),
        method: 'session.close',
        params: <String, dynamic>{'sessionId': sessionId, 'threadId': threadId},
      ),
      onNotification: (_) {},
      endpointOverride: endpointOverride,
      authorizationOverride: authorizationOverride,
    );
  }

  Future<Map<String, dynamic>> request({
    required String method,
    required Map<String, dynamic> params,
    void Function(Map<String, dynamic>)? onNotification,
    Uri? endpointOverride,
    String authorizationOverride = '',
  }) async {
    return _requestForResolvedEndpoint(
      _GatewayAcpRpcRequest(
        id: _nextRequestId(method),
        method: method,
        params: params,
      ),
      onNotification: onNotification ?? (_) {},
      endpointOverride: endpointOverride,
      authorizationOverride: authorizationOverride,
    );
  }

  Future<void> dispose() async {}

  Future<Map<String, dynamic>> _requestForResolvedEndpoint(
    _GatewayAcpRpcRequest request, {
    required void Function(Map<String, dynamic>) onNotification,
    Uri? endpointOverride,
    String authorizationOverride = '',
  }) async {
    final resolvedEndpoint = endpointOverride ?? endpointResolver();
    final scheme = resolvedEndpoint?.scheme.trim().toLowerCase() ?? '';

    if (scheme == 'http' || scheme == 'https') {
      return _requestViaHttp(
        request,
        onNotification: onNotification,
        endpointOverride: resolvedEndpoint,
        authorizationOverride: authorizationOverride,
      );
    }

    return _requestViaWebSocket(
      request,
      onNotification: onNotification,
      endpointOverride: resolvedEndpoint,
      authorizationOverride: authorizationOverride,
    );
  }

  Future<Map<String, dynamic>> _requestViaWebSocket(
    _GatewayAcpRpcRequest request, {
    required void Function(Map<String, dynamic>) onNotification,
    Uri? endpointOverride,
    String authorizationOverride = '',
  }) async {
    final endpoint = resolveAcpWebSocketEndpoint(
      endpointOverride ?? endpointResolver(),
    );
    if (endpoint == null) {
      throw const GatewayAcpException(
        'Missing ACP endpoint',
        code: 'ACP_ENDPOINT_MISSING',
      );
    }
    return _requestViaWebSocketEndpoint(
      request,
      endpoint: endpoint,
      onNotification: onNotification,
      authorizationOverride: authorizationOverride,
    );
  }

  Future<Map<String, dynamic>> _requestViaWebSocketEndpoint(
    _GatewayAcpRpcRequest request, {
    required Uri endpoint,
    required void Function(Map<String, dynamic>) onNotification,
    String authorizationOverride = '',
  }) async {
    final authorization = await _resolveAuthorizationHeader(
      endpoint,
      authorizationOverride: authorizationOverride,
    );
    final socket =
        await WebSocket.connect(
          endpoint.toString(),
          headers: authorization.isEmpty
              ? null
              : <String, dynamic>{
                  HttpHeaders.authorizationHeader: authorization,
                },
        ).timeout(
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
      return <String, dynamic>{
        ...response,
        '_xworkmateDiagnostics': <String, dynamic>{
          'transport': 'websocket',
          'requestUrl': endpoint.toString(),
          'statusCode': null,
          'contentType': '',
          'bodyRead': true,
        },
      };
    } finally {
      await subscription.cancel();
      await socket.close();
    }
  }

  Future<Map<String, dynamic>> _requestViaHttp(
    _GatewayAcpRpcRequest request, {
    required void Function(Map<String, dynamic>) onNotification,
    Uri? endpointOverride,
    String authorizationOverride = '',
  }) async {
    final endpoint = _resolveHttpRpcEndpoint(endpointOverride, request.method);
    if (endpoint == null) {
      throw const GatewayAcpException(
        'Missing ACP HTTP endpoint',
        code: 'ACP_HTTP_ENDPOINT_MISSING',
      );
    }

    GatewayAcpException? lastRetryableError;
    for (
      var attempt = 0;
      attempt <= gatewayAcpHttpHandshakeInterruptedRetryCount;
      attempt += 1
    ) {
      try {
        return await _requestViaHttpAttempt(
          request,
          endpoint: endpoint,
          onNotification: onNotification,
          authorizationOverride: authorizationOverride,
          retryAttempt: attempt,
        );
      } on GatewayAcpException catch (error) {
        final retryLimit = _httpRetryCountForError(error);
        if (retryLimit == null || attempt >= retryLimit) {
          rethrow;
        }
        lastRetryableError = error;
        await Future<void>.delayed(_httpRetryDelayFor(error, attempt));
      }
    }
    throw lastRetryableError ??
        const GatewayAcpException(
          'ACP HTTP handshake was interrupted before the response started',
          code: gatewayAcpHttpHandshakeInterruptedCode,
        );
  }

  int? _httpRetryCountForError(GatewayAcpException error) {
    return switch (error.code) {
      gatewayAcpHttpHandshakeInterruptedCode =>
        gatewayAcpHttpHandshakeInterruptedRetryCount,
      gatewayAcpHttpConnectTimeoutCode ||
      gatewayAcpHttpConnectFailedCode => gatewayAcpHttpConnectFailureRetryCount,
      _ => null,
    };
  }

  Duration _httpRetryDelayFor(GatewayAcpException error, int attempt) {
    if (error.code == gatewayAcpHttpConnectTimeoutCode ||
        error.code == gatewayAcpHttpConnectFailedCode) {
      return Duration(milliseconds: 200 * (1 << attempt));
    }
    return Duration(milliseconds: 50 * (attempt + 1));
  }

  Future<Map<String, dynamic>> _requestViaHttpAttempt(
    _GatewayAcpRpcRequest request, {
    required Uri endpoint,
    required void Function(Map<String, dynamic>) onNotification,
    required String authorizationOverride,
    required int retryAttempt,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = gatewayAcpHttpConnectTimeout;
    var statusCode = 0;
    var contentType = '';
    var bodyRead = false;
    var phase = _GatewayAcpHttpRequestPhase.connect;
    try {
      final authorization = await _resolveAuthorizationHeader(
        endpoint,
        authorizationOverride: authorizationOverride,
      );
      phase = _GatewayAcpHttpRequestPhase.connect;
      final httpRequest = await client
          .postUrl(endpoint)
          .timeout(gatewayAcpHttpConnectTimeout);
      phase = _GatewayAcpHttpRequestPhase.write;
      httpRequest.headers.set(
        HttpHeaders.contentTypeHeader,
        'application/json; charset=utf-8',
      );
      httpRequest.headers.set(
        HttpHeaders.acceptHeader,
        'text/event-stream, application/json',
      );
      if (authorization.isNotEmpty) {
        httpRequest.headers.set(HttpHeaders.authorizationHeader, authorization);
      }
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
      phase = _GatewayAcpHttpRequestPhase.waitingForResponse;
      final response = await httpRequest.close().timeout(
        gatewayAcpHttpResponseTimeoutFor(
          endpoint,
          request.method,
          request.params,
        ),
      );
      statusCode = response.statusCode;
      contentType =
          response.headers.contentType?.mimeType.toLowerCase() ??
          response.headers
              .value(HttpHeaders.contentTypeHeader)
              ?.toLowerCase() ??
          '';
      phase = _GatewayAcpHttpRequestPhase.bodyRead;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body = await response.transform(utf8.decoder).join();
        bodyRead = body.isNotEmpty;
        throw GatewayAcpException(
          _describeHttpError(
            statusCode: response.statusCode,
            contentType: contentType,
            body: body,
          ),
          code: 'ACP_HTTP_${response.statusCode}',
          details: <String, dynamic>{
            'requestUrl': endpoint.toString(),
            'statusCode': response.statusCode,
            'contentType': contentType,
            'bodyRead': bodyRead,
          },
        );
      }
      if (contentType.contains('text/event-stream')) {
        final decoded = await _consumeSseRpcResponse(
          response: response,
          requestId: request.id,
          onNotification: onNotification,
        );
        return <String, dynamic>{
          ...decoded.response,
          '_xworkmateDiagnostics': <String, dynamic>{
            'transport': 'http-sse',
            'requestUrl': endpoint.toString(),
            'statusCode': response.statusCode,
            'contentType': contentType,
            'bodyRead': true,
            'sseKeepaliveReceived': decoded.keepaliveReceived,
            'sseLastEventAtMs': decoded.lastEventAtMs,
            'sseEventCount': decoded.eventCount,
          },
        };
      }
      final body = await response.transform(utf8.decoder).join();
      bodyRead = body.isNotEmpty;
      final decoded = _decodeMap(body);
      _throwIfJsonRpcError(decoded);
      return <String, dynamic>{
        ...decoded,
        '_xworkmateDiagnostics': <String, dynamic>{
          'transport': 'http',
          'requestUrl': endpoint.toString(),
          'statusCode': response.statusCode,
          'contentType': contentType,
          'bodyRead': bodyRead,
        },
      };
    } on GatewayAcpException {
      rethrow;
    } on TimeoutException catch (error) {
      if (phase == _GatewayAcpHttpRequestPhase.connect) {
        throw _connectException(
          endpoint: endpoint,
          statusCode: statusCode,
          contentType: contentType,
          bodyRead: bodyRead,
          retryAttempt: retryAttempt,
          phase: phase,
          originalError: error,
          timeout: true,
        );
      }
      rethrow;
    } on HandshakeException catch (error) {
      throw _handshakeInterruptedException(
        endpoint: endpoint,
        statusCode: statusCode,
        contentType: contentType,
        bodyRead: bodyRead,
        retryAttempt: retryAttempt,
        originalError: error,
      );
    } on SocketException catch (error) {
      if (_looksLikeHandshakeInterruptedSocketError(
        error.toString(),
        endpoint: endpoint,
        statusCode: statusCode,
        bodyRead: bodyRead,
      )) {
        throw _handshakeInterruptedException(
          endpoint: endpoint,
          statusCode: statusCode,
          contentType: contentType,
          bodyRead: bodyRead,
          retryAttempt: retryAttempt,
          originalError: error,
        );
      }
      if (phase == _GatewayAcpHttpRequestPhase.connect &&
          statusCode == 0 &&
          !bodyRead) {
        throw _connectException(
          endpoint: endpoint,
          statusCode: statusCode,
          contentType: contentType,
          bodyRead: bodyRead,
          retryAttempt: retryAttempt,
          phase: phase,
          originalError: error,
          timeout: _looksLikeConnectTimeout(error.toString()),
        );
      }
      rethrow;
    } on HttpException catch (error) {
      if (_looksLikeConnectionClosedBeforeResponse(error.toString())) {
        throw GatewayAcpException(
          'ACP HTTP connection closed before the response finished arriving',
          code: 'ACP_HTTP_CONNECTION_CLOSED',
          details: <String, dynamic>{
            'requestUrl': endpoint.toString(),
            'statusCode': statusCode,
            'contentType': contentType,
            'bodyRead': bodyRead,
            'originalError': error.toString(),
          },
        );
      }
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  GatewayAcpException _connectException({
    required Uri endpoint,
    required int statusCode,
    required String contentType,
    required bool bodyRead,
    required int retryAttempt,
    required _GatewayAcpHttpRequestPhase phase,
    required Object originalError,
    required bool timeout,
  }) {
    final code = timeout
        ? gatewayAcpHttpConnectTimeoutCode
        : gatewayAcpHttpConnectFailedCode;
    final message = timeout
        ? 'ACP HTTP connection timed out before the request was confirmed'
        : 'ACP HTTP connection failed before the request was confirmed';
    return GatewayAcpException(
      message,
      code: code,
      details: <String, dynamic>{
        'requestUrl': endpoint.toString(),
        'statusCode': statusCode,
        'contentType': contentType,
        'bodyRead': bodyRead,
        'phase': phase.name,
        'retryAttempt': retryAttempt,
        'maxRetryAttempts': gatewayAcpHttpConnectFailureRetryCount,
        'originalError': originalError.toString(),
      },
    );
  }

  GatewayAcpException _handshakeInterruptedException({
    required Uri endpoint,
    required int statusCode,
    required String contentType,
    required bool bodyRead,
    required int retryAttempt,
    required Object originalError,
  }) {
    return GatewayAcpException(
      'ACP HTTP handshake was interrupted before the response started',
      code: gatewayAcpHttpHandshakeInterruptedCode,
      details: <String, dynamic>{
        'requestUrl': endpoint.toString(),
        'statusCode': statusCode,
        'contentType': contentType,
        'bodyRead': bodyRead,
        'retryAttempt': retryAttempt,
        'maxRetryAttempts': gatewayAcpHttpHandshakeInterruptedRetryCount,
        'originalError': originalError.toString(),
      },
    );
  }

  bool _looksLikeHandshakeInterruptedSocketError(
    String raw, {
    required Uri endpoint,
    required int statusCode,
    required bool bodyRead,
  }) {
    if (endpoint.scheme != 'https' || statusCode != 0 || bodyRead) {
      return false;
    }
    final lowered = raw.toLowerCase();
    return lowered.contains('connection reset') ||
        lowered.contains('read failed') ||
        lowered.contains('connection terminated during handshake');
  }

  bool _looksLikeConnectionClosedBeforeResponse(String raw) {
    final lowered = raw.toLowerCase();
    return lowered.contains('connection closed before full header') ||
        lowered.contains('connection closed while receiving data') ||
        lowered.contains('connection terminated during body read') ||
        lowered.contains('stream closed');
  }

  bool _looksLikeConnectTimeout(String raw) {
    final lowered = raw.toLowerCase();
    return lowered.contains('connection timed out') ||
        lowered.contains('timed out') ||
        lowered.contains('timeout');
  }

  String _describeHttpError({
    required int statusCode,
    required String contentType,
    required String body,
  }) {
    final base = 'ACP HTTP request failed ($statusCode)';
    final normalizedType = contentType.trim();
    final detail = _extractErrorDetail(body);
    if (normalizedType.isNotEmpty &&
        !_contentTypeLooksJsonOrSse(normalizedType)) {
      if (detail.isNotEmpty) {
        return '$base · $detail · unexpected content type: $normalizedType';
      }
      return '$base · unexpected content type: $normalizedType';
    }

    if (detail.isNotEmpty) {
      return '$base · $detail';
    }
    return base;
  }

  bool _contentTypeLooksJsonOrSse(String contentType) {
    return contentType.contains('application/json') ||
        contentType.contains('application/problem+json') ||
        contentType.contains('text/json') ||
        contentType.contains('text/event-stream');
  }

  String _extractErrorDetail(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    try {
      final decoded = _decodeMap(trimmed);
      final detail = _extractStructuredErrorDetail(decoded);
      if (detail.isNotEmpty) {
        return detail;
      }
    } on FormatException {
      // Fall through to textual snippet extraction below.
    }

    final singleLine = trimmed.replaceAll(RegExp(r'\s+'), ' ');
    if (singleLine.isEmpty) {
      return '';
    }
    return singleLine.length <= 160
        ? singleLine
        : '${singleLine.substring(0, 157)}...';
  }

  String _extractStructuredErrorDetail(Map<String, dynamic> decoded) {
    final candidates = <String>[];
    void addCandidate(Object? value) {
      final text = _extractStructuredErrorText(value).trim();
      if (text.isNotEmpty && !candidates.contains(text)) {
        candidates.add(text);
      }
    }

    final error = decoded['error'];
    addCandidate(error);
    if (error is Map) {
      final errorMap = error.cast<String, dynamic>();
      addCandidate(errorMap['data']);
      addCandidate(errorMap['details']);
    }
    for (final key in const <String>[
      'message',
      'detail',
      'errorMessage',
      'unavailableMessage',
      'reason',
      'description',
      'body',
    ]) {
      addCandidate(decoded[key]);
    }
    final code = stringValue(decoded['code']) ?? '';
    if (candidates.isEmpty && code.isNotEmpty) {
      candidates.add(code);
    }
    return candidates.join(' · ');
  }

  String _extractStructuredErrorText(Object? value, [Set<Object>? visited]) {
    if (value == null) {
      return '';
    }
    if (value is String) {
      return value.trim();
    }
    if (value is num || value is bool) {
      return value.toString();
    }
    final seen = visited ?? <Object>{};
    if (!seen.add(value)) {
      return '';
    }
    if (value is Map) {
      final map = value.cast<String, dynamic>();
      final parts = <String>[];
      for (final key in const <String>[
        'message',
        'detail',
        'error',
        'errorMessage',
        'unavailableMessage',
        'upstreamError',
        'reason',
        'description',
      ]) {
        final text = _extractStructuredErrorText(map[key], seen);
        if (text.isNotEmpty && !parts.contains(text)) {
          parts.add(text);
        }
      }
      final code =
          stringValue(map['code']) ?? stringValue(map['unavailableCode']) ?? '';
      final upstream =
          stringValue(map['upstreamMethod']) ??
          stringValue(map['upstream']) ??
          '';
      if (code.isNotEmpty && parts.every((part) => !part.contains(code))) {
        parts.add('code: $code');
      }
      if (upstream.isNotEmpty) {
        parts.add('upstream: $upstream');
      }
      if (parts.length <= 1) {
        return parts.join();
      }
      return '${parts.first} (${parts.skip(1).join(', ')})';
    }
    if (value is Iterable) {
      return value
          .map((item) => _extractStructuredErrorText(item, seen))
          .where((item) => item.isNotEmpty)
          .join(' · ');
    }
    return value.toString().trim();
  }

  Future<String> _resolveAuthorizationHeader(
    Uri endpoint, {
    String authorizationOverride = '',
  }) async {
    final override = _normalizeAuthorizationHeader(authorizationOverride);
    if (override.isNotEmpty) {
      return override;
    }
    return _normalizeAuthorizationHeader(
      (await authorizationResolver?.call(endpoint))?.trim() ?? '',
    );
  }

  String _normalizeAuthorizationHeader(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    if (_looksLikeAuthorizationHeader(trimmed)) {
      return trimmed;
    }
    return 'Bearer $trimmed';
  }

  bool _looksLikeAuthorizationHeader(String raw) {
    final separatorIndex = raw.indexOf(RegExp(r'\s'));
    if (separatorIndex <= 0 || separatorIndex >= raw.length - 1) {
      return false;
    }
    final scheme = raw.substring(0, separatorIndex);
    return RegExp(r"^[A-Za-z][A-Za-z0-9!#$%&'*+.^_`|~-]*$").hasMatch(scheme);
  }

  Future<_GatewayAcpSseRpcResponse> _consumeSseRpcResponse({
    required HttpClientResponse response,
    required String requestId,
    required void Function(Map<String, dynamic>) onNotification,
  }) async {
    Map<String, dynamic>? resolvedResponse;
    final eventLines = <String>[];
    var eventCount = 0;
    var keepaliveReceived = false;
    var lastEventAtMs = 0;

    void consumeEventPayload(String payload) {
      final trimmed = payload.trim();
      if (trimmed.isEmpty || trimmed == '[DONE]') {
        return;
      }
      eventCount += 1;
      lastEventAtMs = DateTime.now().millisecondsSinceEpoch;
      final json = _decodeMap(trimmed);
      if (stringValue(json['id']) == requestId &&
          (json.containsKey('result') || json.containsKey('error'))) {
        resolvedResponse ??= json;
        return;
      }
      final method = stringValue(json['method']) ?? '';
      if (method == 'xworkmate.bridge.keepalive') {
        keepaliveReceived = true;
      }
      if (method.isNotEmpty) {
        onNotification(json);
      }
    }

    try {
      await for (final line
          in response.transform(utf8.decoder).transform(const LineSplitter())) {
        if (line.isEmpty) {
          if (eventLines.isNotEmpty) {
            consumeEventPayload(eventLines.join('\n'));
            eventLines.clear();
            if (resolvedResponse != null) {
              break;
            }
          }
          continue;
        }
        if (line.startsWith('data:')) {
          eventLines.add(line.substring(5).trimLeft());
        }
      }
    } on HttpException catch (error, stackTrace) {
      if (resolvedResponse == null && eventLines.isNotEmpty) {
        try {
          consumeEventPayload(eventLines.join('\n'));
          eventLines.clear();
        } on FormatException {
          Error.throwWithStackTrace(error, stackTrace);
        }
      }
      if (resolvedResponse == null) {
        rethrow;
      }
    }

    if (eventLines.isNotEmpty && resolvedResponse == null) {
      consumeEventPayload(eventLines.join('\n'));
    }
    final resolved = resolvedResponse;
    if (resolved == null) {
      throw GatewayAcpException(
        'ACP SSE ended without JSON-RPC response for request $requestId',
        code: 'ACP_SSE_NO_RESULT',
      );
    }
    _throwIfJsonRpcError(resolved);
    return _GatewayAcpSseRpcResponse(
      response: resolved,
      keepaliveReceived: keepaliveReceived,
      lastEventAtMs: lastEventAtMs,
      eventCount: eventCount,
    );
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
    final details = error['data'] ?? error['details'];
    throw GatewayAcpException(
      stringValue(error['message']) ?? 'ACP JSON-RPC request failed',
      code: stringValue(error['code']),
      detailCode: _jsonRpcErrorDetailCode(details),
      details: details,
    );
  }

  String? _jsonRpcErrorDetailCode(Object? details) {
    final data = asMap(details);
    return stringValue(data['code']) ??
        stringValue(data['detailCode']) ??
        stringValue(data['errorCode']);
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

  Uri? _resolveHttpRpcEndpoint([Uri? endpointOverride, String method = '']) {
    final endpoint = endpointOverride ?? endpointResolver();
    if (_isOpenClawTaskSubmitEndpoint(endpoint) &&
        _isOpenClawTaskSubmitMethod(method)) {
      return endpoint?.replace(
        path: '/gateway/openclaw',
        query: null,
        fragment: null,
      );
    }
    return resolveAcpHttpRpcEndpoint(endpoint);
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

bool _isOpenClawTaskSubmitMethod(String method) {
  final normalized = method.trim();
  return normalized == 'session.start' || normalized == 'session.message';
}

bool _isOpenClawTaskSubmitEndpoint(Uri? endpoint) {
  var path = endpoint?.path.trim() ?? '';
  if (!path.startsWith('/')) {
    path = '/$path';
  }
  path = path.replaceFirst(RegExp(r'/+$'), '');
  return path == '/gateway/openclaw';
}

Duration gatewayAcpHttpResponseTimeoutFor(
  Uri endpoint,
  String method, [
  Map<String, dynamic> params = const <String, dynamic>{},
]) {
  if (!_isOpenClawTaskSubmitMethod(method)) {
    return const Duration(seconds: 120);
  }
  if (_isOpenClawTaskSubmitEndpoint(endpoint)) {
    return Duration(
      minutes: gatewayAcpTaskRuntimeBudgetMinutesForParams({
        'requestedExecutionTarget':
            AssistantExecutionTarget.gateway.promptValue,
        ...params,
      }),
    );
  }
  return Duration(minutes: gatewayAcpTaskRuntimeBudgetMinutesForParams(params));
}

int gatewayAcpTaskRuntimeBudgetMinutesForParams(Map<String, dynamic> params) {
  if (_looksLikeLongArtifactTask(params)) {
    return 30;
  }
  if (_looksLikeGatewayTask(params)) {
    return 10;
  }
  return 2;
}

bool _looksLikeGatewayTask(Map<String, dynamic> params) {
  final target = _paramText(params, const <String>[
    'requestedExecutionTarget',
    'executionTarget',
  ]).toLowerCase();
  if (target == AssistantExecutionTarget.gateway.promptValue) {
    return true;
  }
  final providerText = _paramText(params, const <String>[
    'provider',
    'gatewayProvider',
    'preferredGatewayProviderId',
  ]).toLowerCase();
  if (providerText.contains('openclaw')) {
    return true;
  }
  final routing = params['routing'];
  if (routing is Map) {
    final preferred = routing['preferredGatewayProviderId']
        ?.toString()
        .trim()
        .toLowerCase();
    return preferred == kCanonicalGatewayProviderId ||
        preferred?.contains('openclaw') == true;
  }
  return false;
}

bool _looksLikeLongArtifactTask(Map<String, dynamic> params) {
  final prompt = _paramText(params, const <String>[
    'taskPrompt',
    'prompt',
    'message',
  ]);
  final lower = prompt.toLowerCase();
  final attachments =
      _paramListLength(params['attachments']) +
      _paramListLength(params['inlineAttachments']);
  if (attachments >= 2 || prompt.length >= 1200) {
    return true;
  }
  const markers = <String>[
    '生成文件',
    '同步生成文件',
    '产物',
    '附件',
    '图片提示词',
    '完整调研ppt',
    'markdown格式',
    '输出markdown',
    '输出 完整',
    'ppt',
    'pptx',
    'powerpoint',
    'xls',
    '.xls',
    'word格式',
    'word 格式',
    'word',
    'docx',
    '.docx',
    'png',
    '.png',
    'mp4',
    '.mp4',
    'jpg',
    '.jpg',
    'markdown格式',
    'markdown',
    '.md',
    'javascript',
    '.js',
    'image prompt',
    'artifacts',
    'downloadurl',
  ];
  return markers.any(lower.contains);
}

String _paramText(Map<String, dynamic> params, List<String> keys) {
  for (final key in keys) {
    final value = params[key];
    if (value == null) {
      continue;
    }
    final text = value.toString().trim();
    if (text.isNotEmpty) {
      return text;
    }
  }
  return '';
}

int _paramListLength(Object? value) {
  if (value is List) {
    return value.length;
  }
  return 0;
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

class _GatewayAcpSseRpcResponse {
  const _GatewayAcpSseRpcResponse({
    required this.response,
    required this.keepaliveReceived,
    required this.lastEventAtMs,
    required this.eventCount,
  });

  final Map<String, dynamic> response;
  final bool keepaliveReceived;
  final int lastEventAtMs;
  final int eventCount;
}
