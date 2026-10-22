import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Read-only client for the shared Code Agent task context exposed by QMD and
/// forwarded through `xworkmate-bridge` (`/api/v1/agent/*`).
///
/// The client never writes to QMD (`ingest` is intentionally omitted in phase 1)
/// and strips any accidental machine-local absolute paths from locations or
/// touched-path items before they reach app state.
class AgentContextException implements Exception {
  const AgentContextException({
    required this.statusCode,
    required this.code,
    required this.message,
  });

  final int statusCode;
  final String code;
  final String message;

  @override
  String toString() => 'AgentContextException($statusCode, $code, $message)';
}

final RegExp _absolutePathPattern = RegExp(
  r'^(?:/Users/|/home/|/private/|/var/|/tmp/|/opt/|/etc/|[A-Za-z]:[\\/]|\\\\)',
  caseSensitive: false,
);

/// Returns true if [value] looks like a host-specific absolute filesystem path.
bool isAbsoluteFilesystemPath(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return false;
  }
  if (_absolutePathPattern.hasMatch(trimmed)) {
    return true;
  }
  return trimmed.startsWith('/');
}

String? _sanitizeRelativeLocation(String? raw) {
  final trimmed = raw?.trim() ?? '';
  if (trimmed.isEmpty || isAbsoluteFilesystemPath(trimmed)) {
    return null;
  }
  return trimmed;
}

class QmdPinnedTask {
  const QmdPinnedTask({
    required this.id,
    required this.source,
    required this.title,
    this.scope,
    this.location,
    this.projectName,
    this.gitBranch,
    this.position = 0,
    this.updatedAt,
    this.removedAt,
  });

  factory QmdPinnedTask.fromJson(Map<String, dynamic> json) {
    return QmdPinnedTask(
      id: _string(json['id']),
      source: _string(json['source']).isEmpty
          ? 'qmd'
          : _string(json['source']),
      title: _string(json['title']),
      scope: _sanitizeRelativeLocation(_nullableString(json['scope'])),
      location: _sanitizeRelativeLocation(_nullableString(json['location'])),
      projectName: _nullableString(json['projectName']),
      gitBranch: _nullableString(json['gitBranch']),
      position: _int(json['position']),
      updatedAt: DateTime.tryParse(_string(json['updatedAt'])),
      removedAt: DateTime.tryParse(_string(json['removedAt'])),
    );
  }

  final String id;
  final String source;
  final String title;
  final String? scope;
  final String? location;
  final String? projectName;
  final String? gitBranch;
  final int position;
  final DateTime? updatedAt;
  final DateTime? removedAt;

  bool get isRemoved => removedAt != null;
}

class QmdSharedProject {
  const QmdSharedProject({
    required this.key,
    required this.name,
    required this.kind,
    this.scope,
    this.location,
    this.sources = const <String>[],
    this.updatedAt,
    this.removedAt,
  });

  factory QmdSharedProject.fromJson(Map<String, dynamic> json) {
    return QmdSharedProject(
      key: _string(json['key']),
      name: _string(json['name']),
      kind: _string(json['kind']),
      scope: _sanitizeRelativeLocation(_nullableString(json['scope'])),
      location: _sanitizeRelativeLocation(_nullableString(json['location'])),
      sources: _stringList(json['sources']),
      updatedAt: DateTime.tryParse(_string(json['updatedAt'])),
      removedAt: DateTime.tryParse(_string(json['removedAt'])),
    );
  }

  final String key;
  final String name;
  final String kind;
  final String? scope;
  final String? location;
  final List<String> sources;
  final DateTime? updatedAt;
  final DateTime? removedAt;
}

class QmdContextThread {
  const QmdContextThread({
    required this.id,
    required this.scope,
    required this.title,
    required this.state,
    this.headBranch,
    this.prNumber,
    this.prState,
    this.headSha,
    this.fence = 0,
    this.lastEventSeq = 0,
    this.itemsCount = 0,
    this.sessionsCount = 0,
    this.createdAt,
    this.updatedAt,
  });

