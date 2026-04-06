@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/runtime/go_task_service_client.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';

void main() {
  test(
    'AppController completes the minimal assistant flow against a gateway',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final gateway = await _FakeGatewayServer.start();
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-assistant-flow-',
      );
      addTearDown(() async {
        await _deleteDirectoryWithRetry(tempDirectory);
      });
      final store = SecureConfigStore(
        enableSecureStorage: false,
        databasePathResolver: () async => '${tempDirectory.path}/settings.db',
        fallbackDirectoryPathResolver: () async => tempDirectory.path,
      );
      final goTaskServiceClient = _FakeGoTaskServiceClient(
        onExecute: gateway.recordGoCoreTurn,
      );
      final controller = AppController(
        store: store,
        goTaskServiceClient: goTaskServiceClient,
      );
      addTearDown(() async {
        controller.dispose();
      });
      addTearDown(gateway.close);

      await _waitFor(() => !controller.initializing);
      await controller.saveSettings(
        controller.settings.copyWith(workspacePath: tempDirectory.path),
        refreshAfterSave: false,
      );

      await controller.connectManual(
        host: '127.0.0.1',
        port: gateway.port,
        tls: false,
        mode: RuntimeConnectionMode.local,
        token: _FakeGatewayServer.sharedToken,
      );

      expect(controller.connection.status, RuntimeConnectionStatus.connected);
      expect(gateway.connectAuthToken, _FakeGatewayServer.sharedToken);
      await controller.selectAgent('main');

      await controller.sendChatMessage('请只回复一行：XWORKMATE_OK', thinking: 'low');
      await _waitFor(
        () => controller.chatMessages.any(
          (message) =>
              message.role == 'assistant' &&
              message.text.contains('XWORKMATE_OK'),
        ),
      );

      expect(
        controller.chatMessages.any(
          (message) =>
              message.role == 'assistant' &&
              message.text.contains('XWORKMATE_OK'),
        ),
        isTrue,
      );
      expect(goTaskServiceClient.lastRequest?.agentId, 'main');
      expect(
        ((goTaskServiceClient.lastRequest?.metadata as Map?)?['node']
            as Map?)?['kind'],
        'app-mediated-cooperative-node',
      );
      expect(
        ((goTaskServiceClient.lastRequest?.metadata as Map?)?['dispatch']
            as Map?)?['mode'],
        'gateway-only',
      );
      expect(
        goTaskServiceClient.lastRequest?.routing?.mode,
        ExternalCodeAgentAcpRoutingMode.auto,
      );
      expect(
        goTaskServiceClient.lastRequest?.routing?.preferredGatewayTarget,
        'local',
      );
    },
  );

  test(
    'AppController marks explicit execution selections as explicit routing context',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-explicit-routing-',
      );
      addTearDown(() async {
        await _deleteDirectoryWithRetry(tempDirectory);
      });
      final store = SecureConfigStore(
        enableSecureStorage: false,
        databasePathResolver: () async => '${tempDirectory.path}/settings.db',
        fallbackDirectoryPathResolver: () async => tempDirectory.path,
      );
      final goTaskServiceClient = _FakeGoTaskServiceClient();
      final controller = AppController(
        store: store,
        goTaskServiceClient: goTaskServiceClient,
      );
      addTearDown(controller.dispose);

      await _waitFor(() => !controller.initializing);
      await controller.saveSettings(
        controller.settings.copyWith(workspacePath: tempDirectory.path),
        refreshAfterSave: false,
      );
      await controller.setAssistantExecutionTarget(
        AssistantExecutionTarget.singleAgent,
      );
      await controller.setSingleAgentProvider(SingleAgentProvider.opencode);
      if (controller.assistantModelChoices.isNotEmpty) {
        await controller.selectAssistantModel(
          controller.assistantModelChoices.first,
        );
      }

      await controller.sendChatMessage('只回复 EXPLICIT_OK', thinking: 'low');

      expect(
        goTaskServiceClient.lastRequest?.routing?.mode,
        ExternalCodeAgentAcpRoutingMode.explicit,
      );
      expect(
        goTaskServiceClient.lastRequest?.routing?.explicitExecutionTarget,
        'singleAgent',
      );
      expect(
        goTaskServiceClient.lastRequest?.routing?.explicitProviderId,
        'opencode',
      );
    },
  );

  test(
    'AppController connects directly from a setup code and persists gateway auth',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final gateway = await _FakeGatewayServer.start();
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-setup-code-flow-',
      );
      addTearDown(() async {
        await _deleteDirectoryWithRetry(tempDirectory);
      });
      final store = SecureConfigStore(
        enableSecureStorage: false,
        databasePathResolver: () async => '${tempDirectory.path}/settings.db',
        fallbackDirectoryPathResolver: () async => tempDirectory.path,
      );
      final controller = AppController(
        store: store,
        goTaskServiceClient: _FakeGoTaskServiceClient(
          onExecute: gateway.recordGoCoreTurn,
        ),
      );
      addTearDown(() async {
        controller.dispose();
      });
      addTearDown(gateway.close);

      await _waitFor(() => !controller.initializing);

      final setupCode = jsonEncode(<String, Object?>{
        'url': 'ws://127.0.0.1:${gateway.port}',
        'token': _FakeGatewayServer.sharedToken,
      });

      await controller.connectWithSetupCode(setupCode: setupCode);

      expect(controller.connection.status, RuntimeConnectionStatus.connected);
      expect(controller.connection.mode, RuntimeConnectionMode.local);
      expect(gateway.connectAuthToken, _FakeGatewayServer.sharedToken);
      expect(controller.settings.primaryLocalGatewayProfile.host, '127.0.0.1');
      expect(controller.settings.primaryLocalGatewayProfile.port, gateway.port);
      expect(
        await controller.settingsController.loadGatewayToken(
          profileIndex: kGatewayLocalProfileIndex,
        ),
        _FakeGatewayServer.sharedToken,
      );
    },
  );

  test(
    'AppController keeps the thread transcript after switching the thread to single-agent',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final gateway = await _FakeGatewayServer.start();
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-single-agent-history-hide-',
      );
      addTearDown(() async {
        await _deleteDirectoryWithRetry(tempDirectory);
      });
      final store = SecureConfigStore(
        enableSecureStorage: false,
        databasePathResolver: () async => '${tempDirectory.path}/settings.db',
        fallbackDirectoryPathResolver: () async => tempDirectory.path,
      );
      final controller = AppController(
        store: store,
        goTaskServiceClient: _FakeGoTaskServiceClient(
          onExecute: gateway.recordGoCoreTurn,
        ),
      );
      addTearDown(controller.dispose);
      addTearDown(gateway.close);

      await _waitFor(() => !controller.initializing);
      await controller.saveSettings(
        controller.settings.copyWith(workspacePath: tempDirectory.path),
        refreshAfterSave: false,
      );

      await controller.connectManual(
        host: '127.0.0.1',
        port: gateway.port,
        tls: false,
        mode: RuntimeConnectionMode.local,
        token: _FakeGatewayServer.sharedToken,
      );
      await controller.selectAgent('main');
      await controller.sendChatMessage('请只回复一行：XWORKMATE_OK', thinking: 'low');
      await _waitFor(
        () => controller.chatMessages.any(
          (message) =>
              message.role == 'assistant' &&
              message.text.contains('XWORKMATE_OK'),
        ),
      );

      await controller.setAssistantExecutionTarget(
        AssistantExecutionTarget.singleAgent,
      );

      expect(
        controller.assistantExecutionTarget,
        AssistantExecutionTarget.singleAgent,
      );
      expect(
        controller.chatMessages.any(
          (message) => message.text.contains('XWORKMATE_OK'),
        ),
        isTrue,
      );
    },
  );
}

