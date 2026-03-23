@TestOn('vm')
library;

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
import 'package:xworkmate/runtime/single_agent_runner.dart';

void main() {
  test(
    'AppController streams and restores persistent Single Agent conversation turns',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-ai-gateway-chat-',
      );
      final server = await _FakeAiGatewayServer.start(
        responseMode: _AiGatewayResponseMode.sse,
      );
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
        availableSingleAgentProvidersOverride: const <SingleAgentProvider>[],
        runtimeCoordinator: RuntimeCoordinator(
          gateway: gateway,
          codex: _FakeCodexRuntime(),
        ),
        singleAgentRunner: _FallbackOnlySingleAgentRunner(),
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
          defaultModel: 'gpt-5.4',
          multiAgent: controller.settings.multiAgent.copyWith(
            autoSync: false,
            mountTargets: _withAvailableMountTargets(
              controller.settings.multiAgent.mountTargets,
              const <String>[],
            ),
          ),
        ),
        refreshAfterSave: false,
      );
      await controller.setAssistantExecutionTarget(
        AssistantExecutionTarget.singleAgent,
      );

      const firstQuestion =
          'Execution context:\n'
          '- target: single-agent\n'
          '- workspace_root: /opt/data/workspace\n'
          '- permission: full-access\n\n'
          '今天聊点什么';
      const secondQuestion = '继续刚才的话题';

      final firstTurn = controller.sendChatMessage(
        firstQuestion,
        thinking: 'low',
      );
      await _waitFor(
        () => controller.chatMessages.any(
          (message) => message.role == 'assistant' && message.pending,
        ),
      );
      expect(controller.hasAssistantPendingRun, isTrue);
      server.allowCompletion(1);
      await firstTurn;

      await _waitFor(
        () => controller.chatMessages.any(
          (message) =>
              message.role == 'assistant' && message.text == 'FIRST_REPLY',
        ),
      );

      final secondStore = SecureConfigStore(
        enableSecureStorage: false,
        databasePathResolver: () async => '${tempDirectory.path}/settings.db',
        fallbackDirectoryPathResolver: () async => tempDirectory.path,
      );
      final secondGateway = _FakeGatewayRuntime(store: secondStore);
      final secondController = AppController(
        store: secondStore,
        availableSingleAgentProvidersOverride: const <SingleAgentProvider>[],
        runtimeCoordinator: RuntimeCoordinator(
          gateway: secondGateway,
          codex: _FakeCodexRuntime(),
        ),
        singleAgentRunner: _FallbackOnlySingleAgentRunner(),
      );
      addTearDown(secondController.dispose);

      await _waitFor(() => !secondController.initializing);
      await secondController.settingsController.saveAiGatewayApiKey('live-key');

      expect(secondController.chatMessages.last.text, 'FIRST_REPLY');
      expect(
        secondController.settings.assistantExecutionTarget,
        AssistantExecutionTarget.singleAgent,
      );

      final secondTurn = secondController.sendChatMessage(
        secondQuestion,
        thinking: 'low',
      );
      await _waitFor(
        () => secondController.chatMessages.any(
          (message) => message.role == 'assistant' && message.pending,
        ),
      );
      server.allowCompletion(2);
      await secondTurn;

      await _waitFor(
        () => secondController.chatMessages.any(
          (message) =>
              message.role == 'assistant' && message.text == 'SECOND_REPLY',
        ),
      );

      expect(server.requestCount, 2);
      expect(server.lastAuthorization, 'Bearer live-key');
      expect(server.requests.first['model'], 'qwen2.5-coder:latest');
      expect(server.requests.first['stream'], isTrue);
      expect(server.requests.first['messages'], <Map<String, dynamic>>[
        <String, dynamic>{'role': 'user', 'content': firstQuestion},
      ]);
      expect(server.requests.last['messages'], <Map<String, dynamic>>[
        <String, dynamic>{'role': 'user', 'content': firstQuestion},
        <String, dynamic>{'role': 'assistant', 'content': 'FIRST_REPLY'},
        <String, dynamic>{'role': 'user', 'content': secondQuestion},
      ]);
      expect(
        secondController.connection.status,
        RuntimeConnectionStatus.offline,
      );
      expect(secondController.assistantConnectionStatusLabel, '单机智能体');
      expect(
        secondController.assistantConnectionTargetLabel,
        'AI Chat fallback · qwen2.5-coder:latest · 127.0.0.1:${server.port}',
      );
      expect(secondController.chatMessages.last.text, 'SECOND_REPLY');
      expect(gateway.connectedProfiles, isEmpty);
      expect(secondGateway.connectedProfiles, isEmpty);
    },
  );

  test(
    'AppController falls back when LLM API ignores stream mode',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-ai-gateway-json-fallback-',
      );
      final server = await _FakeAiGatewayServer.start(
        responseMode: _AiGatewayResponseMode.json,
      );
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
      final controller = AppController(
        store: store,
        availableSingleAgentProvidersOverride: const <SingleAgentProvider>[],
        runtimeCoordinator: RuntimeCoordinator(
          gateway: _FakeGatewayRuntime(store: store),
          codex: _FakeCodexRuntime(),
        ),
        singleAgentRunner: _FallbackOnlySingleAgentRunner(),
      );
      addTearDown(controller.dispose);

      await _waitFor(() => !controller.initializing);
      await controller.settingsController.saveAiGatewayApiKey('live-key');
      await controller.saveSettings(
        controller.settings.copyWith(
          aiGateway: controller.settings.aiGateway.copyWith(
            baseUrl: server.baseUrl,
            availableModels: const <String>['moonshotai/kimi-k2.5'],
            selectedModels: const <String>['moonshotai/kimi-k2.5'],
          ),
          defaultModel: 'moonshotai/kimi-k2.5',
          multiAgent: controller.settings.multiAgent.copyWith(
            autoSync: false,
            mountTargets: _withAvailableMountTargets(
              controller.settings.multiAgent.mountTargets,
              const <String>[],
            ),
          ),
        ),
        refreshAfterSave: false,
      );
      await controller.setAssistantExecutionTarget(
        AssistantExecutionTarget.singleAgent,
      );

      await controller.sendChatMessage('你好', thinking: 'low');

      await _waitFor(
        () => controller.chatMessages.any(
          (message) =>
              message.role == 'assistant' && message.text == 'FIRST_REPLY',
        ),
      );

      expect(server.requests.single['stream'], isTrue);
      expect(controller.chatMessages.last.pending, isFalse);
    },
  );

  test(
    'AppController abortRun stops Single Agent streaming requests',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-ai-gateway-abort-',
      );
      final server = await _FakeAiGatewayServer.start(
        responseMode: _AiGatewayResponseMode.sse,
      );
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
      final controller = AppController(
        store: store,
        availableSingleAgentProvidersOverride: const <SingleAgentProvider>[],
        runtimeCoordinator: RuntimeCoordinator(
          gateway: _FakeGatewayRuntime(store: store),
          codex: _FakeCodexRuntime(),
        ),
        singleAgentRunner: _FallbackOnlySingleAgentRunner(),
      );
      addTearDown(controller.dispose);

      await _waitFor(() => !controller.initializing);
      await controller.settingsController.saveAiGatewayApiKey('live-key');
      await controller.saveSettings(
        controller.settings.copyWith(
          aiGateway: controller.settings.aiGateway.copyWith(
            baseUrl: server.baseUrl,
            availableModels: const <String>['z-ai/glm5'],
            selectedModels: const <String>['z-ai/glm5'],
          ),
          defaultModel: 'z-ai/glm5',
          multiAgent: controller.settings.multiAgent.copyWith(
            autoSync: false,
            mountTargets: _withAvailableMountTargets(
              controller.settings.multiAgent.mountTargets,
              const <String>[],
            ),
          ),
        ),
        refreshAfterSave: false,
      );
      await controller.setAssistantExecutionTarget(
        AssistantExecutionTarget.singleAgent,
      );

      final pendingTurn = controller.sendChatMessage('今天聊点什么', thinking: 'low');
      await _waitFor(
        () => controller.chatMessages.any(
          (message) => message.role == 'assistant' && message.pending,
        ),
      );

      await controller.abortRun();
      server.allowCompletion(1);
      await pendingTurn;
      await _waitFor(() => !controller.hasAssistantPendingRun);

      expect(
        controller.chatMessages.where((message) => message.pending),
        isEmpty,
      );
      expect(
        controller.chatMessages.where((message) => message.error),
        isEmpty,
      );
    },
  );

  test(
    'AppController uses the selected Single Agent provider before AI Chat fallback',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-single-agent-provider-',
      );
      addTearDown(() async {
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
      });

      final store = SecureConfigStore(
        enableSecureStorage: false,
        databasePathResolver: () async => '${tempDirectory.path}/settings.db',
        fallbackDirectoryPathResolver: () async => tempDirectory.path,
      );
      final runner = _FakeSingleAgentRunner(
        resolvedProvider: SingleAgentProvider.codex,
        result: const SingleAgentRunResult(
          provider: SingleAgentProvider.codex,
          output: 'CODEX_REPLY',
          success: true,
          errorMessage: '',
          shouldFallbackToAiChat: false,
        ),
      );
      final controller = AppController(
        store: store,
        availableSingleAgentProvidersOverride: const <SingleAgentProvider>[
          SingleAgentProvider.codex,
        ],
        runtimeCoordinator: RuntimeCoordinator(
          gateway: _FakeGatewayRuntime(store: store),
          codex: _FakeCodexRuntime(),
        ),
        singleAgentRunner: runner,
      );
      addTearDown(controller.dispose);

      await _waitFor(() => !controller.initializing);
      await controller.setAssistantExecutionTarget(
        AssistantExecutionTarget.singleAgent,
      );
      await controller.setSingleAgentProvider(SingleAgentProvider.codex);

      await controller.sendChatMessage('请输出 CODEX_REPLY', thinking: 'low');

      expect(runner.resolveCalls, 1);
      expect(runner.runCalls, 1);
      expect(runner.lastRequest?.provider, SingleAgentProvider.codex);
      expect(
        controller.chatMessages.any(
          (message) => message.role == 'assistant' && message.text == 'CODEX_REPLY',
        ),
        isTrue,
      );
      expect(
        controller.chatMessages.any((message) => message.toolName == 'Codex'),
        isTrue,
      );
    },
  );

  test(
    'AppController keeps the thread provider strict when another external CLI is available',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-single-agent-strict-provider-',
      );
      final server = await _FakeAiGatewayServer.start(
        responseMode: _AiGatewayResponseMode.json,
      );
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
      final runner = _FakeSingleAgentRunner(
        resolvedProvider: null,
        fallbackReason: 'Codex CLI is unavailable on this device.',
      );
      final controller = AppController(
        store: store,
        availableSingleAgentProvidersOverride: const <SingleAgentProvider>[
          SingleAgentProvider.claude,
        ],
        runtimeCoordinator: RuntimeCoordinator(
          gateway: _FakeGatewayRuntime(store: store),
          codex: _FakeCodexRuntime(),
        ),
        singleAgentRunner: runner,
      );
      addTearDown(controller.dispose);

      await _waitFor(() => !controller.initializing);
      await controller.settingsController.saveAiGatewayApiKey('live-key');
      await controller.saveSettings(
        controller.settings.copyWith(
          aiGateway: controller.settings.aiGateway.copyWith(
            baseUrl: server.baseUrl,
            availableModels: const <String>['moonshotai/kimi-k2.5'],
            selectedModels: const <String>['moonshotai/kimi-k2.5'],
          ),
          defaultModel: 'moonshotai/kimi-k2.5',
          multiAgent: controller.settings.multiAgent.copyWith(
            autoSync: false,
            mountTargets: _withAvailableMountTargets(
              controller.settings.multiAgent.mountTargets,
              const <String>['claude'],
            ),
          ),
        ),
        refreshAfterSave: false,
      );
      await controller.setAssistantExecutionTarget(
        AssistantExecutionTarget.singleAgent,
      );
      await controller.setSingleAgentProvider(SingleAgentProvider.codex);

      await controller.sendChatMessage('你好', thinking: 'low');

      expect(runner.resolveCalls, 1);
      expect(runner.runCalls, 0);
      expect(server.requestCount, 0);
      expect(controller.currentAssistantConnectionState.connected, isFalse);
      expect(
        controller.chatMessages.any(
          (message) => message.text.contains('可切到 Auto'),
        ),
        isTrue,
      );
    },
  );

  test(
    'AppController falls back to AI Chat when no external CLI is available',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-single-agent-fallback-',
      );
      final server = await _FakeAiGatewayServer.start(
        responseMode: _AiGatewayResponseMode.json,
      );
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
      final runner = _FakeSingleAgentRunner(
        resolvedProvider: null,
        fallbackReason: 'Codex CLI is unavailable on this device.',
      );
      final controller = AppController(
        store: store,
        availableSingleAgentProvidersOverride: const <SingleAgentProvider>[],
        runtimeCoordinator: RuntimeCoordinator(
          gateway: _FakeGatewayRuntime(store: store),
          codex: _FakeCodexRuntime(),
        ),
        singleAgentRunner: runner,
      );
      addTearDown(controller.dispose);

      await _waitFor(() => !controller.initializing);
      await controller.settingsController.saveAiGatewayApiKey('live-key');
      await controller.saveSettings(
        controller.settings.copyWith(
          aiGateway: controller.settings.aiGateway.copyWith(
            baseUrl: server.baseUrl,
            availableModels: const <String>['moonshotai/kimi-k2.5'],
            selectedModels: const <String>['moonshotai/kimi-k2.5'],
          ),
          defaultModel: 'moonshotai/kimi-k2.5',
        ),
        refreshAfterSave: false,
      );
      await controller.setAssistantExecutionTarget(
        AssistantExecutionTarget.singleAgent,
      );
      await controller.setSingleAgentProvider(SingleAgentProvider.codex);

      await controller.sendChatMessage('你好', thinking: 'low');

      expect(runner.resolveCalls, 1);
      expect(runner.runCalls, 0);
      expect(server.requestCount, 1);
      expect(
        controller.chatMessages.any(
          (message) =>
              message.toolName == 'AI Chat fallback' &&
              message.text.contains('Codex CLI is unavailable'),
        ),
        isTrue,
      );
      expect(
        controller.chatMessages.any(
          (message) =>
              message.role == 'assistant' && message.text == 'FIRST_REPLY',
        ),
        isTrue,
      );
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

