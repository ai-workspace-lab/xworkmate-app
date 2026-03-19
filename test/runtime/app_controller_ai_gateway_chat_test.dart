import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/runtime/codex_runtime.dart';
import 'package:xworkmate/runtime/device_identity_store.dart';
import 'package:xworkmate/runtime/gateway_runtime.dart';
import 'package:xworkmate/runtime/runtime_coordinator.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';

void main() {
  test(
    'AppController sends persistent conversation turns through AI Gateway-only mode',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-ai-gateway-chat-',
      );
      final server = await _FakeAiGatewayServer.start();
      addTearDown(() async {
        await server.close();
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
      });

      final store = SecureConfigStore(
        enableSecureStorage: false,
        databasePathResolver: () async => '${tempDirectory.path}/settings.db',
        fallbackDirectoryPathResolver: () async => tempDirectory.path,
      );
      final gateway = _FakeGatewayRuntime(store: store);
      final controller = AppController(
        store: store,
        runtimeCoordinator: RuntimeCoordinator(
          gateway: gateway,
          codex: _FakeCodexRuntime(),
        ),
      );
      addTearDown(controller.dispose);

      await _waitFor(() => !controller.initializing);
      await controller.settingsController.saveAiGatewayApiKey('live-key');
      await controller.saveSettings(
        controller.settings.copyWith(
          aiGateway: controller.settings.aiGateway.copyWith(
            baseUrl: server.baseUrl,
            availableModels: const <String>['qwen2.5-coder:latest'],
            selectedModels: const <String>['qwen2.5-coder:latest'],
          ),
          defaultModel: 'qwen2.5-coder:latest',
        ),
        refreshAfterSave: false,
      );
      await controller.setAssistantExecutionTarget(
        AssistantExecutionTarget.aiGatewayOnly,
      );

      await controller.sendChatMessage('First question', thinking: 'low');

      await _waitFor(
        () => controller.chatMessages.any(
          (message) =>
              message.role == 'assistant' && message.text == 'FIRST_REPLY',
        ),
      );

      await controller.sendChatMessage('Second question', thinking: 'low');

      await _waitFor(
        () => controller.chatMessages.any(
          (message) =>
              message.role == 'assistant' && message.text == 'SECOND_REPLY',
        ),
      );

      expect(server.requestCount, 2);
      expect(server.lastAuthorization, 'Bearer live-key');
      expect(server.requests.first['model'], 'qwen2.5-coder:latest');
      expect(server.requests.first['messages'], <Map<String, dynamic>>[
        <String, dynamic>{'role': 'user', 'content': 'First question'},
      ]);
      expect(server.requests.last['messages'], <Map<String, dynamic>>[
        <String, dynamic>{'role': 'user', 'content': 'First question'},
        <String, dynamic>{'role': 'assistant', 'content': 'FIRST_REPLY'},
        <String, dynamic>{'role': 'user', 'content': 'Second question'},
      ]);
      expect(controller.connection.status, RuntimeConnectionStatus.offline);
      expect(controller.assistantConnectionStatusLabel, '仅 AI Gateway');
      expect(
        controller.assistantConnectionTargetLabel,
        'qwen2.5-coder:latest · 127.0.0.1:${server.port}',
      );
      expect(controller.chatMessages.last.text, 'SECOND_REPLY');
      expect(gateway.connectedProfiles, isEmpty);
    },
  );
}

class _FakeGatewayRuntime extends GatewayRuntime {
  _FakeGatewayRuntime({required super.store})
    : super(identityStore: DeviceIdentityStore(store));

  final List<GatewayConnectionProfile> connectedProfiles =
      <GatewayConnectionProfile>[];
  GatewayConnectionSnapshot _snapshot = GatewayConnectionSnapshot.initial();

  @override
  bool get isConnected => _snapshot.status == RuntimeConnectionStatus.connected;

  @override
  GatewayConnectionSnapshot get snapshot => _snapshot;

  @override
  Stream<GatewayPushEvent> get events => const Stream<GatewayPushEvent>.empty();

  @override
  Future<void> connectProfile(
    GatewayConnectionProfile profile, {
    String authTokenOverride = '',
    String authPasswordOverride = '',
  }) async {
    connectedProfiles.add(profile);
    _snapshot = GatewayConnectionSnapshot.initial(mode: profile.mode).copyWith(
      status: RuntimeConnectionStatus.connected,
      remoteAddress: '${profile.host}:${profile.port}',
    );
    notifyListeners();
  }

  @override
  Future<void> disconnect({bool clearDesiredProfile = true}) async {
    _snapshot = _snapshot.copyWith(status: RuntimeConnectionStatus.offline);
    notifyListeners();
  }

  @override
  Future<dynamic> request(
    String method, {
    Map<String, dynamic>? params,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    switch (method) {
      case 'health':
      case 'status':
        return <String, dynamic>{'ok': true};
      case 'agents.list':
        return <String, dynamic>{'agents': const <Object>[], 'mainKey': 'main'};
      case 'sessions.list':
        return <String, dynamic>{'sessions': const <Object>[]};
      case 'chat.history':
        return <String, dynamic>{'messages': const <Object>[]};
      case 'skills.status':
        return <String, dynamic>{'skills': const <Object>[]};
      case 'channels.status':
        return <String, dynamic>{
          'channelMeta': const <Object>[],
          'channelLabels': const <String, dynamic>{},
          'channelDetailLabels': const <String, dynamic>{},
          'channelAccounts': const <String, dynamic>{},
          'channelOrder': const <Object>[],
        };
      case 'models.list':
        return <String, dynamic>{'models': const <Object>[]};
      case 'cron.list':
        return <String, dynamic>{'jobs': const <Object>[]};
      case 'device.pair.list':
        return <String, dynamic>{
          'pending': const <Object>[],
          'paired': const <Object>[],
        };
      case 'system-presence':
        return const <Object>[];
      default:
        return <String, dynamic>{};
    }
  }
}

class _FakeCodexRuntime extends CodexRuntime {
  @override
  Future<String?> findCodexBinary() async => null;

  @override
  Future<void> stop() async {}
}

class _FakeAiGatewayServer {
  _FakeAiGatewayServer._(this._server);

  final HttpServer _server;
  int requestCount = 0;
  String? lastAuthorization;
  final List<Map<String, dynamic>> requests = <Map<String, dynamic>>[];

  int get port => _server.port;
  String get baseUrl => 'http://127.0.0.1:${_server.port}/v1';

  static Future<_FakeAiGatewayServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = _FakeAiGatewayServer._(server);
    unawaited(fake._serve());
    return fake;
  }

  Future<void> close() async {
    await _server.close(force: true);
  }

  Future<void> _serve() async {
    await for (final request in _server) {
      final path = request.uri.path;
      if (path != '/v1/chat/completions') {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        continue;
      }

      requestCount += 1;
      lastAuthorization = request.headers.value(
        HttpHeaders.authorizationHeader,
      );
      final body = await utf8.decoder.bind(request).join();
      requests.add((jsonDecode(body) as Map).cast<String, dynamic>());

      final reply = requestCount == 1 ? 'FIRST_REPLY' : 'SECOND_REPLY';
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(<String, dynamic>{
          'id': 'chatcmpl-$requestCount',
          'choices': <Map<String, dynamic>>[
            <String, dynamic>{
              'index': 0,
              'message': <String, dynamic>{
                'role': 'assistant',
                'content': reply,
              },
            },
          ],
        }),
      );
      await request.response.close();
    }
  }
}

Future<void> _waitFor(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition not met before timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