  factory QmdContextThread.fromJson(Map<String, dynamic> json) {
    final prNum = json['prNumber'];
    return QmdContextThread(
      id: _string(json['id']),
      scope: _sanitizeRelativeLocation(_nullableString(json['scope'])) ?? '',
      title: _string(json['title']),
      state: _string(json['state']).isEmpty ? 'open' : _string(json['state']),
      headBranch: _nullableString(json['headBranch']),
      prNumber: prNum is num ? prNum.toInt() : int.tryParse(_string(prNum)),
      prState: _nullableString(json['prState']),
      headSha: _nullableString(json['headSha']),
      fence: _int(json['fence']),
      lastEventSeq: _int(json['lastEventSeq']),
      itemsCount: _int(json['items']),
      sessionsCount: _int(json['sessions']),
      createdAt: DateTime.tryParse(_string(json['createdAt'])),
      updatedAt: DateTime.tryParse(_string(json['updatedAt'])),
    );
  }

  final String id;
  final String scope;
  final String title;
  final String state;
  final String? headBranch;
  final int? prNumber;
  final String? prState;
  final String? headSha;
  final int fence;
  final int lastEventSeq;
  final int itemsCount;
  final int sessionsCount;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get displayLabel {
    if (title.trim().isNotEmpty) {
      return title.trim();
    }
    final shortScope = scope.split('/').where((s) => s.isNotEmpty).lastOrNull ??
        scope;
    if (prNumber != null) {
      return '$shortScope#$prNumber';
    }
    if ((headBranch ?? '').trim().isNotEmpty) {
      return shortScope.isEmpty
          ? headBranch!.trim()
          : '$shortScope@${headBranch!.trim()}';
    }
    return shortScope.isEmpty ? id : shortScope;
  }
}

class QmdTaskCatalog {
  const QmdTaskCatalog({
    required this.pinnedTasks,
    required this.sharedProjects,
    required this.recentThreads,
    this.limit = 50,
    this.offset = 0,
    this.pinnedTotal = 0,
    this.projectsTotal = 0,
  });

  factory QmdTaskCatalog.fromJson(Map<String, dynamic> json) {
    final page = _asMap(json['page']);
    final pinnedTasks = _asList(json['pinnedTasks'])
        .map((item) => QmdPinnedTask.fromJson(_asMap(item)))
        .where((item) => item.id.isNotEmpty && !item.isRemoved)
        .toList(growable: false);
    final sharedProjects = _asList(json['sharedProjects'])
        .map((item) => QmdSharedProject.fromJson(_asMap(item)))
        .where(
          (item) =>
              item.key.isNotEmpty &&
              !isAbsoluteFilesystemPath(item.key) &&
              item.removedAt == null,
        )
        .toList(growable: false);
    final recentThreads = _asList(json['recentThreads'])
        .map((item) => QmdContextThread.fromJson(_asMap(item)))
        .where((item) => item.id.isNotEmpty && item.scope.isNotEmpty)
        .toList(growable: false);
    return QmdTaskCatalog(
      pinnedTasks: pinnedTasks,
      sharedProjects: sharedProjects,
      recentThreads: recentThreads,
      limit: _int(page['limit'], fallback: 50),
      offset: _int(page['offset']),
      pinnedTotal: _int(page['pinnedTotal'], fallback: pinnedTasks.length),
      projectsTotal: _int(
        page['projectsTotal'],
        fallback: sharedProjects.length,
      ),
    );
  }

  final List<QmdPinnedTask> pinnedTasks;
  final List<QmdSharedProject> sharedProjects;
  final List<QmdContextThread> recentThreads;
  final int limit;
  final int offset;
  final int pinnedTotal;
  final int projectsTotal;
}

class QmdThreadPage {
  const QmdThreadPage({
    required this.threads,
    this.limit = 50,
    this.offset = 0,
    this.total = 0,
  });