class _FakeSingleAgentRunner implements SingleAgentRunner {
  _FakeSingleAgentRunner({
    required this.resolvedProvider,
    this.result,
    this.fallbackReason,
  });

  final SingleAgentProvider? resolvedProvider;
  final SingleAgentRunResult? result;
  final String? fallbackReason;

  int resolveCalls = 0;
  int runCalls = 0;
  int abortCalls = 0;
  SingleAgentRunRequest? lastRequest;

  @override
  Future<SingleAgentProviderResolution> resolveProvider({
    required SingleAgentProvider selection,
    required String configuredCodexCliPath,
    required String gatewayToken,
  }) async {
    resolveCalls += 1;
    return SingleAgentProviderResolution(
      selection: selection,
      resolvedProvider: resolvedProvider,
      fallbackReason: fallbackReason,
    );
  }

  @override
  Future<SingleAgentRunResult> run(SingleAgentRunRequest request) async {
    runCalls += 1;
    lastRequest = request;
    if (result?.output.isNotEmpty == true) {
      request.onOutput?.call(result!.output);
    }
    return result ??
        SingleAgentRunResult(
          provider: request.provider,
          output: '',
          success: false,
          errorMessage: 'no result configured',
          shouldFallbackToAiChat: false,
        );
  }

  @override
  Future<void> abort(String sessionId) async {
    abortCalls += 1;
  }
}

