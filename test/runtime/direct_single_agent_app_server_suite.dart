@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/direct_single_agent_app_server_client.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

void main() {
  group('DirectSingleAgentAppServerClient', () {
    test('classifies the four endpoint modes', () {
      expect(
        DirectSingleAgentEndpointDescriptor.describe(
          Uri.parse('ws://127.0.0.1:9001'),
        ).mode,
        DirectSingleAgentEndpointMode.wsLocal,
      );
      expect(
        DirectSingleAgentEndpointDescriptor.describe(
          Uri.parse('wss://agent.example.com'),
        ).mode,
        DirectSingleAgentEndpointMode.wss,
      );
      expect(
        DirectSingleAgentEndpointDescriptor.describe(
          Uri.parse('http://localhost:38992'),
        ).mode,
        DirectSingleAgentEndpointMode.httpLocal,
      );
      expect(
        DirectSingleAgentEndpointDescriptor.describe(
          Uri.parse('https://agent.example.com'),
        ).mode,
        DirectSingleAgentEndpointMode.https,
      );
    });

    test('probes websocket endpoint and reports codex support', () async {
      final server = await _FakeAppServer.start();
      addTearDown(server.close);

      final client = DirectSingleAgentAppServerClient(
        endpointResolver: (_) => server.baseHttpUri,
      );

      final capabilities = await client.loadCapabilities(
        provider: SingleAgentProvider.codex,
      );

      expect(capabilities.available, isTrue);
      expect(capabilities.supportsCodex, isTrue);
      expect(capabilities.endpoint, 'ws://127.0.0.1:${server.port}');
      expect(server.methods, contains('initialize'));
    });

    test('runs single-agent turns over direct websocket app-server', () async {
      final server = await _FakeAppServer.start();
      addTearDown(server.close);

      final client = DirectSingleAgentAppServerClient(
        endpointResolver: (_) => server.baseHttpUri,
      );
      addTearDown(client.dispose);

      final deltas = <String>[];
      final result = await client.run(
        const DirectSingleAgentRunRequest(
          sessionId: 'session-1',
          provider: SingleAgentProvider.codex,
          prompt: 'hello world',
          model: 'gpt-4.1',
          workingDirectory: '/tmp',
          gatewayToken: 'token-1',
        ).copyWith(onOutput: deltas.add),
      );

      expect(result.success, isTrue, reason: result.errorMessage);
      expect(result.output, 'hello world from app server');
      expect(result.resolvedModel, 'codex-sonnet');
      expect(server.lastTurnInput, <Object?>[
        <String, dynamic>{'type': 'text', 'text': 'hello world'},
      ]);
      expect(deltas.join(), 'hello world from app server');
      expect(
        server.methods,
        containsAll(<String>['initialize', 'thread/start', 'turn/start']),
      );
      expect(server.authorizationHeaders, contains('Bearer token-1'));
    });

    test('sends selected skills as structured app-server inputs', () async {
      final server = await _FakeAppServer.start();
      addTearDown(server.close);

      final client = DirectSingleAgentAppServerClient(
        endpointResolver: (_) => server.baseHttpUri,
      );
      addTearDown(client.dispose);

      final result = await client.run(
        DirectSingleAgentRunRequest(
          sessionId: 'session-skills',
          provider: SingleAgentProvider.codex,
          prompt: 'use the selected skills',
          model: 'gpt-4.1',
          workingDirectory: '/tmp',
          gatewayToken: '',
          selectedSkills: const <AssistantThreadSkillEntry>[
            AssistantThreadSkillEntry(
              key: '/tmp/ppt',
              label: 'PPT',
              description: 'Slides',
              source: 'codex',
              sourcePath: '/tmp/ppt/SKILL.md',
              scope: 'user',
              sourceLabel: 'codex · user · ppt',
            ),
            AssistantThreadSkillEntry(
              key: '/tmp/browser',
              label: 'Browser Automation',
              description: 'Browser',
              source: 'agents',
              sourcePath: '/tmp/browser/SKILL.md',
              scope: 'user',
              sourceLabel: 'agents · user · browser',
            ),
          ],
        ),
      );

      expect(result.success, isTrue);
      expect(server.lastTurnInput, <Object?>[
        <String, dynamic>{'type': 'text', 'text': 'use the selected skills'},
        <String, dynamic>{
          'type': 'skill',
          'name': 'PPT',
          'path': '/tmp/ppt/SKILL.md',
        },
        <String, dynamic>{
          'type': 'skill',
          'name': 'Browser Automation',
          'path': '/tmp/browser/SKILL.md',
        },
      ]);
    });

    test('interrupts active turns on abort', () async {
      final server = await _FakeAppServer.start(delayCompletion: true);
      addTearDown(server.close);

      final client = DirectSingleAgentAppServerClient(
        endpointResolver: (_) => server.baseHttpUri,
      );
      addTearDown(client.dispose);

      final runFuture = client.run(
        const DirectSingleAgentRunRequest(
          sessionId: 'session-abort',
          provider: SingleAgentProvider.codex,
          prompt: 'abort me',
          model: 'gpt-4.1',
          workingDirectory: '/tmp',
          gatewayToken: '',
        ),
      );

      await server.waitForMethod('turn/start');
      await client.abort('session-abort');
      final result = await runFuture;

      expect(result.aborted, isTrue);
      expect(server.methods, contains('turn/interrupt'));
    });

    test(
      'accepts nested thread objects returned by codex app-server',
      () async {
        final server = await _FakeAppServer.start(nestedThreadResult: true);
        addTearDown(server.close);

        final client = DirectSingleAgentAppServerClient(
          endpointResolver: (_) => server.baseHttpUri,
        );
        addTearDown(client.dispose);

        final result = await client.run(
          const DirectSingleAgentRunRequest(
            sessionId: 'session-nested',
            provider: SingleAgentProvider.codex,
            prompt: 'hello nested world',
            model: 'qwen2.5-coder:latest',
            workingDirectory: '/tmp',
            gatewayToken: '',
          ),
        );

        expect(result.success, isTrue);
        expect(result.output, 'hello world from app server');
        expect(result.resolvedModel, 'codex-sonnet');
      },
    );

    test('probes OpenCode REST endpoint and reports provider support', () async {
      final server = await _FakeOpenCodeRestServer.start();
      addTearDown(server.close);

      final client = DirectSingleAgentAppServerClient(
        endpointResolver: (_) => server.baseHttpUri,
      );

      final capabilities = await client.loadCapabilities(
        provider: SingleAgentProvider.opencode,
      );

      expect(capabilities.available, isTrue);
      expect(
        capabilities.supportsProvider(SingleAgentProvider.opencode),
        isTrue,
      );
      expect(server.healthRequested, isTrue);
    });

    test('runs OpenCode turns over REST session api', () async {
      final server = await _FakeOpenCodeRestServer.start();
      addTearDown(server.close);

      final client = DirectSingleAgentAppServerClient(
        endpointResolver: (_) => server.baseHttpUri,
      );
      addTearDown(client.dispose);

      final deltas = <String>[];
      final result = await client.run(
        const DirectSingleAgentRunRequest(
          sessionId: 'session-opencode',
          provider: SingleAgentProvider.opencode,
          prompt: 'hello opencode',
          model: '',
          workingDirectory: '/tmp',
          gatewayToken: '',
        ).copyWith(onOutput: deltas.add),
      );

      expect(result.success, isTrue);
      expect(result.output, 'hello world from opencode');
      expect(deltas.join(), 'hello world from opencode');
      expect(server.createdSessionCount, 1);
      expect(server.lastPromptText, 'hello opencode');
    });
  });
}

