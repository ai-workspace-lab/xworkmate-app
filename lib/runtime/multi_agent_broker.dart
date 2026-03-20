import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'multi_agent_orchestrator.dart';
import 'runtime_models.dart';

class MultiAgentBrokerServer {
  MultiAgentBrokerServer(this._orchestrator);

  final MultiAgentOrchestrator _orchestrator;
  final Map<String, _BrokerSessionState> _sessions =
      <String, _BrokerSessionState>{};
  HttpServer? _server;

  bool get isRunning => _server != null;

  Uri? get wsUri => _server == null
      ? null
      : Uri.parse('ws://127.0.0.1:${_server!.port}/multi-agent-broker');

  Future<void> start() async {
    if (_server != null) {
      return;
    }
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(_listen());
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    _sessions.clear();
    await server?.close(force: true);
  }

  Future<void> _listen() async {
    final server = _server;
    if (server == null) {
      return;
    }
    await for (final request in server) {
      if (request.uri.path != '/multi-agent-broker' ||
          !WebSocketTransformer.isUpgradeRequest(request)) {
        request.response
          ..statusCode = HttpStatus.notFound
          ..close();
        continue;
      }
      final socket = await WebSocketTransformer.upgrade(request);
      unawaited(_handleSocket(socket));
    }
  }

