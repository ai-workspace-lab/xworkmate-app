part of 'direct_single_agent_app_server_client.dart';

class _ResolvedSingleAgentTransport {
  const _ResolvedSingleAgentTransport({
    required this.kind,
    required this.endpoint,
    required this.workspaceRefKind,
    this.websocket,
    this.rest,
  });

  final _DirectSingleAgentTransportKind kind;
  final Uri endpoint;
  final WorkspaceRefKind workspaceRefKind;
  final _DirectSingleAgentWebSocketTransport? websocket;
  final _DirectSingleAgentRestTransport? rest;
}

class _ResolvedDirectThread {
  const _ResolvedDirectThread({
    required this.threadId,
    this.workingDirectory = '',
  });

  final String threadId;
  final String workingDirectory;
}

class _DirectSingleAgentWebSocketTransport {
  final Map<String, _DirectAppServerConnection> _activeConnections =
      <String, _DirectAppServerConnection>{};
  final Map<String, String> _threadIds = <String, String>{};
  final Map<String, String> _threadWorkingDirectories = <String, String>{};
  final Set<String> _abortedSessions = <String>{};

  Future<void> probe(Uri endpoint, {required String gatewayToken}) async {
    _DirectAppServerConnection? connection;
    try {
      connection = await _DirectAppServerConnection.connect(
        endpoint,
        gatewayToken: gatewayToken,
      );
      await connection.initialize();
    } finally {
      await connection?.close();
    }
  }