class _FakeGatewayServer {
  _FakeGatewayServer._(this._server);

  static const sharedToken = 'shared-token-from-test';

  final HttpServer _server;
  WebSocket? _socket;
  String? connectAuthToken;
  Map<String, dynamic>? lastChatSendParams;
  final List<Map<String, dynamic>> _history = <Map<String, dynamic>>[];
  String _lastMessagePreview = '';
  double _updatedAtMs = DateTime.now().millisecondsSinceEpoch.toDouble();

  int get port => _server.port;

  static Future<_FakeGatewayServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = _FakeGatewayServer._(server);
    unawaited(fake._serve());
    return fake;
  }

  Future<void> close() async {
    await _socket?.close();
    await _server.close(force: true);
  }

  Future<void> _serve() async {
    await for (final request in _server) {
      if (request.uri.path == '/acp/rpc' && request.method == 'POST') {
        await _serveAcpRpc(request);
        continue;
      }
      if (request.uri.path == '/acp' &&
          WebSocketTransformer.isUpgradeRequest(request)) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        continue;
      }
      if (!WebSocketTransformer.isUpgradeRequest(request)) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        continue;
      }
      final socket = await WebSocketTransformer.upgrade(request);
      _socket = socket;
      _send(socket, <String, dynamic>{
        'type': 'event',
        'event': 'connect.challenge',
        'payload': <String, dynamic>{'nonce': 'nonce-1'},
      });

      await for (final raw in socket) {
        final frame = jsonDecode(raw as String) as Map<String, dynamic>;
        if (frame['type'] != 'req') {
          continue;
        }
        final method = frame['method'] as String? ?? '';
        final id = frame['id'] as String? ?? 'unknown';
        final params =
            (frame['params'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
        switch (method) {
          case 'connect':
            connectAuthToken = ((params['auth'] as Map?)?['token'] as String?)
                ?.trim();
            _send(socket, <String, dynamic>{
              'type': 'res',
              'id': id,
              'ok': true,
              'payload': <String, dynamic>{
                'server': <String, dynamic>{'host': '127.0.0.1'},
                'snapshot': <String, dynamic>{
                  'sessionDefaults': <String, dynamic>{
                    'mainSessionKey': 'agent:main:main',
                  },
                },
              },
            });
            break;
          case 'health':
          case 'status':
            _send(socket, <String, dynamic>{
              'type': 'res',
              'id': id,
              'ok': true,
              'payload': <String, dynamic>{'ok': true},
            });
            break;
          case 'agents.list':
            _send(socket, <String, dynamic>{
              'type': 'res',
              'id': id,
              'ok': true,
              'payload': <String, dynamic>{
                'agents': <Map<String, dynamic>>[
                  <String, dynamic>{'id': 'main', 'name': 'Main'},
                ],
                'mainKey': 'main',
              },
            });
            break;
          case 'sessions.list':
            _send(socket, <String, dynamic>{
              'type': 'res',
              'id': id,
              'ok': true,
              'payload': <String, dynamic>{
                'sessions': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'key': 'agent:main:main',
                    'displayName': 'main',
                    'surface': 'assistant',
                    'updatedAt': _updatedAtMs,
                    'derivedTitle': 'main',
                    'lastMessagePreview': _lastMessagePreview,
                    'sessionId': 'sess-main',
                  },
                ],
              },
            });
            break;
          case 'chat.history':
            _send(socket, <String, dynamic>{
              'type': 'res',
              'id': id,
              'ok': true,
              'payload': <String, dynamic>{'messages': _history},
            });
            break;
          case 'skills.status':
            _send(socket, <String, dynamic>{
              'type': 'res',
              'id': id,
              'ok': true,
              'payload': <String, dynamic>{'skills': const <Object>[]},
            });
            break;
          case 'channels.status':
            _send(socket, <String, dynamic>{
              'type': 'res',
              'id': id,
              'ok': true,
              'payload': <String, dynamic>{
                'channelMeta': const <Object>[],
                'channelLabels': const <String, dynamic>{},
                'channelDetailLabels': const <String, dynamic>{},
                'channelAccounts': const <String, dynamic>{},
                'channelOrder': const <Object>[],
              },
            });
            break;
          case 'models.list':
            _send(socket, <String, dynamic>{
              'type': 'res',
              'id': id,
              'ok': true,
              'payload': <String, dynamic>{
                'models': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'id': 'gpt-5.4',
                    'name': 'gpt-5.4',
                    'provider': 'test',
                  },
                ],
              },
            });
            break;
          case 'cron.list':
            _send(socket, <String, dynamic>{
              'type': 'res',
              'id': id,
              'ok': true,
              'payload': <String, dynamic>{'jobs': const <Object>[]},
            });
            break;
          case 'system-presence':
            _send(socket, <String, dynamic>{
              'type': 'res',
              'id': id,
              'ok': true,
              'payload': const <Object>[],
            });
            break;
          case 'chat.send':
            lastChatSendParams = params;
            final sessionKey =
                params['sessionKey'] as String? ?? 'agent:main:main';
            final runId = params['idempotencyKey'] as String? ?? 'run-1';
            final userText = params['message'] as String? ?? '';
            _appendMessage(role: 'user', text: userText);
            _send(socket, <String, dynamic>{
              'type': 'res',
              'id': id,
              'ok': true,
              'payload': <String, dynamic>{'runId': runId, 'status': 'started'},
            });
            unawaited(
              _emitAssistantResult(
                socket,
                runId: runId,
                sessionKey: sessionKey,
              ),
            );
            break;
          default:
            _send(socket, <String, dynamic>{
              'type': 'res',
              'id': id,
              'ok': true,
              'payload': const <String, dynamic>{},
            });
            break;
        }
      }
    }
  }

  Future<void> _serveAcpRpc(HttpRequest request) async {
    final body = await utf8.decodeStream(request);
    final envelope = (jsonDecode(body) as Map).cast<String, dynamic>();
    final id = envelope['id'];
    final method = envelope['method']?.toString() ?? '';
    final params =
        (envelope['params'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    request.response.headers.set(
      HttpHeaders.contentTypeHeader,
      'text/event-stream; charset=utf-8',
    );
    if (method == 'session.start' || method == 'session.message') {
      final payload = _startAcpSession(params);
      request.response.write(
        'data: ${jsonEncode(<String, dynamic>{'jsonrpc': '2.0', 'method': 'session.update', 'params': payload.notification})}\n\n',
      );
      request.response.write(
        'data: ${jsonEncode(<String, dynamic>{'jsonrpc': '2.0', 'id': id, 'result': payload.result})}\n\n',
      );
      await request.response.close();
      return;
    }
    final response = <String, dynamic>{
      'jsonrpc': '2.0',
      'id': id,
      'result': switch (method) {
        'acp.capabilities' => <String, dynamic>{
          'singleAgent': true,
          'multiAgent': true,
          'providers': <String>['claude', 'codex', 'gemini', 'opencode'],
          'capabilities': <String, dynamic>{
            'single_agent': true,
            'multi_agent': true,
            'providers': <String>['claude', 'codex', 'gemini', 'opencode'],
          },
        },
        'session.cancel' || 'session.close' => <String, dynamic>{'ok': true},
        _ => const <String, dynamic>{},
      },
    };
    request.response.write('data: ${jsonEncode(response)}\n\n');
    await request.response.close();
  }

  _AcpSessionPayload _startAcpSession(Map<String, dynamic> params) {
    lastChatSendParams = params;
    final sessionKey = params['sessionId']?.toString().trim().isNotEmpty == true
        ? params['sessionId'].toString().trim()
        : params['threadId']?.toString().trim() ?? 'agent:main:main';
    final prompt = params['taskPrompt']?.toString() ?? '';
    const reply = 'XWORKMATE_OK';
    _appendMessage(role: 'user', text: prompt);
    _appendMessage(role: 'assistant', text: reply);
    return _AcpSessionPayload(
      notification: <String, dynamic>{
        'sessionId': sessionKey,
        'threadId': sessionKey,
        'turnId': 'turn-1',
        'type': 'delta',
        'delta': reply,
        'message': '',
        'pending': true,
        'error': false,
      },
      result: <String, dynamic>{
        'success': true,
        'message': reply,
        'summary': reply,
        'turnId': 'turn-1',
      },
    );
  }

  Future<void> _emitAssistantResult(
    WebSocket socket, {
    required String runId,
    required String sessionKey,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    const reply = 'XWORKMATE_OK';
    _appendMessage(role: 'assistant', text: reply);
    _send(socket, <String, dynamic>{
      'type': 'event',
      'event': 'chat',
      'payload': <String, dynamic>{
        'runId': runId,
        'sessionKey': sessionKey,
        'state': 'delta',
        'message': <String, dynamic>{
          'role': 'assistant',
          'content': <Map<String, dynamic>>[
            <String, dynamic>{'type': 'text', 'text': reply},
          ],
          'timestamp': _updatedAtMs.toInt(),
        },
      },
    });
    _send(socket, <String, dynamic>{
      'type': 'event',
      'event': 'chat',
      'payload': <String, dynamic>{
        'runId': runId,
        'sessionKey': sessionKey,
        'state': 'final',
        'message': <String, dynamic>{
          'role': 'assistant',
          'content': <Map<String, dynamic>>[
            <String, dynamic>{'type': 'text', 'text': reply},
          ],
          'timestamp': _updatedAtMs.toInt(),
        },
      },
    });
  }

  void _appendMessage({required String role, required String text}) {
    _updatedAtMs = DateTime.now().millisecondsSinceEpoch.toDouble();
    _lastMessagePreview = text;
    _history.add(<String, dynamic>{
      'role': role,
      'content': <Map<String, dynamic>>[
        <String, dynamic>{'type': 'text', 'text': text},
      ],
      'timestamp': _updatedAtMs.toInt(),
    });
  }

  void _send(WebSocket socket, Map<String, dynamic> frame) {
    socket.add(jsonEncode(frame));
  }

  void recordGoCoreTurn(GoTaskServiceRequest request) {
    lastChatSendParams = request.toExternalAcpParams();
    final prompt = request.prompt.trim();
    if (prompt.isNotEmpty) {
      _appendMessage(role: 'user', text: prompt);
    }
    _appendMessage(role: 'assistant', text: 'XWORKMATE_OK');
  }
}

class _FakeGoTaskServiceClient implements GoTaskServiceClient {
  _FakeGoTaskServiceClient({this.onExecute});

  GoTaskServiceRequest? lastRequest;
  final void Function(GoTaskServiceRequest request)? onExecute;

  @override
  Future<void> syncExternalProviders(
    List<ExternalCodeAgentAcpSyncedProvider> providers,
  ) async {}

  @override
  Future<ExternalCodeAgentAcpCapabilities> loadExternalAcpCapabilities({
    required AssistantExecutionTarget target,
    bool forceRefresh = false,
  }) async {
    return ExternalCodeAgentAcpCapabilities(
      singleAgent: true,
      multiAgent: true,
      providers: <SingleAgentProvider>{
        SingleAgentProvider.codex,
        SingleAgentProvider.opencode,
      },
      raw: <String, dynamic>{},
    );
  }

  @override
  Future<GoTaskServiceResult> executeTask(
    GoTaskServiceRequest request, {
    required void Function(GoTaskServiceUpdate update) onUpdate,
  }) async {
    lastRequest = request;
    onExecute?.call(request);
    onUpdate(
      GoTaskServiceUpdate(
        sessionId: request.sessionId,
        threadId: request.threadId,
        turnId: 'turn-1',
        type: 'delta',
        text: 'XWORKMATE_OK',
        message: '',
        pending: false,
        error: false,
        route: request.route,
        payload: const <String, dynamic>{'type': 'delta'},
      ),
    );
    return GoTaskServiceResult(
      success: true,
      message: 'XWORKMATE_OK',
      turnId: 'turn-1',
      raw: <String, dynamic>{},
      errorMessage: '',
      resolvedModel: '',
      route: request.route,
    );
  }

  @override
  Future<void> cancelTask({
    required GoTaskServiceRoute route,
    required AssistantExecutionTarget target,
    required String sessionId,
    required String threadId,
  }) async {}

  @override
  Future<void> closeTask({
    required GoTaskServiceRoute route,
    required AssistantExecutionTarget target,
    required String sessionId,
    required String threadId,
  }) async {}

  @override
  Future<void> dispose() async {}
}

class _AcpSessionPayload {
  const _AcpSessionPayload({required this.notification, required this.result});

  final Map<String, dynamic> notification;
  final Map<String, dynamic> result;
}

Future<void> _deleteDirectoryWithRetry(Directory directory) async {
  if (!await directory.exists()) {
    return;
  }
  for (var attempt = 0; attempt < 3; attempt += 1) {
    try {
      await directory.delete(recursive: true);
      return;
    } on FileSystemException {
      if (attempt == 2) {
        rethrow;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
}

Future<void> _waitFor(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (predicate()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  throw TimeoutException('Condition not met before timeout.');
}