  factory QmdThreadPage.fromJson(Map<String, dynamic> json) {
    final page = _asMap(json['page']);
    final threads = _asList(json['threads'])
        .map((item) => QmdContextThread.fromJson(_asMap(item)))
        .where((item) => item.id.isNotEmpty && item.scope.isNotEmpty)
        .toList(growable: false);
    return QmdThreadPage(
      threads: threads,
      limit: _int(page['limit'], fallback: 50),
      offset: _int(page['offset']),
      total: _int(page['total'], fallback: threads.length),
    );
  }

  final List<QmdContextThread> threads;
  final int limit;
  final int offset;
  final int total;
}

class QmdBriefingItem {
  const QmdBriefingItem({
    required this.kind,
    required this.key,
    required this.status,
    required this.text,
    this.ord,
    this.detail,
    this.at,
    this.gitHead,
    this.sources = const <String>[],
  });

  factory QmdBriefingItem.fromJson(Map<String, dynamic> json) {
    return QmdBriefingItem(
      kind: _string(json['kind']),
      key: _string(json['key']),
      status: _string(json['status']),
      text: _string(json['text']),
      ord: json['ord'] is num ? (json['ord'] as num).toInt() : null,
      detail: _nullableString(json['detail']),
      at: DateTime.tryParse(_string(json['at'])),
      gitHead: _nullableString(json['gitHead']),
      sources: _stringList(json['sources']),
    );
  }

  final String kind;
  final String key;
  final String status;
  final String text;
  final int? ord;
  final String? detail;
  final DateTime? at;
  final String? gitHead;
  final List<String> sources;
}

class QmdBriefingContributor {
  const QmdBriefingContributor({
    required this.source,
    required this.sessions,
    this.lastSeenAt,
  });

  factory QmdBriefingContributor.fromJson(Map<String, dynamic> json) {
    return QmdBriefingContributor(
      source: _string(json['source']),
      sessions: _int(json['sessions']),
      lastSeenAt: DateTime.tryParse(_string(json['lastSeenAt'])),
    );
  }

  final String source;
  final int sessions;
  final DateTime? lastSeenAt;
}

class QmdThreadBriefing {
  const QmdThreadBriefing({
    required this.thread,
    required this.items,
    required this.contributors,
  });

