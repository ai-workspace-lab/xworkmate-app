import 'dart:async';
import 'dart:convert';

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

  static Uri? resolveWebSocketEndpointInternal(Uri? endpoint) {
    return resolveAcpWebSocketEndpoint(endpoint);
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