class _FakeAppServer {
  _FakeAppServer._(
    this._server, {
    required this.delayCompletion,
    required this.nestedThreadResult,
  });

  final HttpServer _server;
  final bool delayCompletion;
  final bool nestedThreadResult;
  final List<String> methods = <String>[];
  final List<String> authorizationHeaders = <String>[];
  final Map<String, Completer<void>> _methodWaiters =
      <String, Completer<void>>{};
  int _threadCounter = 0;
  List<Object?>? lastTurnInput;

  int get port => _server.port;
  Uri get baseHttpUri => Uri.parse('http://127.0.0.1:${_server.port}');

  static Future<_FakeAppServer> start({
    bool delayCompletion = false,
    bool nestedThreadResult = false,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = _FakeAppServer._(
      server,
      delayCompletion: delayCompletion,
      nestedThreadResult: nestedThreadResult,
    );
    unawaited(fake._listen());
    return fake;
  }

  Future<void> close() async {
    await _server.close(force: true);
  }

  Future<void> waitForMethod(String method) async {
    if (methods.contains(method)) {
      return;
    }
    final completer = _methodWaiters.putIfAbsent(method, Completer<void>.new);
    await completer.future.timeout(const Duration(seconds: 3));
  }

  Future<void> _listen() async {
    await for (final request in _server) {
      authorizationHeaders.add(
        request.headers.value(HttpHeaders.authorizationHeader) ?? '',
      );
      if (request.uri.path == '/' &&
          WebSocketTransformer.isUpgradeRequest(request)) {
        final socket = await WebSocketTransformer.upgrade(request);
        unawaited(_handleSocket(socket));
        continue;
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    }
  }

  Future<void> _handleSocket(WebSocket socket) async {
    await for (final raw in socket) {
      final message = _decodeMap(raw);
      final method = message['method']?.toString() ?? '';
      final id = message['id'];
      final params = _asMap(message['params']);
      if (method.isEmpty) {
        continue;
      }
      methods.add(method);
      _methodWaiters.remove(method)?.complete();
      switch (method) {
        case 'initialize':
          socket.add(
            jsonEncode(<String, dynamic>{
              'jsonrpc': '2.0',
              'id': id,
              'result': <String, dynamic>{
                'serverInfo': <String, dynamic>{'name': 'fake-codex'},
              },
            }),
          );
          break;
        case 'initialized':
          break;
        case 'thread/start':
          _threadCounter += 1;
          final result = nestedThreadResult
              ? <String, dynamic>{
                  'thread': <String, dynamic>{
                    'id': 'thread-$_threadCounter',
                    'path': params['cwd'] ?? '/tmp',
                    'ephemeral': false,
                  },
                }
              : <String, dynamic>{
                  'id': 'thread-$_threadCounter',
                  'path': params['cwd'] ?? '/tmp',
                  'ephemeral': false,
                };
          socket.add(
            jsonEncode(<String, dynamic>{
              'jsonrpc': '2.0',
              'id': id,
              'result': result,
            }),
          );
          break;
        case 'thread/resume':
          final result = nestedThreadResult
              ? <String, dynamic>{
                  'thread': <String, dynamic>{
                    'id': params['threadId'] ?? 'thread-resumed',
                    'path': params['cwd'] ?? '/tmp',
                    'ephemeral': false,
                  },
                }
              : <String, dynamic>{
                  'id': params['threadId'] ?? 'thread-resumed',
                  'path': params['cwd'] ?? '/tmp',
                  'ephemeral': false,
                };
          socket.add(
            jsonEncode(<String, dynamic>{
              'jsonrpc': '2.0',
              'id': id,
              'result': result,
            }),
          );
          break;
        case 'turn/start':
          final threadId = params['threadId']?.toString() ?? 'thread-1';
          if (params.containsKey('userInput')) {
            socket.add(
              jsonEncode(<String, dynamic>{
                'jsonrpc': '2.0',
                'id': id,
                'error': <String, dynamic>{
                  'code': -32600,
                  'message': 'Invalid request: missing field `input`',
                },
              }),
            );
            break;
          }
          final input = params['input'];
          if (input is! List) {
            socket.add(
              jsonEncode(<String, dynamic>{
                'jsonrpc': '2.0',
                'id': id,
                'error': <String, dynamic>{
                  'code': -32600,
                  'message':
                      'Invalid request: invalid type: expected a sequence',
                },
              }),
            );
            break;
          }
          lastTurnInput = List<Object?>.from(input);
          socket.add(
            jsonEncode(<String, dynamic>{
              'jsonrpc': '2.0',
              'id': id,
              'result': <String, dynamic>{
                'id': 'turn-1',
                'threadId': threadId,
                'status': 'started',
                'model': 'codex-sonnet',
              },
            }),
          );
          unawaited(_emitTurn(socket, threadId));
          break;
        case 'turn/interrupt':
          final threadId = params['threadId']?.toString() ?? 'thread-1';
          socket.add(
            jsonEncode(<String, dynamic>{
              'jsonrpc': '2.0',
              'id': id,
              'result': <String, dynamic>{'ok': true},
            }),
          );
          socket.add(
            jsonEncode(<String, dynamic>{
              'jsonrpc': '2.0',
              'method': 'turn/error',
              'params': <String, dynamic>{
                'threadId': threadId,
                'message': 'aborted',
              },
            }),
          );
          await socket.close();
          break;
        default:
          socket.add(
            jsonEncode(<String, dynamic>{
              'jsonrpc': '2.0',
              'id': id,
              'error': <String, dynamic>{
                'code': -32601,
                'message': 'unknown method $method',
              },
            }),
          );
      }
    }
  }

  Future<void> _emitTurn(WebSocket socket, String threadId) async {
    const parts = <String>['hello ', 'world ', 'from app server'];
    for (final part in parts) {
      try {
        socket.add(
          jsonEncode(<String, dynamic>{
            'jsonrpc': '2.0',
            'method': 'item/agentMessage/delta',
            'params': <String, dynamic>{
              'threadId': threadId,
              'turnId': 'turn-1',
              'delta': part,
            },
          }),
        );
      } catch (_) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    if (delayCompletion) {
      return;
    }
    socket.add(
      jsonEncode(<String, dynamic>{
        'jsonrpc': '2.0',
        'method': 'turn/completed',
        'params': <String, dynamic>{'threadId': threadId, 'turnId': 'turn-1'},
      }),
    );
  }
}

class _FakeOpenCodeRestServer {
  _FakeOpenCodeRestServer._(this._server);

  final HttpServer _server;
  final List<HttpResponse> _eventResponses = <HttpResponse>[];
  var _sessionCounter = 0;
  var _messageCounter = 0;
  bool healthRequested = false;
  int createdSessionCount = 0;
  String lastPromptText = '';
  final Map<String, String> _assistantTextBySession = <String, String>{};

  Uri get baseHttpUri => Uri.parse('http://127.0.0.1:${_server.port}');

  static Future<_FakeOpenCodeRestServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = _FakeOpenCodeRestServer._(server);
    unawaited(fake._listen());
    return fake;
  }

  Future<void> close() async {
    for (final response in _eventResponses.toList(growable: false)) {
      try {
        await response.close();
      } catch (_) {
        // Best effort.
      }
    }
    await _server.close(force: true);
  }

  Future<void> _listen() async {
    await for (final request in _server) {
      if (request.uri.path == '/global/health') {
        healthRequested = true;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(<String, dynamic>{'healthy': true, 'version': '1.3.3'}),
        );
        await request.response.close();
        continue;
      }
      if (request.uri.path == '/global/event') {
        request.response.headers.set(
          HttpHeaders.contentTypeHeader,
          'text/event-stream',
        );
        request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
        request.response.write(
          'data: ${jsonEncode(<String, dynamic>{'payload': <String, dynamic>{'type': 'server.connected', 'properties': <String, dynamic>{}}})}\n\n',
        );
        await request.response.flush();
        _eventResponses.add(request.response);
        continue;
      }
      if (request.uri.path == '/session' && request.method == 'POST') {
        createdSessionCount += 1;
        final sessionId = 'ses-${_sessionCounter++}';
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(<String, dynamic>{
            'id': sessionId,
            'title': 'test',
            'directory':
                request.uri.queryParameters['directory'] ?? Directory.current.path,
          }),
        );
        await request.response.close();
        continue;
      }
      final sessionMatch = RegExp(r'^/session/([^/]+)/message$').firstMatch(
        request.uri.path,
      );
      if (sessionMatch != null && request.method == 'GET') {
        final sessionId = sessionMatch.group(1)!;
        final text = _assistantTextBySession[sessionId] ?? '';
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(<Map<String, dynamic>>[
            <String, dynamic>{
              'info': <String, dynamic>{'id': 'msg-user', 'role': 'user'},
              'parts': <Map<String, dynamic>>[
                <String, dynamic>{'type': 'text', 'text': lastPromptText},
              ],
            },
            if (text.isNotEmpty)
              <String, dynamic>{
                'info': <String, dynamic>{
                  'id': 'msg-assistant',
                  'role': 'assistant',
                },
                'parts': <Map<String, dynamic>>[
                  <String, dynamic>{'type': 'text', 'text': text},
                ],
              },
          ]),
        );
        await request.response.close();
        continue;
      }
      if (sessionMatch != null && request.method == 'POST') {
        final sessionId = sessionMatch.group(1)!;
        final body = jsonDecode(await utf8.decodeStream(request));
        final parts = (body as Map<String, dynamic>)['parts'] as List<dynamic>? ??
            const <dynamic>[];
        if (parts.isNotEmpty) {
          lastPromptText =
              (parts.first as Map<String, dynamic>)['text']?.toString() ?? '';
        }
        final assistantMessageId = 'msg-assistant-${_messageCounter++}';
        await _broadcastEvent(
          <String, dynamic>{
            'payload': <String, dynamic>{
              'type': 'session.status',
              'properties': <String, dynamic>{
                'sessionID': sessionId,
                'status': <String, dynamic>{'type': 'busy'},
              },
            },
          },
        );
        await _broadcastEvent(
          <String, dynamic>{
            'payload': <String, dynamic>{
              'type': 'message.updated',
              'properties': <String, dynamic>{
                'sessionID': sessionId,
                'info': <String, dynamic>{
                  'id': assistantMessageId,
                  'role': 'assistant',
                },
              },
            },
          },
        );
        for (final delta in <String>['hello ', 'world ', 'from ', 'opencode']) {
          await _broadcastEvent(
            <String, dynamic>{
              'payload': <String, dynamic>{
                'type': 'message.part.delta',
                'properties': <String, dynamic>{
                  'sessionID': sessionId,
                  'part': <String, dynamic>{'messageID': assistantMessageId},
                  'text': delta,
                },
              },
            },
          );
        }
        await _broadcastEvent(
          <String, dynamic>{
            'payload': <String, dynamic>{
              'type': 'message.part.updated',
              'properties': <String, dynamic>{
                'sessionID': sessionId,
                'part': <String, dynamic>{
                  'messageID': assistantMessageId,
                  'type': 'text',
                  'text': 'hello world from opencode',
                },
              },
            },
          },
        );
        _assistantTextBySession[sessionId] = 'hello world from opencode';
        await _broadcastEvent(
          <String, dynamic>{
            'payload': <String, dynamic>{
              'type': 'session.status',
              'properties': <String, dynamic>{
                'sessionID': sessionId,
                'status': <String, dynamic>{'type': 'idle'},
              },
            },
          },
        );
        request.response.headers.contentType = ContentType.json;
        request.response.write('');
        await request.response.close();
        continue;
      }
      final abortMatch = RegExp(r'^/session/([^/]+)/abort$').firstMatch(
        request.uri.path,
      );
      if (abortMatch != null && request.method == 'POST') {
        request.response.headers.contentType = ContentType.json;
        request.response.write('{}');
        await request.response.close();
        continue;
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    }
  }

  Future<void> _broadcastEvent(Map<String, dynamic> event) async {
    final payload = 'data: ${jsonEncode(event)}\n\n';
    for (final response in _eventResponses.toList(growable: false)) {
      response.write(payload);
      await response.flush();
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

extension on DirectSingleAgentRunRequest {
  DirectSingleAgentRunRequest copyWith({
    void Function(String text)? onOutput,
    List<AssistantThreadSkillEntry>? selectedSkills,
  }) {
    return DirectSingleAgentRunRequest(
      sessionId: sessionId,
      provider: provider,
      prompt: prompt,
      model: model,
      workingDirectory: workingDirectory,
      gatewayToken: gatewayToken,
      selectedSkills: selectedSkills ?? this.selectedSkills,
      onOutput: onOutput ?? this.onOutput,
    );
  }
}
