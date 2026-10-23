import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'session_sync_contract.dart';

/// Shared task sessions held by Accounts and reached through the Bridge
/// `/api/v1` proxy with the signed-in account token. Accounts is the only
/// durable task state (AI Workspace v2.1); the DSH orchestrator claims the
/// queued runs and appends their events.
class TaskSessionException implements Exception {
  const TaskSessionException({
    required this.statusCode,
    required this.code,
    required this.message,
  });

  final int statusCode;
  final String code;
  final String message;

  @override
  String toString() => 'TaskSessionException($statusCode, $code, $message)';
}

class TaskSessionSummary {
  const TaskSessionSummary({
    required this.sessionId,
    required this.title,
    required this.lastEventSeq,
    required this.updatedAt,
    required this.lastRunState,
  });

  factory TaskSessionSummary.fromJson(Map<String, dynamic> json) {
    final context = _asMap(json['context']);
    return TaskSessionSummary(
      sessionId: _string(json['sessionId']),
      title: _string(json['title']),
      lastEventSeq: _int(json['lastEventSeq']),
      updatedAt: DateTime.tryParse(_string(json['updatedAt'])),
      lastRunState: _string(context['lastRunState']),
    );
  }

  final String sessionId;
  final String title;
  final int lastEventSeq;
  final DateTime? updatedAt;
  final String lastRunState;
}

class TaskSessionEvent {
  const TaskSessionEvent({
    required this.seq,
    required this.type,
    required this.payload,
    required this.createdAt,
  });

  factory TaskSessionEvent.fromJson(Map<String, dynamic> json) {
    return TaskSessionEvent(
      seq: _int(json['seq']),
      type: _string(json['type']),
      payload: _asMap(json['payload']),
      createdAt: DateTime.tryParse(_string(json['createdAt'])),
    );
  }

  final int seq;
  final String type;
  final Map<String, dynamic> payload;
  final DateTime? createdAt;

  String get taskRunId => _string(payload['taskRunId']);
}

class TaskEventPage {
  const TaskEventPage({required this.events, required this.lastEventSeq});

  final List<TaskSessionEvent> events;
  final int lastEventSeq;
}

class TaskMessageReceipt {
  const TaskMessageReceipt({required this.taskRunId, required this.eventSeq});

  final String taskRunId;
  final int eventSeq;
}

abstract class TaskSessionClient {
  Future<String> personalNamespaceId();

  Future<List<TaskSessionSummary>> listSessions(String namespaceId);

  Future<TaskSessionSummary> createSession({
    required String namespaceId,
    required String title,
  });

  /// [routing] carries orchestrator hints: role, roleMode, workspace key …;
  /// Accounts validates them and never stores paths.
  Future<TaskMessageReceipt> appendMessage({
    required String sessionId,
    required String clientRequestId,
    required String text,
    Map<String, Object?> routing = const <String, Object?>{},
  });

  Future<TaskEventPage> listEvents({
    required String sessionId,
    int afterSeq = 0,
    int limit = 100,
  });

  Future<void> cancelRun({
    required String sessionId,
    required String taskRunId,
    required String clientRequestId,
  });
}

/// Optional canonical lookup capability. Kept separate so existing
/// `implements TaskSessionClient` integrations remain source-compatible.
abstract interface class TaskSessionSnapshotReader {
  Future<CloudSessionSnapshot> loadSnapshot(String sessionId);
}

extension TaskSessionSnapshotLookup on TaskSessionClient {
  Future<CloudSessionSnapshot> loadSessionSnapshot(String sessionId) {
    final client = this;
    if (client is TaskSessionSnapshotReader) {
      return (client as TaskSessionSnapshotReader).loadSnapshot(sessionId);
    }
    throw UnsupportedError(
      'This task client does not support session snapshots.',
    );
  }
}

