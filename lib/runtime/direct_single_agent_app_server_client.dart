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
    this.resolvedModel = '',
  });

  final bool success;
  final String output;
  final String errorMessage;
  final bool aborted;
  final String resolvedModel;
}

class DirectSingleAgentRunRequest {
  const DirectSingleAgentRunRequest({
    required this.sessionId,
    required this.provider,
    required this.prompt,
    required this.model,
    required this.workingDirectory,
    required this.gatewayToken,
    this.selectedSkills = const <AssistantThreadSkillEntry>[],
    this.onOutput,
  });

  final String sessionId;
  final SingleAgentProvider provider;
  final String prompt;
  final String model;
  final String workingDirectory;
  final String gatewayToken;
  final List<AssistantThreadSkillEntry> selectedSkills;
  final void Function(String text)? onOutput;
}

enum DirectSingleAgentEndpointMode {
  wsLocal,
  wss,
  httpLocal,
  https,
  unsupported,
}

enum _DirectSingleAgentTransportKind { websocketAppServer, restSessionApi }

class DirectSingleAgentEndpointDescriptor {
  const DirectSingleAgentEndpointDescriptor({
    required this.mode,
    required this.baseUri,
    this.websocketUri,
  });

  final DirectSingleAgentEndpointMode mode;
  final Uri? baseUri;
  final Uri? websocketUri;

  bool get isSupported => mode != DirectSingleAgentEndpointMode.unsupported;

  bool get prefersWebSocket =>
      mode == DirectSingleAgentEndpointMode.wsLocal ||
      mode == DirectSingleAgentEndpointMode.wss;

  bool get allowsRest =>
      mode == DirectSingleAgentEndpointMode.httpLocal ||
      mode == DirectSingleAgentEndpointMode.https;

  static DirectSingleAgentEndpointDescriptor describe(Uri? endpoint) {
    if (endpoint == null) {
      return const DirectSingleAgentEndpointDescriptor(
        mode: DirectSingleAgentEndpointMode.unsupported,
        baseUri: null,
      );
    }
    final scheme = endpoint.scheme.toLowerCase();
    final normalizedBase = endpoint.replace(path: '', query: null, fragment: null);
    final isLocal = _isLocalHost(endpoint.host);
    if (scheme == 'ws' && isLocal) {
      return DirectSingleAgentEndpointDescriptor(
        mode: DirectSingleAgentEndpointMode.wsLocal,
        baseUri: normalizedBase,
        websocketUri: normalizedBase,
      );
    }
    if (scheme == 'wss') {
      return DirectSingleAgentEndpointDescriptor(
        mode: DirectSingleAgentEndpointMode.wss,
        baseUri: normalizedBase,
        websocketUri: normalizedBase,
      );
    }
    if (scheme == 'http' && isLocal) {
      return DirectSingleAgentEndpointDescriptor(
        mode: DirectSingleAgentEndpointMode.httpLocal,
        baseUri: normalizedBase,
        websocketUri: normalizedBase.replace(scheme: 'ws'),
      );
    }
    if (scheme == 'https') {
      return DirectSingleAgentEndpointDescriptor(
        mode: DirectSingleAgentEndpointMode.https,
        baseUri: normalizedBase,
        websocketUri: normalizedBase.replace(scheme: 'wss'),
      );
    }
    return DirectSingleAgentEndpointDescriptor(
      mode: DirectSingleAgentEndpointMode.unsupported,
      baseUri: normalizedBase,
    );
  }
}

class DirectSingleAgentAppServerClient {
  DirectSingleAgentAppServerClient({required this.endpointResolver});

  final Uri? Function(SingleAgentProvider provider) endpointResolver;
  final _DirectSingleAgentWebSocketTransport _webSocketTransport =
      _DirectSingleAgentWebSocketTransport();
  final _DirectSingleAgentRestTransport _restTransport =
      _DirectSingleAgentRestTransport();

