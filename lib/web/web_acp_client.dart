import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

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

  static const Duration _defaultTimeout = Duration(seconds: 120);

  Future<WebAcpCapabilities> loadCapabilities({
    required Uri endpoint,
  }) async {
    final response = await request(
      endpoint: endpoint,
      method: 'acp.capabilities',
      params: const <String, dynamic>{},
    );
    final result = _asMap(response['result']);
    final caps = _asMap(result['capabilities']);
    final providers = <SingleAgentProvider>{};
    for (final raw in <Object?>[
      ..._asList(result['providers']),
      ..._asList(caps['providers']),
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
        _boolValue(result['singleAgent']) ??
        _boolValue(caps['single_agent']) ??
        providers.isNotEmpty;
    final multiAgent =
        _boolValue(result['multiAgent']) ??
        _boolValue(caps['multi_agent']) ??
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
    Duration timeout = _defaultTimeout,
  }) async {
    final requestId = '${DateTime.now().microsecondsSinceEpoch}-$method';
    final wsEndpoint = _resolveWebSocketEndpoint(endpoint);
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
        final json = _decodeMap(raw);
        final id = _stringValue(json['id']);
        final methodName = _stringValue(json['method']) ?? '';
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
      _throwIfJsonRpcError(response);
      return response;
    } finally {
      await subscription.cancel();
      await socket.sink.close();
    }
  }

  static Uri? _resolveWebSocketEndpoint(Uri? endpoint) {
    if (endpoint == null || endpoint.host.trim().isEmpty) {
      return null;
    }
    final scheme = endpoint.scheme.trim().toLowerCase();
    final wsScheme = switch (scheme) {
      'https' || 'wss' => 'wss',
      _ => 'ws',
    };
    return endpoint.replace(path: '/acp', query: null, fragment: null, scheme: wsScheme);
  }

  void _throwIfJsonRpcError(Map<String, dynamic> response) {
    final error = _asMap(response['error']);
    if (error.isEmpty) {
      return;
    }
    throw WebAcpException(
      _stringValue(error['message']) ?? 'ACP request failed',
      code: _stringValue(error['code']),
      details: error['data'],
    );
  }

  static Map<String, dynamic> _decodeMap(Object? raw) {
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

  static Map<String, dynamic> _asMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.cast<String, dynamic>();
    }
    return const <String, dynamic>{};
  }

  static List<dynamic> _asList(Object? value) {
    if (value is List<dynamic>) {
      return value;
    }
    if (value is List) {
      return value.cast<dynamic>();
    }
    return const <dynamic>[];
  }

  static String? _stringValue(Object? value) {
    final text = value?.toString().trim();
    return (text == null || text.isEmpty) ? null : text;
  }

  static bool? _boolValue(Object? value) {
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