class HttpTaskSessionClient
    implements TaskSessionClient, TaskSessionSnapshotReader {
  HttpTaskSessionClient({
    required Uri bridgeBase,
    required String accountToken,
    HttpClient Function()? httpClientFactory,
    this.timeout = const Duration(seconds: 10),
  }) : _base = bridgeBase.replace(
         path: _trimSlash(bridgeBase.path),
         query: null,
         fragment: null,
       ),
       _token = accountToken.trim(),
       _httpClientFactory = httpClientFactory ?? HttpClient.new;

  final Uri _base;
  final String _token;
  final HttpClient Function() _httpClientFactory;
  final Duration timeout;

  static String _trimSlash(String path) =>
      path.replaceFirst(RegExp(r'/+$'), '');

  Uri _uri(List<String> segments, [Map<String, String>? query]) {
    final encoded = segments.map(Uri.encodeComponent).join('/');
    return _base.replace(
      path: '${_base.path}/api/v1/$encoded',
      queryParameters: query,
    );
  }

  Future<Map<String, dynamic>> _request(
    String method,
    Uri uri, {
    Map<String, Object?>? body,
  }) async {
    if (_token.isEmpty) {
      throw const TaskSessionException(
        statusCode: 401,
        code: 'account_sign_in_required',
        message: 'Sign in to the account to use Bot tasks',
      );
    }
    final client = _httpClientFactory()..connectionTimeout = timeout;
    try {
      final request = await client.openUrl(method, uri).timeout(timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_token');
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response = await request.close().timeout(timeout);
      final raw = await utf8.decoder.bind(response).join().timeout(timeout);
      Map<String, dynamic> decoded = const <String, dynamic>{};
      if (raw.trim().isNotEmpty) {
        try {
          decoded = _asMap(jsonDecode(raw));
        } on FormatException {
          decoded = const <String, dynamic>{};
        }
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final error = _asMap(decoded['error']);
        throw TaskSessionException(
          statusCode: response.statusCode,
          code: _string(error['code']).isEmpty
              ? 'http_${response.statusCode}'
              : _string(error['code']),
          message: _string(error['message']).isEmpty
              ? 'Task session request failed (${response.statusCode})'
              : _string(error['message']),
        );
      }
      return decoded;
    } on TaskSessionException {
      rethrow;
    } on TimeoutException {
      throw const TaskSessionException(
        statusCode: 0,
        code: 'task_session_timeout',
        message: 'The task service did not answer in time',
      );
    } on SocketException catch (error) {
      throw TaskSessionException(
        statusCode: 0,
        code: 'task_session_unreachable',
        message: 'The task service is unreachable: ${error.message}',
      );
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<String> personalNamespaceId() async {
    final body = await _request('GET', _uri(<String>['namespaces']));
    for (final item in _asList(body['namespaces'])) {
      final namespace = _asMap(item);
      if (_string(namespace['slug']) == 'personal') {
        return _string(namespace['namespaceId']);
      }
    }
    throw const TaskSessionException(
      statusCode: 404,
      code: 'personal_namespace_missing',
      message: 'The account has no personal task namespace',
    );
  }

  @override
  Future<List<TaskSessionSummary>> listSessions(String namespaceId) async {
    final body = await _request(
      'GET',
      _uri(<String>['namespaces', namespaceId, 'sessions']),
    );
    return _asList(body['sessions'])
        .map((item) => TaskSessionSummary.fromJson(_asMap(item)))
        .where((session) => session.sessionId.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Future<CloudSessionSnapshot> loadSnapshot(String sessionId) async {
    final body = await _request('GET', _uri(<String>['sessions', sessionId]));
    return CloudSessionSnapshot.fromJson(body);
  }

  @override
  Future<TaskSessionSummary> createSession({
    required String namespaceId,
    required String title,
  }) async {
    final body = await _request(
      'POST',
      _uri(<String>['namespaces', namespaceId, 'sessions']),
      body: <String, Object?>{'title': title},
    );
    return TaskSessionSummary.fromJson(body);
  }

  @override
  Future<TaskMessageReceipt> appendMessage({
    required String sessionId,
    required String clientRequestId,
    required String text,
    Map<String, Object?> routing = const <String, Object?>{},
  }) async {
    final body = await _request(
      'POST',
      _uri(<String>['sessions', sessionId, 'messages']),
      body: <String, Object?>{
        'clientRequestId': clientRequestId,
        'text': text,
        if (routing.isNotEmpty) 'routing': routing,
      },
    );
    return TaskMessageReceipt(
      taskRunId: _string(_asMap(body['taskRun'])['id']),
      eventSeq: _int(_asMap(body['event'])['seq']),
    );
  }

  @override
  Future<TaskEventPage> listEvents({
    required String sessionId,
    int afterSeq = 0,
    int limit = 100,
  }) async {
    final body = await _request(
      'GET',
      _uri(
        <String>['sessions', sessionId, 'events'],
        <String, String>{'after_seq': '$afterSeq', 'limit': '$limit'},
      ),
    );
    return TaskEventPage(
      events: _asList(body['events'])
          .map((item) => TaskSessionEvent.fromJson(_asMap(item)))
          .toList(growable: false),
      lastEventSeq: _int(body['lastEventSeq']),
    );
  }

  @override
  Future<void> cancelRun({
    required String sessionId,
    required String taskRunId,
    required String clientRequestId,
  }) async {
    await _request(
      'POST',
      _uri(<String>['sessions', sessionId, 'runs', taskRunId, 'cancel']),
      body: <String, Object?>{'clientRequestId': clientRequestId},
    );
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

List<Object?> _asList(Object? value) =>
    value is List ? value : const <Object?>[];

String _string(Object? value) => value?.toString().trim() ?? '';

int _int(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(_string(value)) ?? 0;
}