  final Map<SingleAgentProvider, DirectSingleAgentCapabilities>
  _cachedCapabilities = <SingleAgentProvider, DirectSingleAgentCapabilities>{};
  final Map<SingleAgentProvider, DateTime> _capabilitiesRefreshedAt =
      <SingleAgentProvider, DateTime>{};
  final Map<SingleAgentProvider, _DirectSingleAgentTransportKind>
  _transportKinds = <SingleAgentProvider, _DirectSingleAgentTransportKind>{};

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

    final descriptor = _describeEndpoint(provider);
    if (!descriptor.isSupported || descriptor.baseUri == null) {
      final unavailable = const DirectSingleAgentCapabilities.unavailable(
        endpoint: '',
        errorMessage: 'Single-agent app-server endpoint is not configured.',
      );
      _cachedCapabilities[provider] = unavailable;
      _capabilitiesRefreshedAt[provider] = DateTime.now();
      return unavailable;
    }

    try {
      final transport = await _resolveTransport(
        provider,
        descriptor: descriptor,
        gatewayToken: gatewayToken,
      );
      _transportKinds[provider] = transport.kind;
      _cachedCapabilities[provider] = DirectSingleAgentCapabilities(
        available: true,
        supportedProviders: <SingleAgentProvider>[provider],
        endpoint: transport.endpoint.toString(),
      );
    } catch (error) {
      _cachedCapabilities[provider] = DirectSingleAgentCapabilities.unavailable(
        endpoint: descriptor.baseUri.toString(),
        errorMessage: error.toString(),
      );
      _transportKinds.remove(provider);
    } finally {
      _capabilitiesRefreshedAt[provider] = DateTime.now();
    }

    return _cachedCapabilities[provider]!;
  }

  Future<DirectSingleAgentRunResult> run(
    DirectSingleAgentRunRequest request,
  ) async {
    final descriptor = _describeEndpoint(request.provider);
    if (!descriptor.isSupported || descriptor.baseUri == null) {
      return const DirectSingleAgentRunResult(
        success: false,
        output: '',
        errorMessage: 'Single-agent app-server endpoint is missing.',
      );
    }
    late final _ResolvedSingleAgentTransport transport;
    try {
      transport = await _resolveTransport(
        request.provider,
        descriptor: descriptor,
        gatewayToken: request.gatewayToken,
      );
    } catch (error) {
      return DirectSingleAgentRunResult(
        success: false,
        output: '',
        errorMessage: error.toString(),
      );
    }
    if (transport.kind == _DirectSingleAgentTransportKind.restSessionApi) {
      return transport.rest!.run(request, base: transport.endpoint);
    }
    return transport.websocket!.run(request, endpoint: transport.endpoint);
  }

  Future<void> abort(String sessionId) async {
    await _restTransport.abort(
      sessionId,
      candidateBases: <Uri>[
        for (final entry in _transportKinds.entries)
          if (entry.value == _DirectSingleAgentTransportKind.restSessionApi)
            ...[
              if (_describeEndpoint(entry.key).baseUri != null)
                _describeEndpoint(entry.key).baseUri!,
            ],
      ],
    );
    await _webSocketTransport.abort(sessionId);
  }

  Future<void> dispose() async {
    await _webSocketTransport.dispose();
  }

  DirectSingleAgentEndpointDescriptor _describeEndpoint(
    SingleAgentProvider provider,
  ) {
    return DirectSingleAgentEndpointDescriptor.describe(endpointResolver(provider));
  }

  Future<_ResolvedSingleAgentTransport> _resolveTransport(
    SingleAgentProvider provider, {
    required DirectSingleAgentEndpointDescriptor descriptor,
    required String gatewayToken,
  }) async {
    final cachedKind = _transportKinds[provider];
    if (cachedKind != null) {
      final cachedEndpoint = cachedKind ==
              _DirectSingleAgentTransportKind.websocketAppServer
          ? descriptor.websocketUri
          : descriptor.baseUri;
      if (cachedEndpoint != null) {
        return _ResolvedSingleAgentTransport(
          kind: cachedKind,
          endpoint: cachedEndpoint,
          websocket: cachedKind ==
                  _DirectSingleAgentTransportKind.websocketAppServer
              ? _webSocketTransport
              : null,
          rest: cachedKind == _DirectSingleAgentTransportKind.restSessionApi
              ? _restTransport
              : null,
        );
      }
    }

    if (descriptor.prefersWebSocket) {
      final endpoint = descriptor.websocketUri;
      if (endpoint == null) {
        throw StateError('Single-agent websocket endpoint is not configured.');
      }
      await _webSocketTransport.probe(endpoint, gatewayToken: gatewayToken);
      return _ResolvedSingleAgentTransport(
        kind: _DirectSingleAgentTransportKind.websocketAppServer,
        endpoint: endpoint,
        websocket: _webSocketTransport,
      );
    }

    if (descriptor.allowsRest) {
      final base = descriptor.baseUri;
      if (base == null) {
        throw StateError('Single-agent endpoint is not configured.');
      }
      try {
        await _restTransport.probe(base, gatewayToken: gatewayToken);
        return _ResolvedSingleAgentTransport(
          kind: _DirectSingleAgentTransportKind.restSessionApi,
          endpoint: base,
          rest: _restTransport,
        );
      } catch (_) {
        final websocket = descriptor.websocketUri;
        if (websocket == null) {
          rethrow;
        }
        await _webSocketTransport.probe(websocket, gatewayToken: gatewayToken);
        return _ResolvedSingleAgentTransport(
          kind: _DirectSingleAgentTransportKind.websocketAppServer,
          endpoint: websocket,
          websocket: _webSocketTransport,
        );
      }
    }

    throw StateError(
      'Single-agent endpoint mode ${descriptor.mode.name} is not supported.',
    );
  }
}

