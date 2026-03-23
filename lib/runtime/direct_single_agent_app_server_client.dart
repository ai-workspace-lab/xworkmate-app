import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'runtime_models.dart';

class DirectSingleAgentCapabilities {
  const DirectSingleAgentCapabilities({
    required this.available,
    required this.supportedProviders,
    required this.endpoint,
    this.errorMessage,
  });

  const DirectSingleAgentCapabilities.unavailable({
    required this.endpoint,
    this.errorMessage,
  }) : available = false,
       supportedProviders = const <SingleAgentProvider>[];

  final bool available;
  final List<SingleAgentProvider> supportedProviders;
  final String endpoint;
  final String? errorMessage;

  bool get supportsCodex => supportsProvider(SingleAgentProvider.codex);

  bool supportsProvider(SingleAgentProvider provider) =>
      supportedProviders.contains(provider);
}

class DirectSingleAgentRunResult {
  const DirectSingleAgentRunResult({
    required this.success,
    required this.output,
    required this.errorMessage,
    this.aborted = false,
  });

  final bool success;
  final String output;
  final String errorMessage;
  final bool aborted;
}

class DirectSingleAgentRunRequest {
  const DirectSingleAgentRunRequest({
    required this.sessionId,
    required this.provider,
    required this.prompt,
    required this.model,
    required this.workingDirectory,
    required this.gatewayToken,
    this.onOutput,
  });

  final String sessionId;
  final SingleAgentProvider provider;
  final String prompt;
  final String model;
  final String workingDirectory;
  final String gatewayToken;
  final void Function(String text)? onOutput;
}

class DirectSingleAgentAppServerClient {
  DirectSingleAgentAppServerClient({required this.endpointResolver});

  final Uri? Function(SingleAgentProvider provider) endpointResolver;

  final Map<String, _DirectAppServerConnection> _activeConnections =
      <String, _DirectAppServerConnection>{};
  final Map<String, String> _threadIds = <String, String>{};
  final Set<String> _abortedSessions = <String>{};

  final Map<SingleAgentProvider, DirectSingleAgentCapabilities>
  _cachedCapabilities = <SingleAgentProvider, DirectSingleAgentCapabilities>{};
  final Map<SingleAgentProvider, DateTime> _capabilitiesRefreshedAt =
      <SingleAgentProvider, DateTime>{};

  Future<DirectSingleAgentCapabilities> loadCapabilities({
    required SingleAgentProvider provider,
    bool forceRefresh = false,
    String gatewayToken = '',
  }) async {
    final cached = _cachedCapabilities[provider];
    final refreshedAt = _capabilitiesRefreshedAt[provider];
    if (!forceRefresh &&
        cached != null &&
        refreshedAt != null &&
        DateTime.now().difference(refreshedAt) < const Duration(seconds: 15)) {
      return cached;
    }

    final endpoint = _resolveWebSocketEndpoint(provider);
    if (endpoint == null) {
      final unavailable = const DirectSingleAgentCapabilities.unavailable(
        endpoint: '',
        errorMessage: 'Single-agent app-server endpoint is not configured.',
      );
      _cachedCapabilities[provider] = unavailable;
      _capabilitiesRefreshedAt[provider] = DateTime.now();
      return unavailable;
    }

    _DirectAppServerConnection? connection;
    try {
      connection = await _DirectAppServerConnection.connect(
        endpoint,
        gatewayToken: gatewayToken,
      );
      await connection.initialize();
      _cachedCapabilities[provider] = DirectSingleAgentCapabilities(
        available: true,
        supportedProviders: <SingleAgentProvider>[provider],
        endpoint: endpoint.toString(),
      );
    } catch (error) {
      _cachedCapabilities[provider] = DirectSingleAgentCapabilities.unavailable(
        endpoint: endpoint.toString(),
        errorMessage: error.toString(),
      );
    } finally {
      _capabilitiesRefreshedAt[provider] = DateTime.now();
      await connection?.close();
    }

    return _cachedCapabilities[provider]!;
  }