  Future<DirectSingleAgentRunResult> run(
    DirectSingleAgentRunRequest request, {
    required Uri endpoint,
    required WorkspaceRefKind workspaceRefKind,
  }) async {
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
      final resolvedThread = await _ensureThread(
        connection,
        sessionId: normalizedSessionId,
        workingDirectory: request.workingDirectory,
        model: request.model,
      );
      final threadId = resolvedThread.threadId;
      final resolvedWorkingDirectory = resolvedThread.workingDirectory.trim();

      final output = StringBuffer();
      String resolvedModel = '';
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
                resolvedModel: resolvedModel,
                resolvedWorkingDirectory: resolvedWorkingDirectory,
                resolvedWorkspaceRefKind: workspaceRefKind,
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
                resolvedModel: resolvedModel,
                resolvedWorkingDirectory: resolvedWorkingDirectory,
                resolvedWorkspaceRefKind: workspaceRefKind,
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
                resolvedModel: resolvedModel,
                resolvedWorkingDirectory: resolvedWorkingDirectory,
                resolvedWorkspaceRefKind: workspaceRefKind,
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
                resolvedModel: resolvedModel,
                resolvedWorkingDirectory: resolvedWorkingDirectory,
                resolvedWorkspaceRefKind: workspaceRefKind,
              ),
            );
          }
        },
      );

      try {
        final input = <Map<String, dynamic>>[
          <String, dynamic>{'type': 'text', 'text': request.prompt},
          for (final skill in request.selectedSkills)
            if (skill.label.trim().isNotEmpty &&
                skill.sourcePath.trim().isNotEmpty)
              <String, dynamic>{
                'type': 'skill',
                'name': skill.label.trim(),
                'path': skill.sourcePath.trim(),
              },
        ];
        final started = await connection.request(
          'turn/start',
          params: <String, dynamic>{'threadId': threadId, 'input': input},
        );
        resolvedModel = _extractModel(started) ?? resolvedModel;
        return await completion.future.timeout(
          const Duration(minutes: 10),
          onTimeout: () => DirectSingleAgentRunResult(
            success: false,
            output: output.toString(),
            errorMessage: 'Single-agent app-server request timed out.',
            aborted: _abortedSessions.contains(normalizedSessionId),
            resolvedModel: resolvedModel,
            resolvedWorkingDirectory: resolvedWorkingDirectory,
            resolvedWorkspaceRefKind: workspaceRefKind,
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
        resolvedModel: '',
        resolvedWorkingDirectory: request.workingDirectory,
        resolvedWorkspaceRefKind: workspaceRefKind,
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

  Future<_ResolvedDirectThread> _ensureThread(
    _DirectAppServerConnection connection, {
    required String sessionId,
    required String workingDirectory,
    required String model,
  }) async {
    final normalizedWorkingDirectory = workingDirectory.trim();
    final existingThreadId = _threadIds[sessionId]?.trim() ?? '';
    final existingWorkingDirectory =
        _threadWorkingDirectories[sessionId]?.trim() ?? '';
    final canReuseExistingThread =
        existingThreadId.isNotEmpty &&
        (normalizedWorkingDirectory.isEmpty ||
            (existingWorkingDirectory.isNotEmpty &&
                existingWorkingDirectory == normalizedWorkingDirectory));
    if (existingThreadId.isNotEmpty) {
      if (!canReuseExistingThread) {
        _threadIds.remove(sessionId);
        _threadWorkingDirectories.remove(sessionId);
      }
    }
    if (canReuseExistingThread) {
      try {
        final resumed = await connection.request(
          'thread/resume',
          params: <String, dynamic>{
            'threadId': existingThreadId,
            if (normalizedWorkingDirectory.isNotEmpty)
              'cwd': normalizedWorkingDirectory,
          },
        );
        final resumedId = _extractThreadId(resumed) ?? existingThreadId;
        final resumedWorkingDirectory =
            _extractThreadPath(resumed)?.trim() ?? normalizedWorkingDirectory;
        _threadIds[sessionId] = resumedId;
        if (resumedWorkingDirectory.isNotEmpty) {
          _threadWorkingDirectories[sessionId] = resumedWorkingDirectory;
        }
        return _ResolvedDirectThread(
          threadId: resumedId,
          workingDirectory: resumedWorkingDirectory,
        );
      } catch (_) {
        _threadIds.remove(sessionId);
        _threadWorkingDirectories.remove(sessionId);
      }
    }

    final created = await connection.request(
      'thread/start',
      params: <String, dynamic>{
        if (normalizedWorkingDirectory.isNotEmpty)
          'cwd': normalizedWorkingDirectory,
        if (model.trim().isNotEmpty) 'model': model.trim(),
      },
    );
    final threadId = _extractThreadId(created) ?? '';
    if (threadId.isEmpty) {
      throw StateError('Single-agent app-server returned an empty thread id.');
    }
    final createdWorkingDirectory =
        _extractThreadPath(created)?.trim() ?? normalizedWorkingDirectory;
    _threadIds[sessionId] = threadId;
    if (createdWorkingDirectory.isNotEmpty) {
      _threadWorkingDirectories[sessionId] = createdWorkingDirectory;
    }
    return _ResolvedDirectThread(
      threadId: threadId,
      workingDirectory: createdWorkingDirectory,
    );
  }
}

class _DirectSingleAgentRestTransport {
  final Map<String, String> _restSessionIds = <String, String>{};
  final Map<String, String> _restSessionWorkingDirectories = <String, String>{};
  final Set<String> _abortedSessions = <String>{};

  Future<void> probe(Uri base, {required String gatewayToken}) async {
    await _fetchJson(
      _buildRestUri(base, '/global/health'),
      gatewayToken: gatewayToken,
    );
  }

  Future<DirectSingleAgentRunResult> run(
    DirectSingleAgentRunRequest request, {
    required Uri base,
    required WorkspaceRefKind workspaceRefKind,
  }) async {
    final normalizedSessionId = request.sessionId.trim();
    if (normalizedSessionId.isEmpty) {
      return const DirectSingleAgentRunResult(
        success: false,
        output: '',
        errorMessage: 'Single-agent session id is missing.',
      );
    }

    _abortedSessions.remove(normalizedSessionId);
    final remoteSessionId = await _ensureRestSession(
      base,
      sessionId: normalizedSessionId,
      workingDirectory: request.workingDirectory,
      gatewayToken: request.gatewayToken,
    );

    final output = StringBuffer();
    final completion = Completer<DirectSingleAgentRunResult>();
    String? activeAssistantMessageId;
    String? lastAssistantText;
    var busySeen = false;

    void completeFailure(String message) {
      if (completion.isCompleted) {
        return;
      }
      completion.complete(
        DirectSingleAgentRunResult(
          success: false,
          output: output.toString(),
          errorMessage: message,
          aborted: _abortedSessions.contains(normalizedSessionId),
          resolvedModel: request.model,
          resolvedWorkingDirectory: request.workingDirectory,
          resolvedWorkspaceRefKind: workspaceRefKind,
        ),
      );
    }

    final eventClient = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8);
    late final HttpClientRequest eventRequest;
    late final HttpClientResponse eventResponse;
    StreamSubscription<String>? lineSubscription;

    void completeSuccess() {
      if (completion.isCompleted) {
        return;
      }
      final resolvedOutput = output.toString().trim().isNotEmpty
          ? output.toString()
          : (lastAssistantText ?? '');
      if (resolvedOutput.trim().isEmpty) {
        completeFailure(
          'OpenCode REST session completed without assistant content.',
        );
        return;
      }
      completion.complete(
        DirectSingleAgentRunResult(
          success: true,
          output: resolvedOutput,
          errorMessage: '',
          resolvedModel: request.model,
          resolvedWorkingDirectory: request.workingDirectory,
          resolvedWorkspaceRefKind: workspaceRefKind,
        ),
      );
    }

    try {
      final eventUri = _buildRestUri(base, '/global/event');
      eventRequest = await eventClient.getUrl(eventUri);
      eventRequest.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
      final normalizedToken = request.gatewayToken.trim();
      if (normalizedToken.isNotEmpty) {
        eventRequest.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer $normalizedToken',
        );
      }
      eventResponse = await eventRequest.close();
      lineSubscription = eventResponse
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
              if (!line.startsWith('data: ')) {
                return;
              }
              final event = _decodeMap(line.substring(6));
              final payload = _asMap(event['payload']);
              final type = payload['type']?.toString().trim() ?? '';
              final properties = _asMap(payload['properties']);
              if (properties['sessionID']?.toString().trim() !=
                  remoteSessionId) {
                return;
              }
              if (type == 'session.status') {
                final status = _asMap(properties['status']);
                final statusType = status['type']?.toString().trim() ?? '';
                if (statusType == 'busy') {
                  busySeen = true;
                }
                if (statusType == 'idle' && busySeen) {
                  completeSuccess();
                }
                return;
              }
              if (type == 'session.idle' && busySeen) {
                completeSuccess();
                return;
              }
              if (type == 'session.error' && !completion.isCompleted) {
                final error = _asMap(properties['error']);
                completeFailure(
                  error['message']?.toString() ??
                      error['name']?.toString() ??
                      'OpenCode session failed.',
                );
                return;
              }
              if (type == 'message.updated') {
                final info = _asMap(properties['info']);
                if (info['role']?.toString().trim() == 'assistant') {
                  activeAssistantMessageId = info['id']?.toString().trim();
                }
                return;
              }
              if (type == 'message.part.delta') {
                final part = _asMap(properties['part']);
                if (activeAssistantMessageId != null &&
                    part['messageID']?.toString().trim() ==
                        activeAssistantMessageId) {
                  final delta =
                      properties['text']?.toString() ??
                      properties['delta']?.toString() ??
                      '';
                  if (delta.isNotEmpty) {
                    output.write(delta);
                    request.onOutput?.call(delta);
                  }
                }
                return;
              }
              if (type == 'message.part.updated') {
                final part = _asMap(properties['part']);
                if (activeAssistantMessageId != null &&
                    part['messageID']?.toString().trim() ==
                        activeAssistantMessageId &&
                    part['type']?.toString().trim() == 'text') {
                  lastAssistantText = part['text']?.toString();
                  if ((lastAssistantText?.trim().isNotEmpty ?? false)) {
                    completeSuccess();
                  }
                }
              }
            },
            onError: (Object error, StackTrace stackTrace) {},
            onDone: () {},
            cancelOnError: true,
          );

      await _postJson(
        _buildRestUri(
          base,
          '/session/$remoteSessionId/message',
          queryParameters: <String, String>{
            'directory': request.workingDirectory,
          },
        ),
        body: <String, dynamic>{
          'agent': 'build',
          'parts': <Map<String, dynamic>>[
            <String, dynamic>{'type': 'text', 'text': request.prompt},
          ],
        },
        gatewayToken: request.gatewayToken,
      );
      unawaited(
        _pollRestAssistantMessage(
          base,
          remoteSessionId: remoteSessionId,
          workingDirectory: request.workingDirectory,
          gatewayToken: request.gatewayToken,
          onResolved: (text) {
            if (text.trim().isNotEmpty) {
              lastAssistantText = text;
              if (output.toString().trim().isEmpty) {
                output.write(text);
                request.onOutput?.call(text);
              }
              completeSuccess();
            }
          },
          onError: completeFailure,
        ),
      );

      return await completion.future.timeout(
        const Duration(minutes: 10),
        onTimeout: () => DirectSingleAgentRunResult(
          success: false,
          output: output.toString(),
          errorMessage: 'OpenCode REST request timed out.',
          aborted: _abortedSessions.contains(normalizedSessionId),
          resolvedModel: request.model,
          resolvedWorkingDirectory: request.workingDirectory,
          resolvedWorkspaceRefKind: workspaceRefKind,
        ),
      );
    } catch (error) {
      return DirectSingleAgentRunResult(
        success: false,
        output: output.toString(),
        errorMessage: error.toString(),
        aborted: _abortedSessions.contains(normalizedSessionId),
        resolvedModel: request.model,
        resolvedWorkingDirectory: request.workingDirectory,
        resolvedWorkspaceRefKind: workspaceRefKind,
      );
    } finally {
      unawaited(lineSubscription?.cancel());
      eventClient.close(force: true);
      _abortedSessions.remove(normalizedSessionId);
    }
  }

  Future<void> abort(
    String sessionId, {
    required List<Uri> candidateBases,
  }) async {
    final normalizedSessionId = sessionId.trim();
    if (normalizedSessionId.isEmpty) {
      return;
    }
    _abortedSessions.add(normalizedSessionId);
    final restSessionId = _restSessionIds[normalizedSessionId]?.trim() ?? '';
    if (restSessionId.isEmpty) {
      return;
    }
    for (final base in candidateBases) {
      try {
        await _postJson(
          _buildRestUri(base, '/session/$restSessionId/abort'),
          body: null,
          gatewayToken: '',
        );
      } catch (_) {
        // Best effort only.
      }
      break;
    }
  }

  Future<String> _ensureRestSession(
    Uri base, {
    required String sessionId,
    required String workingDirectory,
    required String gatewayToken,
  }) async {
    final normalizedWorkingDirectory = workingDirectory.trim();
    final existing = _restSessionIds[sessionId]?.trim() ?? '';
    if (existing.isNotEmpty) {
      final existingWorkingDirectory =
          _restSessionWorkingDirectories[sessionId]?.trim() ?? '';
      final canReuseExistingSession =
          normalizedWorkingDirectory.isEmpty ||
          (existingWorkingDirectory.isNotEmpty &&
              existingWorkingDirectory == normalizedWorkingDirectory);
      if (canReuseExistingSession) {
        return existing;
      }
      _restSessionIds.remove(sessionId);
      _restSessionWorkingDirectories.remove(sessionId);
    }
    final created = await _postJson(
      _buildRestUri(
        base,
        '/session',
        queryParameters: <String, String>{
          'directory': normalizedWorkingDirectory,
        },
      ),
      body: <String, dynamic>{'title': sessionId},
      gatewayToken: gatewayToken,
    );
    final createdId = created['id']?.toString().trim() ?? '';
    if (createdId.isEmpty) {
      throw StateError('OpenCode REST endpoint returned an empty session id.');
    }
    _restSessionIds[sessionId] = createdId;
    if (normalizedWorkingDirectory.isNotEmpty) {
      _restSessionWorkingDirectories[sessionId] = normalizedWorkingDirectory;
    }
    return createdId;
  }

  Future<void> _pollRestAssistantMessage(
    Uri base, {
    required String remoteSessionId,
    required String workingDirectory,
    required String gatewayToken,
    required void Function(String text) onResolved,
    required void Function(String message) onError,
  }) async {
    String? previousText;
    var stableCount = 0;
    for (var attempt = 0; attempt < 100; attempt++) {
      try {
        final items = await _fetchJsonList(
          _buildRestUri(
            base,
            '/session/$remoteSessionId/message',
            queryParameters: <String, String>{
              'directory': workingDirectory,
              'limit': '20',
            },
          ),
          gatewayToken: gatewayToken,
        );
        final text = _latestAssistantTextFromRestMessages(items);
        if (text.trim().isNotEmpty) {
          if (text == previousText) {
            stableCount += 1;
          } else {
            previousText = text;
            stableCount = 1;
          }
          if (stableCount >= 2) {
            onResolved(text);
            return;
          }
        }
      } catch (error) {
        onError(error.toString());
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    onError('OpenCode REST session completed without assistant content.');
  }

  String _latestAssistantTextFromRestMessages(List<Object?> items) {
    for (final raw in items.reversed) {
      final item = _asMap(raw);
      final info = _asMap(item['info']);
      if (info['role']?.toString().trim() != 'assistant') {
        continue;
      }
      final parts = item['parts'];
      if (parts is! List) {
        continue;
      }
      for (final rawPart in parts) {
        final part = _asMap(rawPart);
        if (part['type']?.toString().trim() == 'text') {
          final text = part['text']?.toString() ?? '';
          if (text.trim().isNotEmpty) {
            return text;
          }
        }
      }
    }
    return '';
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

