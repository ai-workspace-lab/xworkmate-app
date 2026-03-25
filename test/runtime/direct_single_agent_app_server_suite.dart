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

      expect(result.success, isTrue);
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