class _ResolvedSingleAgentTransport {
  const _ResolvedSingleAgentTransport({
    required this.kind,
    required this.endpoint,
    this.websocket,
    this.rest,
  });

  final _DirectSingleAgentTransportKind kind;
  final Uri endpoint;
  final _DirectSingleAgentWebSocketTransport? websocket;
  final _DirectSingleAgentRestTransport? rest;
}

class _DirectSingleAgentWebSocketTransport {
  final Map<String, _DirectAppServerConnection> _activeConnections =
      <String, _DirectAppServerConnection>{};
  final Map<String, String> _threadIds = <String, String>{};
  final Set<String> _abortedSessions = <String>{};

  Future<void> probe(
    Uri endpoint, {
    required String gatewayToken,
  }) async {
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
      final threadId = await _ensureThread(
        connection,
        sessionId: normalizedSessionId,
        workingDirectory: request.workingDirectory,
        model: request.model,
      );

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
        final resumedId = _extractThreadId(resumed) ?? existingThreadId;
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
    final threadId = _extractThreadId(created) ?? '';
    if (threadId.isEmpty) {
      throw StateError('Single-agent app-server returned an empty thread id.');
    }
    _threadIds[sessionId] = threadId;
    return threadId;
  }
}

class _DirectSingleAgentRestTransport {
  final Map<String, String> _restSessionIds = <String, String>{};
  final Set<String> _abortedSessions = <String>{};

  Future<void> probe(
    Uri base, {
    required String gatewayToken,
  }) async {
    await _fetchJson(
      _buildRestUri(base, '/global/health'),
      gatewayToken: gatewayToken,
    );
  }

