import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'multi_agent_orchestrator.dart';
import 'runtime_models.dart';

class MultiAgentBrokerServer {
  MultiAgentBrokerServer(this._orchestrator);

  final MultiAgentOrchestrator _orchestrator;
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
        if (method != 'run.start') {
          socket.add(
            jsonEncode(<String, dynamic>{
              'jsonrpc': '2.0',
              'id': id,
              'error': <String, dynamic>{
                'code': -32601,
                'message': 'Method not found',
              },
            }),
          );
          continue;
        }
        final params =
            (json['params'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
        final attachments =
            ((params['attachments'] as List?) ?? const <Object>[])
                .whereType<Map>()
                .map(
                  (item) => CollaborationAttachment(
                    name: item['name']?.toString() ?? '',
                    description: item['description']?.toString() ?? '',
                    path: item['path']?.toString() ?? '',
                  ),
                )
                .toList(growable: false);
        final result = await _orchestrator.runCollaboration(
          taskPrompt: params['taskPrompt'] as String? ?? '',
          workingDirectory: params['workingDirectory'] as String? ?? '',
          attachments: attachments,
          selectedSkills:
              ((params['selectedSkills'] as List?) ?? const <Object>[])
                  .map((item) => item.toString())
                  .toList(growable: false),
          aiGatewayBaseUrl: params['aiGatewayBaseUrl'] as String? ?? '',
          aiGatewayApiKey: params['aiGatewayApiKey'] as String? ?? '',
          onEvent: (event) {
            socket.add(
              jsonEncode(<String, dynamic>{
                'jsonrpc': '2.0',
                'method': 'multi_agent.event',
                'params': event.toJson(),
              }),
            );
          },
        );
        socket.add(
          jsonEncode(<String, dynamic>{
            'jsonrpc': '2.0',
            'id': id,
            'result': result.toJson(),
          }),
        );
      } catch (error) {
        socket.add(
          jsonEncode(<String, dynamic>{
            'jsonrpc': '2.0',
            'error': <String, dynamic>{
              'code': -32000,
              'message': error.toString(),
            },
          }),
        );
      }
    }
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
  }) async* {
    final socket = await WebSocket.connect(_uri.toString());
    final controller = StreamController<MultiAgentRunEvent>();
    final requestId = DateTime.now().microsecondsSinceEpoch.toString();

    socket.listen(
      (raw) {
        final json = jsonDecode(raw as String) as Map<String, dynamic>;
        final method = json['method'] as String?;
        if (method == 'multi_agent.event') {
          final params =
              (json['params'] as Map?)?.cast<String, dynamic>() ??
              const <String, dynamic>{};
          controller.add(MultiAgentRunEvent.fromJson(params));
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
        'method': 'run.start',
        'params': <String, dynamic>{
          'taskPrompt': taskPrompt,
          'workingDirectory': workingDirectory,
          'attachments': attachments
              .map(
                (item) => <String, dynamic>{
                  'name': item.name,
                  'description': item.description,
                  'path': item.path,
                },
              )
              .toList(growable: false),
          'selectedSkills': selectedSkills,
          'aiGatewayBaseUrl': aiGatewayBaseUrl,
          'aiGatewayApiKey': aiGatewayApiKey,
        },
      }),
    );

    yield* controller.stream;
  }
}