  factory QmdThreadBriefing.fromJson(Map<String, dynamic> json) {
    final items = _asList(json['items'])
        .map((item) => QmdBriefingItem.fromJson(_asMap(item)))
        .where((item) {
          if (item.text.trim().isEmpty) {
            return false;
          }
          if (item.kind == 'path' && isAbsoluteFilesystemPath(item.text)) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
    final contributors = _asList(json['contributors'])
        .map((item) => QmdBriefingContributor.fromJson(_asMap(item)))
        .where((item) => item.source.isNotEmpty)
        .toList(growable: false);
    return QmdThreadBriefing(
      thread: QmdContextThread.fromJson(_asMap(json['thread'])),
      items: items,
      contributors: contributors,
    );
  }

  final QmdContextThread thread;
  final List<QmdBriefingItem> items;
  final List<QmdBriefingContributor> contributors;
}

abstract class AgentContextClient {
  Future<QmdTaskCatalog> fetchCatalog({
    String? scope,
    int limit = 50,
    int offset = 0,
  });

  Future<QmdThreadPage> listThreads({
    String? scope,
    String state = 'live',
    int limit = 50,
    int offset = 0,
  });

  Future<QmdThreadBriefing> fetchBriefing(
    String threadId, {
    int events = 20,
  });
}

class HttpAgentContextClient implements AgentContextClient {
  HttpAgentContextClient({
    required Uri bridgeBase,
    required String authToken,
    HttpClient Function()? httpClientFactory,
    this.timeout = const Duration(seconds: 10),
  }) : _base = bridgeBase.replace(
         path: _trimSlash(bridgeBase.path),
         query: null,
         fragment: null,
       ),
       _token = _stripBearer(authToken),
       _httpClientFactory = httpClientFactory ?? HttpClient.new;

  final Uri _base;
  final String _token;
  final HttpClient Function() _httpClientFactory;
  final Duration timeout;

  static String _trimSlash(String path) =>
      path.replaceFirst(RegExp(r'/+$'), '');

  static String _stripBearer(String raw) {
    final trimmed = raw.trim();
    if (trimmed.toLowerCase().startsWith('bearer ')) {
      return trimmed.substring(7).trim();
    }
    return trimmed;
  }

  Uri _uri(List<String> segments, [Map<String, String>? query]) {
    final encoded = segments.map(Uri.encodeComponent).join('/');
    return _base.replace(
      path: '${_base.path}/api/v1/agent/$encoded',
      queryParameters: (query == null || query.isEmpty) ? null : query,
    );
  }

  Future<Map<String, dynamic>> _get(Uri uri) async {
    if (_token.isEmpty) {
      throw const AgentContextException(
        statusCode: 401,
        code: 'bridge_auth_required',
        message: 'Bridge authorization token is required for QMD sync',
      );
    }
    final client = _httpClientFactory()..connectionTimeout = timeout;
    try {
      final request = await client.openUrl('GET', uri).timeout(timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_token');
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
        throw AgentContextException(
          statusCode: response.statusCode,
          code: _string(error['code']).isEmpty
              ? 'http_${response.statusCode}'
              : _string(error['code']),
          message: _string(error['message']).isEmpty
              ? 'Agent context request failed (${response.statusCode})'
              : _string(error['message']),
        );
      }
      return decoded;
    } on AgentContextException {
      rethrow;
    } on TimeoutException {
      throw const AgentContextException(
        statusCode: 0,
        code: 'agent_context_timeout',
        message: 'The QMD agent context service did not answer in time',
      );
    } on SocketException catch (error) {
      throw AgentContextException(
        statusCode: 0,
        code: 'agent_context_unreachable',
        message: 'The QMD agent context service is unreachable: ${error.message}',
      );
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<QmdTaskCatalog> fetchCatalog({
    String? scope,
    int limit = 50,
    int offset = 0,
  }) async {
    final query = <String, String>{
      'limit': '${limit.clamp(1, 200)}',
      if (offset > 0) 'offset': '$offset',
      if (scope != null && scope.trim().isNotEmpty) 'scope': scope.trim(),
    };
    final body = await _get(_uri(const <String>['catalog'], query));
    return QmdTaskCatalog.fromJson(_asMap(body['catalog']));
  }

  @override
  Future<QmdThreadPage> listThreads({
    String? scope,
    String state = 'live',
    int limit = 50,
    int offset = 0,
  }) async {
    final normalizedState = state.trim().toLowerCase() == 'all'
        ? 'all'
        : 'live';
    final query = <String, String>{
      'state': normalizedState,
      'limit': '${limit.clamp(1, 200)}',
      if (offset > 0) 'offset': '$offset',
      if (scope != null && scope.trim().isNotEmpty) 'scope': scope.trim(),
    };
    final body = await _get(_uri(const <String>['threads'], query));
    return QmdThreadPage.fromJson(body);
  }

  @override
  Future<QmdThreadBriefing> fetchBriefing(
    String threadId, {
    int events = 20,
  }) async {
    final id = threadId.trim();
    if (id.isEmpty) {
      throw ArgumentError.value(threadId, 'threadId', 'must not be empty');
    }
    final query = <String, String>{
      'events': '${events.clamp(1, 200)}',
    };
    final body = await _get(
      _uri(<String>['threads', id, 'briefing'], query),
    );
    return QmdThreadBriefing.fromJson(_asMap(body['briefing']));
  }
}

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, entry) => MapEntry('$key', entry));
  }
  return const <String, dynamic>{};
}

List<Object?> _asList(Object? value) =>
    value is List ? value.cast<Object?>() : const <Object?>[];

String _string(Object? value) => value == null ? '' : '$value'.trim();

String? _nullableString(Object? value) {
  final text = _string(value);
  return text.isEmpty ? null : text;
}

List<String> _stringList(Object? value) {
  return _asList(value)
      .map(_string)
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

int _int(Object? value, {int fallback = 0}) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(_string(value)) ?? fallback;
}
