import 'dart:convert';

import 'package:http/http.dart' as http;

import '../runtime/runtime_models.dart';
import 'web_store.dart';

abstract class WebSessionRepository {
  Future<List<AssistantThreadRecord>> loadThreadRecords();

  Future<void> saveThreadRecords(List<AssistantThreadRecord> records);
}

class BrowserWebSessionRepository implements WebSessionRepository {
  const BrowserWebSessionRepository(this._store);

  final WebStore _store;

  @override
  Future<List<AssistantThreadRecord>> loadThreadRecords() {
    return _store.loadAssistantThreadRecords();
  }

  @override
  Future<void> saveThreadRecords(List<AssistantThreadRecord> records) {
    return _store.saveAssistantThreadRecords(records);
  }
}

class RemoteWebSessionRepository implements WebSessionRepository {
  RemoteWebSessionRepository({
    required String baseUrl,
    required String clientId,
    String accessToken = '',
    http.Client? client,
  }) : _baseUri = _normalizeBaseUri(baseUrl),
       _clientId = clientId.trim(),
       _accessToken = accessToken.trim(),
       _client = client ?? http.Client();

  final Uri? _baseUri;
  final String _clientId;
  final String _accessToken;
  final http.Client _client;

  static Uri? normalizeBaseUrl(String raw) => _normalizeBaseUri(raw);

  @override
  Future<List<AssistantThreadRecord>> loadThreadRecords() async {
    final uri = _threadsUri();
    final response = await _client.get(uri, headers: _headers());
    _throwIfError(response, fallbackMessage: 'Remote session load failed');
    final body = response.body.trim();
    if (body.isEmpty) {
      return const <AssistantThreadRecord>[];
    }
    final decoded = jsonDecode(body);
    final rawThreads = switch (decoded) {
      List<dynamic> items => items,
      Map<String, dynamic> map => map['threads'] as List<dynamic>? ?? const [],
      _ => const <dynamic>[],
    };
    return rawThreads
        .whereType<Map>()
        .map(
          (item) =>
              AssistantThreadRecord.fromJson(item.cast<String, dynamic>()),
        )
        .toList(growable: false);
  }

  @override
  Future<void> saveThreadRecords(List<AssistantThreadRecord> records) async {
    final uri = _threadsUri();
    final response = await _client.put(
      uri,
      headers: _headers(contentTypeJson: true),
      body: jsonEncode(<String, dynamic>{
        'threads': records.map((item) => item.toJson()).toList(growable: false),
      }),
    );
    _throwIfError(response, fallbackMessage: 'Remote session save failed');
  }

  Uri _threadsUri() {
    final baseUri = _baseUri;
    if (baseUri == null) {
      throw const WebSessionRepositoryException(
        'Missing remote session API URL.',
      );
    }
    final pathSegments = <String>[
      ...baseUri.pathSegments.where((item) => item.isNotEmpty),
      'threads',
    ];
    return baseUri.replace(pathSegments: pathSegments);
  }

  Map<String, String> _headers({bool contentTypeJson = false}) {
    return <String, String>{
      'Accept': 'application/json',
      if (contentTypeJson) 'Content-Type': 'application/json',
      if (_clientId.isNotEmpty) 'X-XWorkmate-Client-Id': _clientId,
      if (_accessToken.isNotEmpty) 'Authorization': 'Bearer $_accessToken',
    };
  }

  void _throwIfError(
    http.Response response, {
    required String fallbackMessage,
  }) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }
    final body = response.body.trim();
    if (body.isEmpty) {
      throw WebSessionRepositoryException(
        '$fallbackMessage (${response.statusCode})',
      );
    }
    String? message;
    try {
      final decoded = jsonDecode(body);
      message = switch (decoded) {
        Map<String, dynamic> map =>
          map['message']?.toString().trim() ??
              (map['error'] is Map
                  ? (map['error'] as Map)['message']?.toString().trim()
                  : null),
        _ => null,
      };
    } catch (_) {
      message = null;
    }
    if (message != null && message.isNotEmpty) {
      throw WebSessionRepositoryException(
        '$fallbackMessage (${response.statusCode}) · $message',
      );
    }
    throw WebSessionRepositoryException(
      '$fallbackMessage (${response.statusCode})',
    );
  }

  static Uri? _normalizeBaseUri(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final candidate = trimmed.contains('://') ? trimmed : 'https://$trimmed';
    final uri = Uri.tryParse(candidate);
    if (uri == null || uri.host.trim().isEmpty) {
      return null;
    }
    final scheme = uri.scheme.trim().toLowerCase();
    if (scheme == 'http' && !_isLoopbackHost(uri.host)) {
      return null;
    }
    if (scheme != 'http' && scheme != 'https') {
      return null;
    }
    final segments = uri.pathSegments
        .where((item) => item.isNotEmpty)
        .toList(growable: true);
    if (segments.isNotEmpty && segments.last == 'threads') {
      segments.removeLast();
    }
    if (segments.isEmpty) {
      segments.addAll(const <String>['v1', 'web-sessions']);
    }
    return uri.replace(pathSegments: segments, query: null, fragment: null);
  }

  static bool _isLoopbackHost(String host) {
    final normalized = host.trim().toLowerCase();
    return normalized == 'localhost' ||
        normalized == '127.0.0.1' ||
        normalized == '::1' ||
        normalized == '[::1]';
  }
}

class WebSessionRepositoryException implements Exception {
  const WebSessionRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}