  Future<DirectSingleAgentRunResult> run(
    DirectSingleAgentRunRequest request,
  ) async {
    final endpoint = _resolveWebSocketEndpoint(request.provider);
    if (endpoint == null) {
      return const DirectSingleAgentRunResult(
        success: false,
        output: '',
        errorMessage: 'Single-agent app-server endpoint is missing.',
      );
    }

    final normalizedSessionId = request.sessionId.trim();
    if (normalizedSessionId.isEmpty) {
      return const DirectSingleAgentRunResult(
        success: false,
        output: '',
        errorMessage: 'Single-agent session id is missing.',
      );
    }

    _abortedSessions.remove(normalizedSessionId);
    final connection = await _DirectAppServerConnection.connect(
      endpoint,
      gatewayToken: request.gatewayToken,
    );
    _activeConnections[normalizedSessionId] = connection;

    try {
      await connection.initialize();
      final threadId = await _ensureThread(
        connection,
        sessionId: normalizedSessionId,
        workingDirectory: request.workingDirectory,
        model: request.model,
      );

      final output = StringBuffer();
      final completion = Completer<DirectSingleAgentRunResult>();
      late final StreamSubscription<Map<String, dynamic>> subscription;
      subscription = connection.notifications.listen(
        (notification) {
          final method = notification['method']?.toString().trim() ?? '';
          final params = _asMap(notification['params']);
          if (params['threadId']?.toString() != threadId) {
            return;
          }
          if (method == 'item/agentMessage/delta') {
            final delta = params['delta']?.toString() ?? '';
            if (delta.isNotEmpty) {
              output.write(delta);
              request.onOutput?.call(delta);
            }
            return;
          }
          if (method == 'turn/completed' && !completion.isCompleted) {
            completion.complete(
              DirectSingleAgentRunResult(
                success: true,
                output: output.toString(),
                errorMessage: '',
              ),
            );
            return;
          }
          if ((method == 'turn/failed' || method == 'turn/error') &&
              !completion.isCompleted) {
            final aborted =
                _abortedSessions.contains(normalizedSessionId) ||
                (params['message']?.toString().toLowerCase().contains(
                      'abort',
                    ) ??
                    false);
            completion.complete(
              DirectSingleAgentRunResult(
                success: false,
                output: output.toString(),
                aborted: aborted,
                errorMessage:
                    params['message']?.toString() ??
                    params['error']?.toString() ??
                    'Single-agent app-server turn failed.',
              ),
            );
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!completion.isCompleted) {
            completion.complete(
              DirectSingleAgentRunResult(
                success: false,
                output: output.toString(),
                errorMessage: error.toString(),
                aborted: _abortedSessions.contains(normalizedSessionId),
              ),
            );
          }
        },
        onDone: () {
          if (!completion.isCompleted) {
            completion.complete(
              DirectSingleAgentRunResult(
                success: false,
                output: output.toString(),
                errorMessage: _abortedSessions.contains(normalizedSessionId)
                    ? 'Single-agent app-server run aborted.'
                    : 'Single-agent app-server connection closed before completion.',
                aborted: _abortedSessions.contains(normalizedSessionId),
              ),
            );
          }
        },
      );

      try {
        await connection.request(
          'turn/start',
          params: <String, dynamic>{
            'threadId': threadId,
            'userInput': <String, dynamic>{
              'type': 'message',
              'content': request.prompt,
            },
          },
        );
        return await completion.future.timeout(
          const Duration(minutes: 10),
          onTimeout: () => DirectSingleAgentRunResult(
            success: false,
            output: output.toString(),
            errorMessage: 'Single-agent app-server request timed out.',
            aborted: _abortedSessions.contains(normalizedSessionId),
          ),
        );
      } finally {
        await subscription.cancel();
      }
    } catch (error) {
      return DirectSingleAgentRunResult(
        success: false,
        output: '',
        errorMessage: error.toString(),
        aborted: _abortedSessions.contains(normalizedSessionId),
      );
    } finally {
      _activeConnections.remove(normalizedSessionId);
      await connection.close();
      _abortedSessions.remove(normalizedSessionId);
    }
  }

  Future<void> abort(String sessionId) async {
    final normalizedSessionId = sessionId.trim();
    if (normalizedSessionId.isEmpty) {
      return;
    }
    _abortedSessions.add(normalizedSessionId);
    final connection = _activeConnections[normalizedSessionId];
    final threadId = _threadIds[normalizedSessionId];
    if (connection == null || threadId == null || threadId.isEmpty) {
      return;
    }
    try {
      await connection.request(
        'turn/interrupt',
        params: <String, dynamic>{'threadId': threadId},
      );
    } catch (_) {
      // Best effort only.
    }
    await connection.close();
  }

  Future<void> dispose() async {
    final connections = _activeConnections.values.toList(growable: false);
    _activeConnections.clear();
    for (final connection in connections) {
      await connection.close();
    }
  }

  Future<String> _ensureThread(
    _DirectAppServerConnection connection, {
    required String sessionId,
    required String workingDirectory,
    required String model,
  }) async {
    final existingThreadId = _threadIds[sessionId]?.trim() ?? '';
    if (existingThreadId.isNotEmpty) {
      try {
        final resumed = await connection.request(
          'thread/resume',
          params: <String, dynamic>{
            'threadId': existingThreadId,
            if (workingDirectory.trim().isNotEmpty) 'cwd': workingDirectory,
          },
        );
        final resumedId = resumed['id']?.toString().trim() ?? existingThreadId;
        _threadIds[sessionId] = resumedId;
        return resumedId;
      } catch (_) {
        _threadIds.remove(sessionId);
      }
    }

    final created = await connection.request(
      'thread/start',
      params: <String, dynamic>{
        if (workingDirectory.trim().isNotEmpty) 'cwd': workingDirectory,
        if (model.trim().isNotEmpty) 'model': model.trim(),
      },
    );
    final threadId = created['id']?.toString().trim() ?? '';
    if (threadId.isEmpty) {
      throw StateError('Single-agent app-server returned an empty thread id.');
    }
    _threadIds[sessionId] = threadId;
    return threadId;
  }

