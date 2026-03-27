@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/i18n/app_language.dart';
import 'package:xworkmate/models/app_models.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';

void main() {
  test(
    'AppController routes LLM API destination through gateway settings and navigateHome restores assistant',
    () async {
      final harness = await _DesktopControllerHarness.create();
      addTearDown(harness.dispose);
      final controller = harness.controller;

      controller.navigateTo(WorkspaceDestination.tasks);
      expect(controller.destination, WorkspaceDestination.tasks);

      controller.navigateTo(WorkspaceDestination.aiGateway);

      expect(controller.destination, WorkspaceDestination.settings);
      expect(controller.settingsTab, SettingsTab.gateway);

      controller.navigateHome();
      await _waitFor(
        () => controller.currentSessionKey == 'main',
        timeout: const Duration(seconds: 2),
      );

      expect(controller.destination, WorkspaceDestination.assistant);
      expect(controller.currentSessionKey, 'main');
    },
  );

  test(
    'AppController connectManual followed by disconnectGateway clears the active runtime connection',
    () async {
      final gateway = await _FakeGatewayServer.start();
      addTearDown(gateway.close);
      final harness = await _DesktopControllerHarness.create();
      addTearDown(harness.dispose);
      final controller = harness.controller;

      await controller.connectManual(
        host: '127.0.0.1',
        port: gateway.port,
        tls: false,
        mode: RuntimeConnectionMode.local,
        token: _FakeGatewayServer.sharedToken,
      );

      expect(controller.connection.status, RuntimeConnectionStatus.connected);
      expect(gateway.connectAuthToken, _FakeGatewayServer.sharedToken);

      await controller.disconnectGateway();

      expect(controller.connection.status, RuntimeConnectionStatus.offline);
      expect(controller.chatMessages, isEmpty);
    },
  );

  test(
    'AppController persists settings drafts before apply and promotes them only after applySettingsDraft',
    () async {
      final harness = await _DesktopControllerHarness.create();
      addTearDown(harness.dispose);
      final controller = harness.controller;

      final nextSettings = controller.settings.copyWith(
        appLanguage: AppLanguage.en,
      );

      await controller.saveSettingsDraft(nextSettings);

      expect(controller.hasSettingsDraftChanges, isTrue);
      expect(controller.settings.appLanguage, AppLanguage.zh);

      await controller.persistSettingsDraft();

      expect(controller.hasPendingSettingsApply, isTrue);
      expect(controller.settings.appLanguage, AppLanguage.en);
      expect(controller.settingsDraft.appLanguage, AppLanguage.en);

      await controller.applySettingsDraft();

      expect(controller.hasPendingSettingsApply, isFalse);
      expect(controller.settings.appLanguage, AppLanguage.en);
      expect(controller.settingsDraft.appLanguage, AppLanguage.en);
    },
  );

  test(
    'AppController keeps AI Gateway model choices when single-agent falls back to AI chat',
    () async {
      final harness = await _DesktopControllerHarness.create(
        availableSingleAgentProvidersOverride: const <SingleAgentProvider>[],
      );
      addTearDown(harness.dispose);
      final controller = harness.controller;

      await controller.settingsController.saveAiGatewayApiKey('live-key');
      await controller.saveSettings(
        controller.settings.copyWith(
          aiGateway: controller.settings.aiGateway.copyWith(
            baseUrl: 'http://127.0.0.1:11434/v1',
            availableModels: const <String>['qwen2.5-coder:latest'],
            selectedModels: const <String>['qwen2.5-coder:latest'],
          ),
          assistantExecutionTarget: AssistantExecutionTarget.singleAgent,
        ),
      );
      await controller.setAssistantExecutionTarget(
        AssistantExecutionTarget.singleAgent,
      );

      expect(controller.currentSingleAgentHasResolvedProvider, isFalse);
      expect(controller.currentSingleAgentUsesAiChatFallback, isTrue);
      expect(controller.currentSingleAgentShouldShowModelControl, isTrue);
      expect(controller.assistantModelChoices, const <String>[
        'qwen2.5-coder:latest',
      ]);
      expect(controller.resolvedAssistantModel, 'qwen2.5-coder:latest');
    },
  );
}

class _DesktopControllerHarness {
  _DesktopControllerHarness._(this.rootDirectory, this.store, this.controller);

  final Directory rootDirectory;
  final SecureConfigStore store;
  final AppController controller;

  static Future<_DesktopControllerHarness> create({
    List<SingleAgentProvider>? availableSingleAgentProvidersOverride,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final tempDirectory = await Directory.systemTemp.createTemp(
      'xworkmate-app-controller-refactor-',
    );
    final store = SecureConfigStore(
      enableSecureStorage: false,
      databasePathResolver: () async => '${tempDirectory.path}/settings.db',
      fallbackDirectoryPathResolver: () async => tempDirectory.path,
    );
    final controller = AppController(
      store: store,
      availableSingleAgentProvidersOverride:
          availableSingleAgentProvidersOverride,
    );
    await _waitFor(() => !controller.initializing);
    return _DesktopControllerHarness._(tempDirectory, store, controller);
  }

  Future<void> dispose() async {
    controller.dispose();
    store.dispose();
    await _deleteDirectoryWithRetry(rootDirectory);
  }
}

class _FakeGatewayServer {
  _FakeGatewayServer._(this._server);

  static const sharedToken = 'shared-token-from-test';

  final HttpServer _server;
  WebSocket? _socket;
  String? connectAuthToken;
  final List<Map<String, dynamic>> _history = <Map<String, dynamic>>[];
  final String _lastMessagePreview = '';
  final double _updatedAtMs = DateTime.now().millisecondsSinceEpoch.toDouble();

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
        final acpSocket = await WebSocketTransformer.upgrade(request);
        await acpSocket.close(
          WebSocketStatus.normalClosure,
          'test gateway runtime only',
        );
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
                'sessionId': 'main',
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
          default:
            _send(socket, <String, dynamic>{
              'type': 'res',
              'id': id,
              'ok': true,
              'result': const <String, dynamic>{},
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
    final response = <String, dynamic>{
      'jsonrpc': '2.0',
      'id': id,
      'result': <String, dynamic>{},
    };
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(response));
    await request.response.close();
  }

  void _send(WebSocket socket, Map<String, dynamic> payload) {
    socket.add(jsonEncode(payload));
  }
}

Future<void> _deleteDirectoryWithRetry(Directory directory) async {
  if (directory.path.isEmpty) {
    return;
  }
  for (var attempt = 0; attempt < 5; attempt += 1) {
    if (!await directory.exists()) {
      return;
    }
    try {
      await directory.delete(recursive: true);
      return;
    } on FileSystemException {
      if (attempt == 4) {
        rethrow;
      }
      await Future<void>.delayed(Duration(milliseconds: 80 * (attempt + 1)));
    }
  }
}

Future<void> _waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