  Future<void> _handleSocket(WebSocket socket) async {
    await for (final raw in socket) {
      try {
        final json = jsonDecode(raw as String) as Map<String, dynamic>;
        final method = json['method'] as String? ?? '';
        final id = json['id'];
        final params =
            (json['params'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
        switch (method) {
          case 'run.start':
            await _handleRunStart(socket, id, params);
            break;
          case 'session.start':
            await _handleSessionStart(socket, id, params);
            break;
          case 'session.message':
            await _handleSessionMessage(socket, id, params);
            break;
          case 'session.cancel':
            await _orchestrator.abort();
            _writeResult(
              socket,
              id,
              <String, dynamic>{'accepted': true, 'cancelled': true},
            );
            break;
          case 'session.close':
            final sessionId = params['sessionId']?.toString().trim() ?? '';
            if (sessionId.isNotEmpty) {
              _sessions.remove(sessionId);
            }
            _writeResult(
              socket,
              id,
              <String, dynamic>{'accepted': true, 'closed': true},
            );
            break;
          default:
            _writeError(socket, id, -32601, 'Method not found');
        }
      } catch (error) {
        _writeError(socket, null, -32000, error.toString());
      }
    }
  }

  Future<void> _handleRunStart(
    WebSocket socket,
    Object? id,
    Map<String, dynamic> params,
  ) async {
    final result = await _orchestrator.runCollaboration(
      taskPrompt: params['taskPrompt'] as String? ?? '',
      workingDirectory: params['workingDirectory'] as String? ?? '',
      attachments: _parseAttachments(params['attachments']),
      selectedSkills: _parseSelectedSkills(params['selectedSkills']),
      aiGatewayBaseUrl: params['aiGatewayBaseUrl'] as String? ?? '',
      aiGatewayApiKey: params['aiGatewayApiKey'] as String? ?? '',
      onEvent: (event) => _emitEvent(socket, event),
    );
    _writeResult(socket, id, result.toJson());
  }

  Future<void> _handleSessionStart(
    WebSocket socket,
    Object? id,
    Map<String, dynamic> params,
  ) async {
    final sessionId = params['sessionId']?.toString().trim() ?? '';
    if (sessionId.isEmpty) {
      _writeError(socket, id, -32602, 'sessionId is required');
      return;
    }
    final state = _BrokerSessionState(
      sessionId: sessionId,
      workingDirectory: params['workingDirectory'] as String? ?? '',
      attachments: _parseAttachments(params['attachments']),
      selectedSkills: _parseSelectedSkills(params['selectedSkills']),
      aiGatewayBaseUrl: params['aiGatewayBaseUrl'] as String? ?? '',
      aiGatewayApiKey: params['aiGatewayApiKey'] as String? ?? '',
      history: <String>[],
    );
    _sessions[sessionId] = state;
    await _runSession(socket, id, state, params['taskPrompt'] as String? ?? '');
  }

  Future<void> _handleSessionMessage(
    WebSocket socket,
    Object? id,
    Map<String, dynamic> params,
  ) async {
    final sessionId = params['sessionId']?.toString().trim() ?? '';
    if (sessionId.isEmpty) {
      _writeError(socket, id, -32602, 'sessionId is required');
      return;
    }
    final state = _sessions.putIfAbsent(
      sessionId,
      () => _BrokerSessionState(
        sessionId: sessionId,
        workingDirectory: params['workingDirectory'] as String? ?? '',
        attachments: _parseAttachments(params['attachments']),
        selectedSkills: _parseSelectedSkills(params['selectedSkills']),
        aiGatewayBaseUrl: params['aiGatewayBaseUrl'] as String? ?? '',
        aiGatewayApiKey: params['aiGatewayApiKey'] as String? ?? '',
        history: <String>[],
      ),
    );
    final workingDirectory = params['workingDirectory'] as String? ?? '';
    if (workingDirectory.trim().isNotEmpty) {
      state.workingDirectory = workingDirectory;
    }
    final attachments = _parseAttachments(params['attachments']);
    if (attachments.isNotEmpty) {
      state.attachments = attachments;
    }
    final selectedSkills = _parseSelectedSkills(params['selectedSkills']);
    if (selectedSkills.isNotEmpty) {
      state.selectedSkills = selectedSkills;
    }
    final aiGatewayBaseUrl = params['aiGatewayBaseUrl'] as String? ?? '';
    if (aiGatewayBaseUrl.trim().isNotEmpty) {
      state.aiGatewayBaseUrl = aiGatewayBaseUrl;
    }
    final aiGatewayApiKey = params['aiGatewayApiKey'] as String? ?? '';
    if (aiGatewayApiKey.trim().isNotEmpty) {
      state.aiGatewayApiKey = aiGatewayApiKey;
    }
    await _runSession(socket, id, state, params['taskPrompt'] as String? ?? '');
  }

  Future<void> _runSession(
    WebSocket socket,
    Object? id,
    _BrokerSessionState state,
    String taskPrompt,
  ) async {
    final trimmedPrompt = taskPrompt.trim();
    if (trimmedPrompt.isNotEmpty) {
      state.history.add(trimmedPrompt);
    }
    final composedPrompt = _composeSessionPrompt(state.history);
    final result = await _orchestrator.runCollaboration(
      taskPrompt: composedPrompt,
      workingDirectory: state.workingDirectory,
      attachments: state.attachments,
      selectedSkills: state.selectedSkills,
      aiGatewayBaseUrl: state.aiGatewayBaseUrl,
      aiGatewayApiKey: state.aiGatewayApiKey,
      onEvent: (event) => _emitEvent(socket, event),
    );
    _writeResult(
      socket,
      id,
      <String, dynamic>{...result.toJson(), 'sessionId': state.sessionId},
    );
  }

  String _composeSessionPrompt(List<String> history) {
    if (history.isEmpty) {
      return '';
    }
    final buffer = StringBuffer();
    for (var index = 0; index < history.length; index++) {
      final turn = index + 1;
      buffer.writeln('## User Turn $turn');
      buffer.writeln(history[index]);
      buffer.writeln();
    }
    return buffer.toString().trim();
  }

  List<CollaborationAttachment> _parseAttachments(Object? raw) {
    return ((raw as List?) ?? const <Object>[])
        .whereType<Map>()
        .map(
          (item) => CollaborationAttachment(
            name: item['name']?.toString() ?? '',
            description: item['description']?.toString() ?? '',
            path: item['path']?.toString() ?? '',
          ),
        )
        .toList(growable: false);
  }

  List<String> _parseSelectedSkills(Object? raw) {
    return ((raw as List?) ?? const <Object>[])
        .map((item) => item.toString())
        .toList(growable: false);
  }

  void _emitEvent(WebSocket socket, MultiAgentRunEvent event) {
    socket.add(
      jsonEncode(<String, dynamic>{
        'jsonrpc': '2.0',
        'method': 'multi_agent.event',
        'params': event.toJson(),
      }),
    );
  }

  void _writeResult(WebSocket socket, Object? id, Map<String, dynamic> result) {
    socket.add(
      jsonEncode(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'result': result,
      }),
    );
  }

  void _writeError(
    WebSocket socket,
    Object? id,
    int code,
    String message,
  ) {
    socket.add(
      jsonEncode(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'error': <String, dynamic>{'code': code, 'message': message},
      }),
    );
  }
}

class MultiAgentBrokerClient {
  MultiAgentBrokerClient(this._uri);

  final Uri _uri;

  Stream<MultiAgentRunEvent> runTask({
    required String taskPrompt,
    required String workingDirectory,
    required List<CollaborationAttachment> attachments,
    required List<String> selectedSkills,
    required String aiGatewayBaseUrl,
    required String aiGatewayApiKey,
  }) {
    return _streamRequest(
      method: 'run.start',
      params: <String, dynamic>{
        'taskPrompt': taskPrompt,
        'workingDirectory': workingDirectory,
        'attachments': _encodeAttachments(attachments),
        'selectedSkills': selectedSkills,
        'aiGatewayBaseUrl': aiGatewayBaseUrl,
        'aiGatewayApiKey': aiGatewayApiKey,
      },
    );
  }

