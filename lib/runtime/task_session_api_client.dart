import 'dart:convert';

import 'session_sync_contract.dart';

enum TaskSessionHttpMethod { get, post }

class TaskSessionHttpRequest {
  const TaskSessionHttpRequest({
    required this.method,
    required this.uri,
    required this.headers,
    this.body,
  });

  final TaskSessionHttpMethod method;
  final Uri uri;
  final Map<String, String> headers;
  final String? body;
}

class TaskSessionHttpResponse {
  const TaskSessionHttpResponse({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
}

/// HTTP and authorization boundary for the shared-session client.
///
/// The transport owns authorization injection. The client never accepts,
/// stores, or logs a token, which keeps session identity metadata separate
/// from credentials and lets the existing managed-Bridge auth resolver be
/// wired in later without changing this contract.
abstract interface class TaskSessionHttpTransport {
  Future<TaskSessionHttpResponse> send(TaskSessionHttpRequest request);
}

abstract interface class TaskSessionGateway {
  Future<CloudSessionSnapshot> createSession({
    required String namespaceId,
    required String title,
  });

  Future<CloudSessionSnapshot> loadSnapshot(String sessionId);

  Future<List<SessionEvent>> loadEvents(
    String sessionId, {
    required int afterSeq,
    required int limit,
  });

  Future<TaskSessionMessageReceipt> sendMessage({
    required String sessionId,
    required String clientRequestId,
    required String text,
    TaskSessionRunRequest? run,
  });
}

class TaskSessionRunRequest {
  TaskSessionRunRequest({required this.priority, this.notBefore}) {
    if (priority < 0) {
      throw ArgumentError.value(priority, 'priority', 'must be non-negative');
    }
  }

  final int priority;
  final DateTime? notBefore;

  Map<String, Object?> toJson() => <String, Object?>{
    'priority': priority,
    if (notBefore != null) 'notBefore': notBefore!.toUtc().toIso8601String(),
  };
}

class TaskSessionMessageReceipt {
  const TaskSessionMessageReceipt({
    required this.sessionId,
    required this.namespaceId,
    required this.snapshotVersion,
    required this.event,
    required this.taskRun,
  });

  final String sessionId;
  final String namespaceId;
  final int snapshotVersion;
  final SessionEvent event;
  final CloudTaskRun taskRun;
}

class TaskSessionApiException implements Exception {
  const TaskSessionApiException({
    required this.statusCode,
    required this.code,
    required this.message,
  });

  final int statusCode;
  final String code;
  final String message;

  @override
  String toString() => 'TaskSessionApiException($statusCode, $code)';
}

class TaskSessionApiClient implements TaskSessionGateway {
  TaskSessionApiClient({
    required Uri baseUri,
    required TaskSessionHttpTransport transport,
  }) : _baseUri = _originUri(baseUri),
       _transport = transport;

  final Uri _baseUri;
  final TaskSessionHttpTransport _transport;

  @override
  Future<CloudSessionSnapshot> createSession({
    required String namespaceId,
    required String title,
  }) async {
    final normalizedNamespaceId = _requiredArgument(namespaceId, 'namespaceId');
    final payload = await _sendJson(
      TaskSessionHttpMethod.post,
      <String>['api', 'v1', 'namespaces', normalizedNamespaceId, 'sessions'],
      body: <String, Object?>{'title': title.trim()},
    );
    return _snapshot(payload);
  }

  @override
  Future<CloudSessionSnapshot> loadSnapshot(String sessionId) async {
    final payload = await _sendJson(TaskSessionHttpMethod.get, <String>[
      'api',
      'v1',
      'sessions',
      _requiredArgument(sessionId, 'sessionId'),
    ]);
    return _snapshot(payload);
  }

  @override
  Future<List<SessionEvent>> loadEvents(
    String sessionId, {
    required int afterSeq,
    required int limit,
  }) async {
    if (afterSeq < 0) {
      throw ArgumentError.value(afterSeq, 'afterSeq', 'must be non-negative');
    }
    if (limit <= 0 || limit > 500) {
      throw ArgumentError.value(limit, 'limit', 'must be between 1 and 500');
    }
    final payload = await _sendJson(
      TaskSessionHttpMethod.get,
      <String>[
        'api',
        'v1',
        'sessions',
        _requiredArgument(sessionId, 'sessionId'),
        'events',
      ],
      queryParameters: <String, String>{
        'after_seq': afterSeq.toString(),
        'limit': limit.toString(),
      },
    );
    final rawEvents = payload['events'];
    if (rawEvents is! List) {
      throw const FormatException('events must be a JSON array.');
    }
    return rawEvents
        .map((item) => SessionEvent.fromJson(_map(item, 'event')))
        .toList(growable: false);
  }

  @override
  Future<TaskSessionMessageReceipt> sendMessage({
    required String sessionId,
    required String clientRequestId,
    required String text,
    TaskSessionRunRequest? run,
  }) async {
    final normalizedSessionId = _requiredArgument(sessionId, 'sessionId');
    final payload = await _sendJson(
      TaskSessionHttpMethod.post,
      <String>['api', 'v1', 'sessions', normalizedSessionId, 'messages'],
      body: <String, Object?>{
        'clientRequestId': _requiredArgument(
          clientRequestId,
          'clientRequestId',
        ),
        'text': _requiredArgument(text, 'text'),
        if (run != null) 'run': run.toJson(),
      },
    );
    final taskRun = _map(payload['taskRun'], 'taskRun');
    return TaskSessionMessageReceipt(
      sessionId: _requiredString(payload, 'sessionId'),
      namespaceId: _requiredString(payload, 'namespaceId'),
      snapshotVersion: _requiredNonNegativeInt(payload, 'snapshotVersion'),
      event: SessionEvent.fromJson(_map(payload['event'], 'event')),
      taskRun: CloudTaskRun(
        id: _requiredString(taskRun, 'id'),
        state: _requiredString(taskRun, 'state'),
        bridgeTaskRef: '',
      ),
    );
  }

  Future<Map<String, dynamic>> _sendJson(
    TaskSessionHttpMethod method,
    List<String> pathSegments, {
    Map<String, String>? queryParameters,
    Map<String, Object?>? body,
  }) async {
    final response = await _transport.send(
      TaskSessionHttpRequest(
        method: method,
        uri: _baseUri.replace(
          pathSegments: pathSegments,
          queryParameters: queryParameters,
        ),
        headers: <String, String>{
          'Accept': 'application/json',
          if (body != null) 'Content-Type': 'application/json',
        },
        body: body == null ? null : jsonEncode(body),
      ),
    );
    final isSuccess = response.statusCode >= 200 && response.statusCode < 300;
    late final Map<String, dynamic> decoded;
    try {
      decoded = _decodeMap(response.body);
    } on FormatException {
      if (isSuccess) {
        rethrow;
      }
      throw TaskSessionApiException(
        statusCode: response.statusCode,
        code: 'invalid_response',
        message: 'Bridge returned a non-JSON error response.',
      );
    }
    if (!isSuccess) {
      throw TaskSessionApiException(
        statusCode: response.statusCode,
        code: _optionalString(decoded, 'error', fallback: 'request_failed'),
        message: _optionalString(
          decoded,
          'message',
          fallback: 'Task session request failed.',
        ),
      );
    }
    return decoded;
  }

  static CloudSessionSnapshot _snapshot(Map<String, dynamic> payload) {
    return CloudSessionSnapshot.fromJson(payload);
  }
}

Uri _originUri(Uri uri) {
  if (!uri.hasScheme || uri.host.trim().isEmpty) {
    throw ArgumentError.value(uri, 'baseUri', 'must be an absolute URI');
  }
  final isLoopback =
      uri.host == 'localhost' || uri.host == '127.0.0.1' || uri.host == '::1';
  if (uri.scheme != 'https' && !(uri.scheme == 'http' && isLoopback)) {
    throw ArgumentError.value(
      uri,
      'baseUri',
      'remote Bridge origins must use HTTPS',
    );
  }
  return uri.replace(path: '', query: null, fragment: null);
}

String _requiredArgument(String value, String name) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(value, name, 'is required');
  }
  return normalized;
}

Map<String, dynamic> _decodeMap(String raw) {
  try {
    return _map(jsonDecode(raw), 'response');
  } on FormatException {
    rethrow;
  } catch (_) {
    throw const FormatException('Response must be a JSON object.');
  }
}

Map<String, dynamic> _map(Object? value, String name) {
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  throw FormatException('$name must be a JSON object.');
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key]?.toString().trim() ?? '';
  if (value.isEmpty) {
    throw FormatException('$key is required.');
  }
  return value;
}

String _optionalString(
  Map<String, dynamic> json,
  String key, {
  required String fallback,
}) {
  final value = json[key]?.toString().trim() ?? '';
  return value.isEmpty ? fallback : value;
}

int _requiredNonNegativeInt(Map<String, dynamic> json, String key) {
  final raw = json[key];
  final value = raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? '');
  if (value == null || value < 0) {
    throw FormatException('$key must be a non-negative integer.');
  }
  return value;
}
