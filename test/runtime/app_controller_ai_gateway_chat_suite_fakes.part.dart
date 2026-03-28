part of 'app_controller_ai_gateway_chat_suite.dart';

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
    int? profileIndex,
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