  Stream<MultiAgentRunEvent> startSession({
    required String sessionId,
    required String taskPrompt,
    required String workingDirectory,
    required List<CollaborationAttachment> attachments,
    required List<String> selectedSkills,
    required String aiGatewayBaseUrl,
    required String aiGatewayApiKey,
  }) {
    return _streamRequest(
      method: 'session.start',
      params: <String, dynamic>{
        'sessionId': sessionId,
        'taskPrompt': taskPrompt,
        'workingDirectory': workingDirectory,
        'attachments': _encodeAttachments(attachments),
        'selectedSkills': selectedSkills,
        'aiGatewayBaseUrl': aiGatewayBaseUrl,
        'aiGatewayApiKey': aiGatewayApiKey,
      },
    );
  }

  Stream<MultiAgentRunEvent> sendSessionMessage({
    required String sessionId,
    required String taskPrompt,
    required String workingDirectory,
    required List<CollaborationAttachment> attachments,
    required List<String> selectedSkills,
    required String aiGatewayBaseUrl,
    required String aiGatewayApiKey,
  }) {
    return _streamRequest(
      method: 'session.message',
      params: <String, dynamic>{
        'sessionId': sessionId,
        'taskPrompt': taskPrompt,
        'workingDirectory': workingDirectory,
        'attachments': _encodeAttachments(attachments),
        'selectedSkills': selectedSkills,
        'aiGatewayBaseUrl': aiGatewayBaseUrl,
        'aiGatewayApiKey': aiGatewayApiKey,
      },
    );
  }

  Future<void> cancelSession(String sessionId) async {
    await _requestOnly(
      method: 'session.cancel',
      params: <String, dynamic>{'sessionId': sessionId},
    );
  }

  Future<void> closeSession(String sessionId) async {
    await _requestOnly(
      method: 'session.close',
      params: <String, dynamic>{'sessionId': sessionId},
    );
  }

  Stream<MultiAgentRunEvent> _streamRequest({
    required String method,
    required Map<String, dynamic> params,
  }) async* {
    final socket = await WebSocket.connect(_uri.toString());
    final controller = StreamController<MultiAgentRunEvent>();
    final requestId = DateTime.now().microsecondsSinceEpoch.toString();

    socket.listen(
      (raw) {
        final json = jsonDecode(raw as String) as Map<String, dynamic>;
        final rpcMethod = json['method'] as String?;
        if (rpcMethod == 'multi_agent.event') {
          final eventParams =
              (json['params'] as Map?)?.cast<String, dynamic>() ??
              const <String, dynamic>{};
          controller.add(MultiAgentRunEvent.fromJson(eventParams));
          return;
        }
        if (json['id']?.toString() == requestId && json['result'] is Map) {
          final result = (json['result'] as Map).cast<String, dynamic>();
          controller.add(
            MultiAgentRunEvent(
              type: 'result',
              title: 'Multi-Agent',
              message: result['success'] == true
                  ? 'Collaboration completed.'
                  : 'Collaboration failed.',
              pending: false,
              error: result['success'] != true,
              data: result,
            ),
          );
          unawaited(controller.close());
          unawaited(socket.close());
          return;
        }
        if (json['error'] is Map) {
          final error = (json['error'] as Map).cast<String, dynamic>();
          controller.add(
            MultiAgentRunEvent(
              type: 'error',
              title: 'Multi-Agent',
              message: error['message']?.toString() ?? 'Broker error',
              pending: false,
              error: true,
            ),
          );
          unawaited(controller.close());
          unawaited(socket.close());
        }
      },
      onError: controller.addError,
      onDone: () {
        if (!controller.isClosed) {
          controller.close();
        }
      },
      cancelOnError: true,
    );

    socket.add(
      jsonEncode(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': requestId,
        'method': method,
        'params': params,
      }),
    );

    yield* controller.stream;
  }

  Future<void> _requestOnly({
    required String method,
    required Map<String, dynamic> params,
  }) async {
    await for (final _ in _streamRequest(method: method, params: params)) {
      return;
    }
  }

  List<Map<String, dynamic>> _encodeAttachments(
    List<CollaborationAttachment> attachments,
  ) {
    return attachments
        .map(
          (item) => <String, dynamic>{
            'name': item.name,
            'description': item.description,
            'path': item.path,
          },
        )
        .toList(growable: false);
  }
}

class _BrokerSessionState {
  _BrokerSessionState({
    required this.sessionId,
    required this.workingDirectory,
    required this.attachments,
    required this.selectedSkills,
    required this.aiGatewayBaseUrl,
    required this.aiGatewayApiKey,
    required this.history,
  });

  final String sessionId;
  String workingDirectory;
  List<CollaborationAttachment> attachments;
  List<String> selectedSkills;
  String aiGatewayBaseUrl;
  String aiGatewayApiKey;
  final List<String> history;
}
