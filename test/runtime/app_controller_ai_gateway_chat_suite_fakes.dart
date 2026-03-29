// ignore_for_file: unused_import, unnecessary_import

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/runtime/codex_runtime.dart';
import 'package:xworkmate/runtime/device_identity_store.dart';
import 'package:xworkmate/runtime/gateway_runtime.dart';
import 'package:xworkmate/runtime/go_agent_core_client.dart';
import 'package:xworkmate/runtime/runtime_coordinator.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';
import 'package:xworkmate/runtime/single_agent_runner.dart';
import 'app_controller_ai_gateway_chat_suite_core.dart';
import 'app_controller_ai_gateway_chat_suite_chat.dart';
import 'app_controller_ai_gateway_chat_suite_single_agent.dart';
import 'app_controller_ai_gateway_chat_suite_fixtures.dart';

class FakeGatewayRuntimeInternal extends GatewayRuntime {
  FakeGatewayRuntimeInternal({required super.store})
    : super(identityStore: DeviceIdentityStore(store));

  final List<GatewayConnectionProfile> connectedProfiles =
      <GatewayConnectionProfile>[];
  GatewayConnectionSnapshot fakeSnapshotInternal =
      GatewayConnectionSnapshot.initial();

  @override
  bool get isConnected =>
      fakeSnapshotInternal.status == RuntimeConnectionStatus.connected;

  @override
  GatewayConnectionSnapshot get snapshot => fakeSnapshotInternal;

  @override
  Stream<GatewayPushEvent> get events => const Stream<GatewayPushEvent>.empty();

  @override
  Future<void> connectProfile(
    GatewayConnectionProfile profile, {
    int? profileIndex,
    String authTokenOverride = '',
    String authPasswordOverride = '',
  }) async {
    connectedProfiles.add(profile);
    fakeSnapshotInternal = GatewayConnectionSnapshot.initial(mode: profile.mode)
        .copyWith(
          status: RuntimeConnectionStatus.connected,
          remoteAddress: '${profile.host}:${profile.port}',
        );
    notifyListeners();
  }

  @override
  Future<void> disconnect({bool clearDesiredProfile = true}) async {
    fakeSnapshotInternal = fakeSnapshotInternal.copyWith(
      status: RuntimeConnectionStatus.offline,
    );
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

class FakeCodexRuntimeInternal extends CodexRuntime {
  @override
  Future<String?> findCodexBinary() async => null;

  @override
  Future<void> stop() async {}
}

class FakeSingleAgentRunnerInternal implements SingleAgentRunner {
  FakeSingleAgentRunnerInternal({
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
  final List<SingleAgentRunRequest> requests = <SingleAgentRunRequest>[];

  @override
  Future<SingleAgentProviderResolution> resolveProvider({
    required SingleAgentProvider selection,
    required List<SingleAgentProvider> availableProviders,
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
    requests.add(request);
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

class FallbackOnlySingleAgentRunnerInternal
    extends FakeSingleAgentRunnerInternal {
  FallbackOnlySingleAgentRunnerInternal()
    : super(
        resolvedProvider: null,
        fallbackReason: 'No supported external CLI provider is available.',
      );
}

class FakeGoAgentCoreClientInternal implements GoAgentCoreClient {
  FakeGoAgentCoreClientInternal({
    this.capabilities = const GoAgentCoreCapabilities.empty(),
    this.result = const GoAgentCoreRunResult(
      success: false,
      message: '',
      turnId: '',
      raw: <String, dynamic>{},
      errorMessage: 'no result configured',
      resolvedModel: '',
    ),
  });

  final GoAgentCoreCapabilities capabilities;
  final GoAgentCoreRunResult result;

  int capabilitiesCalls = 0;
  int executeCalls = 0;
  int cancelCalls = 0;
  GoAgentCoreSessionRequest? lastRequest;
  final List<GoAgentCoreSessionRequest> requests = <GoAgentCoreSessionRequest>[];

  @override
  Future<GoAgentCoreCapabilities> loadCapabilities({
    required AssistantExecutionTarget target,
    bool forceRefresh = false,
  }) async {
    capabilitiesCalls += 1;
    return capabilities;
  }

  @override
  Future<GoAgentCoreRunResult> executeSession(
    GoAgentCoreSessionRequest request, {
    required void Function(GoAgentCoreSessionUpdate update) onUpdate,
  }) async {
    executeCalls += 1;
    lastRequest = request;
    requests.add(request);
    if (result.message.trim().isNotEmpty) {
      onUpdate(
        GoAgentCoreSessionUpdate(
          sessionId: request.sessionId,
          threadId: request.threadId,
          turnId: result.turnId,
          type: 'delta',
          text: result.message,
          message: '',
          pending: false,
          error: false,
          payload: const <String, dynamic>{'type': 'delta'},
        ),
      );
    }
    return result;
  }

  @override
  Future<void> cancelSession({
    required AssistantExecutionTarget target,
    required String sessionId,
    required String threadId,
  }) async {
    cancelCalls += 1;
  }

  @override
  Future<void> closeSession({
    required AssistantExecutionTarget target,
    required String sessionId,
    required String threadId,
  }) async {}

  @override
  Future<void> dispose() async {}
}

class FallbackOnlyGoAgentCoreClientInternal
    extends FakeGoAgentCoreClientInternal {
  FallbackOnlyGoAgentCoreClientInternal()
    : super(capabilities: const GoAgentCoreCapabilities.empty());
}

class FakeAiGatewayServerInternal {
  FakeAiGatewayServerInternal._(this.serverInternal, this.responseModeInternal);

  final HttpServer serverInternal;
  final AiGatewayResponseModeInternal responseModeInternal;
  int requestCount = 0;
  String? lastAuthorization;
  final List<Map<String, dynamic>> requests = <Map<String, dynamic>>[];
  final Map<int, Completer<void>> completionGatesInternal =
      <int, Completer<void>>{};

  int get port => serverInternal.port;
  String get baseUrl => 'http://127.0.0.1:${serverInternal.port}/v1';

  static Future<FakeAiGatewayServerInternal> start({
    required AiGatewayResponseModeInternal responseMode,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = FakeAiGatewayServerInternal._(server, responseMode);
    unawaited(fake.serveInternal());
    return fake;
  }

  void allowCompletion(int requestNumber) {
    completionGatesInternal[requestNumber]?.complete();
  }

  Future<void> close() async {
    await serverInternal.close(force: true);
  }

  Future<void> serveInternal() async {
    await for (final request in serverInternal) {
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
      if (responseModeInternal == AiGatewayResponseModeInternal.json) {
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
      completionGatesInternal[requestCount] = gate;
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

enum AiGatewayResponseModeInternal { json, sse }
