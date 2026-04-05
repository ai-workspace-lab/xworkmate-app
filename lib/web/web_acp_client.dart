import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../runtime/acp_endpoint_paths.dart';
import '../runtime/runtime_models.dart';

class WebAcpException implements Exception {
  const WebAcpException(this.message, {this.code, this.details});

  final String message;
  final String? code;
  final Object? details;

  @override
  String toString() => code == null ? message : '$code: $message';
}

class WebAcpCapabilities {
  const WebAcpCapabilities({
    required this.singleAgent,
    required this.multiAgent,
    required this.providers,
    required this.raw,
  });

  const WebAcpCapabilities.empty()
    : singleAgent = false,
      multiAgent = false,
      providers = const <SingleAgentProvider>{},
      raw = const <String, dynamic>{};

  final bool singleAgent;
  final bool multiAgent;
  final Set<SingleAgentProvider> providers;
  final Map<String, dynamic> raw;
}

class WebAcpClient {
  const WebAcpClient();

  static const Duration defaultTimeoutInternal = Duration(seconds: 120);

  Future<WebAcpCapabilities> loadCapabilities({required Uri endpoint}) async {
    final response = await request(
      endpoint: endpoint,
      method: 'acp.capabilities',
      params: const <String, dynamic>{},
    );
    final result = asMapInternal(response['result']);
    final caps = asMapInternal(result['capabilities']);
    final providers = <SingleAgentProvider>{};
    for (final raw in <Object?>[
      ...asListInternal(result['providers']),
      ...asListInternal(caps['providers']),
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
        boolValueInternal(result['singleAgent']) ??
        boolValueInternal(caps['single_agent']) ??
        providers.isNotEmpty;
    final multiAgent =
        boolValueInternal(result['multiAgent']) ??
        boolValueInternal(caps['multi_agent']) ??
        false;
    return WebAcpCapabilities(
      singleAgent: singleAgent,
      multiAgent: multiAgent,
      providers: providers,
      raw: result,
    );
  }

  Future<void> cancelSession({
    required Uri endpoint,
    required String sessionId,
    required String threadId,
  }) async {
    await request(
      endpoint: endpoint,
      method: 'session.cancel',
      params: <String, dynamic>{'sessionId': sessionId, 'threadId': threadId},
    );
  }

  Future<Map<String, dynamic>> request({
    required Uri endpoint,
    required String method,
    required Map<String, dynamic> params,
    void Function(Map<String, dynamic> notification)? onNotification,
    Duration timeout = defaultTimeoutInternal,
  }) async {
    final requestId = '${DateTime.now().microsecondsSinceEpoch}-$method';
    final scheme = endpoint.scheme.trim().toLowerCase();
    final canUseHttp = resolveHttpRpcEndpointInternal(endpoint) != null;
    if (scheme == 'http' || scheme == 'https') {
      try {
        return await _requestViaHttp(
          requestId: requestId,
          endpoint: endpoint,
          method: method,
          params: params,
          onNotification: onNotification,
          timeout: timeout,
        );
      } catch (error) {
        if (error is WebAcpException) {
          rethrow;
        }
        return _requestViaWebSocket(
          requestId: requestId,
          endpoint: endpoint,
          method: method,
          params: params,
          onNotification: onNotification,
          timeout: timeout,
        );
      }
    }

    try {
      return await _requestViaWebSocket(
        requestId: requestId,
        endpoint: endpoint,
        method: method,
        params: params,
        onNotification: onNotification,
        timeout: timeout,
      );
    } catch (_) {
      if (!canUseHttp) {
        rethrow;
      }
      return _requestViaHttp(
        requestId: requestId,
        endpoint: endpoint,
        method: method,
        params: params,
        onNotification: onNotification,
        timeout: timeout,
      );
    }
  }

  Future<Map<String, dynamic>> _requestViaWebSocket({
    required String requestId,
    required Uri endpoint,
    required String method,
    required Map<String, dynamic> params,
    void Function(Map<String, dynamic> notification)? onNotification,
    required Duration timeout,
  }) async {
    final wsEndpoint = resolveWebSocketEndpointInternal(endpoint);
    if (wsEndpoint == null) {
      throw const WebAcpException(
        'Missing ACP endpoint',
        code: 'ACP_ENDPOINT_MISSING',
      );
    }
    final socket = WebSocketChannel.connect(wsEndpoint);
    final completer = Completer<Map<String, dynamic>>();
    late final StreamSubscription<dynamic> subscription;
    subscription = socket.stream.listen(
      (raw) {
        final json = decodeMapInternal(raw);
        final id = stringValueInternal(json['id']);
        final methodName = stringValueInternal(json['method']) ?? '';
        if (id == requestId &&
            (json.containsKey('result') || json.containsKey('error'))) {
          if (!completer.isCompleted) {
            completer.complete(json);
          }
          return;
        }
        if (methodName.isNotEmpty && onNotification != null) {
          onNotification(json);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(
            WebAcpException(error.toString(), code: 'ACP_WS_RUNTIME_ERROR'),
          );
        }
      },
      onDone: () {
        if (!completer.isCompleted) {
          completer.completeError(
            const WebAcpException(
              'ACP websocket closed before response',
              code: 'ACP_WS_EARLY_CLOSE',
            ),
          );
        }
      },
      cancelOnError: true,
    );

    try {
      await socket.ready;
      socket.sink.add(
        jsonEncode(<String, dynamic>{
          'jsonrpc': '2.0',
          'id': requestId,
          'method': method,
          'params': params,
        }),
      );
      final response = await completer.future.timeout(timeout);
      throwIfJsonRpcErrorInternal(response);
      return response;
    } finally {
      await subscription.cancel();
      await socket.sink.close();
    }
  }

  Future<Map<String, dynamic>> _requestViaHttp({
    required String requestId,
    required Uri endpoint,
    required String method,
    required Map<String, dynamic> params,
    void Function(Map<String, dynamic> notification)? onNotification,
    required Duration timeout,
  }) async {
    final httpEndpoint = resolveHttpRpcEndpointInternal(endpoint);
    if (httpEndpoint == null) {
      throw const WebAcpException(
        'Missing ACP HTTP endpoint',
        code: 'ACP_HTTP_ENDPOINT_MISSING',
      );
    }

    final response = await http
        .post(
          httpEndpoint,
          headers: const <String, String>{
            'content-type': 'application/json; charset=utf-8',
            'accept': 'text/event-stream, application/json',
          },
          body: jsonEncode(<String, dynamic>{
            'jsonrpc': '2.0',
            'id': requestId,
            'method': method,
            'params': params,
          }),
        )
        .timeout(timeout);
    final contentType =
        response.headers['content-type']?.toLowerCase().trim() ?? '';
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw WebAcpException(
        _describeHttpError(
          statusCode: response.statusCode,
          contentType: contentType,
          body: response.body,
        ),
        code: 'ACP_HTTP_${response.statusCode}',
        details: <String, dynamic>{
          'statusCode': response.statusCode,
          'contentType': contentType,
        },
      );
    }
    if (contentType.contains('text/event-stream')) {
      return _consumeSseRpcResponse(
        body: response.body,
        requestId: requestId,
        onNotification: onNotification,
      );
    }
    final decoded = decodeMapInternal(response.body);
    throwIfJsonRpcErrorInternal(decoded);
    return decoded;
  }

  static Uri? resolveWebSocketEndpointInternal(Uri? endpoint) {
    return resolveAcpWebSocketEndpoint(endpoint);
  }

  static Uri? resolveHttpRpcEndpointInternal(Uri? endpoint) {
    return resolveAcpHttpRpcEndpoint(endpoint);
  }

  String _describeHttpError({
    required int statusCode,
    required String contentType,
    required String body,
  }) {
    final base = 'ACP HTTP request failed ($statusCode)';
    final normalizedType = contentType.trim();
    if (normalizedType.isNotEmpty &&
        !_contentTypeLooksJsonOrSse(normalizedType)) {
      return '$base · unexpected content type: $normalizedType';
    }

    final detail = _extractErrorDetail(body);
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
      final decoded = decodeMapInternal(trimmed);
      final error = asMapInternal(decoded['error']);
      return (stringValueInternal(error['message']) ??
              stringValueInternal(decoded['message']) ??
              stringValueInternal(decoded['detail']) ??
              '')
          .trim();
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

  Future<Map<String, dynamic>> _consumeSseRpcResponse({
    required String body,
    required String requestId,
    void Function(Map<String, dynamic> notification)? onNotification,
  }) async {
    final eventLines = <String>[];
    Map<String, dynamic>? responseEnvelope;

    void consumeEventPayload(String payload) {
      final trimmed = payload.trim();
      if (trimmed.isEmpty || trimmed == '[DONE]') {
        return;
      }
      final json = decodeMapInternal(trimmed);
      if (stringValueInternal(json['id']) == requestId &&
          (json.containsKey('result') || json.containsKey('error'))) {
        responseEnvelope = json;
        return;
      }
      if ((stringValueInternal(json['method']) ?? '').isNotEmpty &&
          onNotification != null) {
        onNotification(json);
      }
    }

    for (final line in const LineSplitter().convert(body)) {
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
    if (responseEnvelope == null) {
      throw const WebAcpException(
        'ACP SSE ended without JSON-RPC response',
        code: 'ACP_SSE_NO_RESULT',
      );
    }
    throwIfJsonRpcErrorInternal(responseEnvelope!);
    return responseEnvelope!;
  }

  void throwIfJsonRpcErrorInternal(Map<String, dynamic> response) {
    final error = asMapInternal(response['error']);
    if (error.isEmpty) {
      return;
    }
    throw WebAcpException(
      stringValueInternal(error['message']) ?? 'ACP request failed',
      code: stringValueInternal(error['code']),
      details: error['data'],
    );
  }

  static Map<String, dynamic> decodeMapInternal(Object? raw) {
    if (raw is Map<String, dynamic>) {
      return raw;
    }
    if (raw is Map) {
      return raw.cast<String, dynamic>();
    }
    if (raw is String) {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.cast<String, dynamic>();
      }
    }
    return const <String, dynamic>{};
  }

  static Map<String, dynamic> asMapInternal(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.cast<String, dynamic>();
    }
    return const <String, dynamic>{};
  }

  static List<dynamic> asListInternal(Object? value) {
    if (value is List<dynamic>) {
      return value;
    }
    if (value is List) {
      return value.cast<dynamic>();
    }
    return const <dynamic>[];
  }

  static String? stringValueInternal(Object? value) {
    final text = value?.toString().trim();
    return (text == null || text.isEmpty) ? null : text;
  }

  static bool? boolValueInternal(Object? value) {
    if (value is bool) {
      return value;
    }
    final text = value?.toString().trim().toLowerCase();
    if (text == 'true') {
      return true;
    }
    if (text == 'false') {
      return false;
    }
    return null;
  }
}