class _FallbackOnlySingleAgentRunner extends _FakeSingleAgentRunner {
  _FallbackOnlySingleAgentRunner()
    : super(
        resolvedProvider: null,
        fallbackReason: 'No supported external CLI provider is available.',
      );
}

class _FakeAiGatewayServer {
  _FakeAiGatewayServer._(this._server, this._responseMode);

  final HttpServer _server;
  final _AiGatewayResponseMode _responseMode;
  int requestCount = 0;
  String? lastAuthorization;
  final List<Map<String, dynamic>> requests = <Map<String, dynamic>>[];
  final Map<int, Completer<void>> _completionGates = <int, Completer<void>>{};

  int get port => _server.port;
  String get baseUrl => 'http://127.0.0.1:${_server.port}/v1';

  static Future<_FakeAiGatewayServer> start({
    required _AiGatewayResponseMode responseMode,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = _FakeAiGatewayServer._(server, responseMode);
    unawaited(fake._serve());
    return fake;
  }

  void allowCompletion(int requestNumber) {
    _completionGates[requestNumber]?.complete();
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
      if (_responseMode == _AiGatewayResponseMode.json) {
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
        continue;
      }

      final gate = Completer<void>();
      _completionGates[requestCount] = gate;
      request.response.bufferOutput = false;
      request.response.headers.set(
        HttpHeaders.contentTypeHeader,
        'text/event-stream; charset=utf-8',
      );
      request.response.write(
        'data: ${jsonEncode(<String, dynamic>{
          'choices': <Object>[
            <String, dynamic>{
              'delta': <String, dynamic>{'content': '${reply.split('_').first}_'},
            },
          ],
        })}\n\n',
      );
      await request.response.flush();
      await gate.future;
      try {
        request.response.write(
          'data: ${jsonEncode(<String, dynamic>{
            'choices': <Object>[
              <String, dynamic>{
                'delta': <String, dynamic>{'content': 'REPLY'},
              },
            ],
          })}\n\n',
        );
        request.response.write('data: [DONE]\n\n');
      } on HttpException {
        // Client aborted the stream; allow the handler to terminate cleanly.
      }
      try {
        await request.response.close();
      } on HttpException {
        // Client closed the connection while the server was still streaming.
      } on SocketException {
        // Same as above on some runners.
      }
    }
  }
}

enum _AiGatewayResponseMode { json, sse }

List<ManagedMountTargetState> _withAvailableMountTargets(
  List<ManagedMountTargetState> current,
  List<String> availableIds,
) {
  final nextIds = availableIds.toSet();
  return current
      .map(
        (item) => item.copyWith(
          available: nextIds.contains(item.targetId),
          discoveryState: nextIds.contains(item.targetId) ? 'ready' : 'idle',
          syncState: nextIds.contains(item.targetId) ? 'ready' : 'idle',
        ),
      )
      .toList(growable: false);
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