  Future<DirectSingleAgentRunResult> run(
    DirectSingleAgentRunRequest request, {
    required Uri base,
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
      completion.complete(
        DirectSingleAgentRunResult(
          success: true,
          output: resolvedOutput,
          errorMessage: '',
          resolvedModel: request.model,
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
                completion.complete(
                  DirectSingleAgentRunResult(
                    success: false,
                    output: output.toString(),
                    errorMessage:
                        error['message']?.toString() ??
                        error['name']?.toString() ??
                        'OpenCode session failed.',
                    aborted: _abortedSessions.contains(normalizedSessionId),
                    resolvedModel: request.model,
                  ),
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
                  final delta = properties['text']?.toString() ??
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
          onError: (message) {
            if (!completion.isCompleted) {
              completion.complete(
                DirectSingleAgentRunResult(
                  success: false,
                  output: output.toString(),
                  errorMessage: message,
                  aborted: _abortedSessions.contains(normalizedSessionId),
                  resolvedModel: request.model,
                ),
              );
            }
          },
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
        ),
      );
    } catch (error) {
      return DirectSingleAgentRunResult(
        success: false,
        output: output.toString(),
        errorMessage: error.toString(),
        aborted: _abortedSessions.contains(normalizedSessionId),
        resolvedModel: request.model,
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
    final existing = _restSessionIds[sessionId]?.trim() ?? '';
    if (existing.isNotEmpty) {
      return existing;
    }
    final created = await _postJson(
      _buildRestUri(
        base,
        '/session',
        queryParameters: <String, String>{'directory': workingDirectory},
      ),
      body: <String, dynamic>{'title': sessionId},
      gatewayToken: gatewayToken,
    );
    final createdId = created['id']?.toString().trim() ?? '';
    if (createdId.isEmpty) {
      throw StateError('OpenCode REST endpoint returned an empty session id.');
    }
    _restSessionIds[sessionId] = createdId;
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

Uri _buildRestUri(
  Uri base,
  String path, {
  Map<String, String>? queryParameters,
}) {
  final normalizedPath = path.startsWith('/') ? path : '/$path';
  return base.replace(
    path: normalizedPath,
    queryParameters: queryParameters,
    fragment: null,
  );
}

Future<Map<String, dynamic>> _fetchJson(
  Uri uri, {
  required String gatewayToken,
}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final request = await client.getUrl(uri);
    final normalizedToken = gatewayToken.trim();
    if (normalizedToken.isNotEmpty) {
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $normalizedToken',
      );
    }
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    return _decodeMap(body);
  } finally {
    client.close(force: true);
  }
}

Future<Map<String, dynamic>> _postJson(
  Uri uri, {
  required Object? body,
  required String gatewayToken,
}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final request = await client.postUrl(uri);
    request.headers.set(
      HttpHeaders.contentTypeHeader,
      'application/json; charset=utf-8',
    );
    final normalizedToken = gatewayToken.trim();
    if (normalizedToken.isNotEmpty) {
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $normalizedToken',
      );
    }
    if (body != null) {
      request.add(utf8.encode(jsonEncode(body)));
    }
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    if (text.trim().isEmpty) {
      return const <String, dynamic>{};
    }
    return _decodeMap(text);
  } finally {
    client.close(force: true);
  }
}

Future<List<Object?>> _fetchJsonList(
  Uri uri, {
  required String gatewayToken,
}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final request = await client.getUrl(uri);
    final normalizedToken = gatewayToken.trim();
    if (normalizedToken.isNotEmpty) {
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $normalizedToken',
      );
    }
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    final decoded = jsonDecode(body);
    if (decoded is List<Object?>) {
      return decoded;
    }
    if (decoded is List) {
      return decoded.cast<Object?>();
    }
    return const <Object?>[];
  } finally {
    client.close(force: true);
  }
}

String? _extractThreadId(Map<String, dynamic> payload) {
  final topLevelId = payload['id']?.toString().trim() ?? '';
  if (topLevelId.isNotEmpty) {
    return topLevelId;
  }
  final thread = _asMap(payload['thread']);
  final nestedId = thread['id']?.toString().trim() ?? '';
  if (nestedId.isNotEmpty) {
    return nestedId;
  }
  return null;
}

String? _extractModel(Map<String, dynamic> payload) {
  final model = payload['model']?.toString().trim() ?? '';
  if (model.isNotEmpty) {
    return model;
  }
  return null;
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

bool _isLocalHost(String host) {
  final normalized = host.trim().toLowerCase();
  if (normalized.isEmpty ||
      normalized == 'localhost' ||
      normalized == '127.0.0.1' ||
      normalized == '::1') {
    return true;
  }
  final address = InternetAddress.tryParse(normalized);
  return address?.isLoopback ?? false;
}
