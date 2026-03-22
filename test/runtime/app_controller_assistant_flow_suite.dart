@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

void main() {
  test(
    'AppController completes the minimal assistant flow against a gateway',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final gateway = await _FakeGatewayServer.start();
      final controller = AppController();
      addTearDown(controller.dispose);
      addTearDown(gateway.close);

      await _waitFor(() => !controller.initializing);

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
      await _waitFor(() => controller.tasksController.history.isNotEmpty);

      expect(
        controller.chatMessages.any(
          (message) =>
              message.role == 'assistant' &&
              message.text.contains('XWORKMATE_OK'),
        ),
        isTrue,
      );
      expect(
        controller.tasksController.history.any(
          (task) => task.summary.contains('XWORKMATE_OK'),
        ),
        isTrue,
      );
      expect(gateway.lastChatSendParams?['agentId'], 'main');
      expect(
        ((gateway.lastChatSendParams?['metadata'] as Map?)?['node']
            as Map?)?['kind'],
        'app-mediated-cooperative-node',
      );
      expect(
        ((gateway.lastChatSendParams?['metadata'] as Map?)?['dispatch']
            as Map?)?['mode'],
        'gateway-only',
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