  Uri? _resolveWebSocketEndpoint(SingleAgentProvider provider) {
    final base = endpointResolver(provider);
    if (base == null) {
      return null;
    }
    final scheme = base.scheme.toLowerCase();
    if (scheme == 'ws' || scheme == 'wss') {
      return base.replace(path: '', query: null, fragment: null);
    }
    if (scheme == 'http' || scheme == 'https') {
      return base.replace(
        scheme: scheme == 'https' ? 'wss' : 'ws',
        path: '',
        query: null,
        fragment: null,
      );
    }
    return null;
  }
}

class _DirectAppServerConnection {
  _DirectAppServerConnection(this._socket);

  final WebSocket _socket;
  final StreamController<Map<String, dynamic>> _notifications =
      StreamController<Map<String, dynamic>>.broadcast();
  final Map<String, Completer<Map<String, dynamic>>> _pendingRequests =
      <String, Completer<Map<String, dynamic>>>{};
  int _requestCounter = 0;
  bool _initialized = false;
  StreamSubscription<dynamic>? _subscription;

  Stream<Map<String, dynamic>> get notifications => _notifications.stream;

  static Future<_DirectAppServerConnection> connect(
    Uri endpoint, {
    String gatewayToken = '',
  }) async {
    final headers = <String, dynamic>{};
    final normalizedToken = gatewayToken.trim();
    if (normalizedToken.isNotEmpty) {
      headers[HttpHeaders.authorizationHeader] = 'Bearer $normalizedToken';
    }
    final socket =
        await WebSocket.connect(
          endpoint.toString(),
          headers: headers.isEmpty ? null : headers,
        ).timeout(
          const Duration(seconds: 8),
          onTimeout: () => throw TimeoutException(
            'Single-agent app-server websocket connect timed out.',
          ),
        );
    final connection = _DirectAppServerConnection(socket);
    connection._attach();
    return connection;
  }

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    await request(
      'initialize',
      params: const <String, dynamic>{
        'clientInfo': <String, dynamic>{'name': 'xworkmate', 'version': '0'},
        'capabilities': <String, dynamic>{
          'optOutNotificationMethods': <String>[],
        },
      },
    );
    await notify('initialized', params: const <String, dynamic>{});
    _initialized = true;
  }

  Future<Map<String, dynamic>> request(
    String method, {
    Map<String, dynamic> params = const <String, dynamic>{},
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final id = '${DateTime.now().microsecondsSinceEpoch}-${_requestCounter++}';
    final completer = Completer<Map<String, dynamic>>();
    _pendingRequests[id] = completer;
    _socket.add(
      jsonEncode(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': params,
      }),
    );
    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _pendingRequests.remove(id);
        throw TimeoutException(
          'Single-agent app-server request $method timed out.',
        );
      },
    );
  }

  Future<void> notify(
    String method, {
    required Map<String, dynamic> params,
  }) async {
    _socket.add(
      jsonEncode(<String, dynamic>{
        'jsonrpc': '2.0',
        'method': method,
        'params': params,
      }),
    );
  }

  void _attach() {
    _subscription = _socket.listen(
      (dynamic raw) {
        final message = _decodeMap(raw);
        final id = message['id']?.toString();
        if (id != null && message.containsKey('result')) {
          final completer = _pendingRequests.remove(id);
          if (completer != null && !completer.isCompleted) {
            completer.complete(_asMap(message['result']));
          }
          return;
        }
        if (id != null && message.containsKey('error')) {
          final completer = _pendingRequests.remove(id);
          if (completer != null && !completer.isCompleted) {
            final error = _asMap(message['error']);
            completer.completeError(
              StateError(
                error['message']?.toString() ??
                    'Single-agent app-server request failed.',
              ),
            );
          }
          return;
        }
        if (message.containsKey('method')) {
          _notifications.add(message);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        for (final completer in _pendingRequests.values) {
          if (!completer.isCompleted) {
            completer.completeError(error);
          }
        }
        _pendingRequests.clear();
        _notifications.addError(error, stackTrace);
      },
      onDone: () {
        final error = StateError(
          'Single-agent app-server websocket closed unexpectedly.',
        );
        for (final completer in _pendingRequests.values) {
          if (!completer.isCompleted) {
            completer.completeError(error);
          }
        }
        _pendingRequests.clear();
        if (!_notifications.isClosed) {
          unawaited(_notifications.close());
        }
      },
      cancelOnError: true,
    );
  }

  Future<void> close() async {
    await _subscription?.cancel();
    _subscription = null;
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError('Single-agent app-server connection closed.'),
        );
      }
    }
    _pendingRequests.clear();
    if (!_notifications.isClosed) {
      await _notifications.close();
    }
    try {
      await _socket.close();
    } catch (_) {
      // Best effort only.
    }
  }
}

Map<String, dynamic> _decodeMap(Object raw) {
  if (raw is Map<String, dynamic>) {
    return raw;
  }
  if (raw is Map) {
    return raw.cast<String, dynamic>();
  }
  final decoded = jsonDecode(raw.toString());
  if (decoded is Map<String, dynamic>) {
    return decoded;
  }
  if (decoded is Map) {
    return decoded.cast<String, dynamic>();
  }
  return const <String, dynamic>{};
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
