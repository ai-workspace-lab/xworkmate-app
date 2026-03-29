import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'embedded_agent_launch_policy.dart';
import 'gateway_runtime_errors.dart';
import 'gateway_runtime_helpers.dart';
import 'gateway_runtime_session_client.dart';
import 'go_core.dart';

typedef GoGatewayRuntimeProcessStarter =
    Future<Process> Function(
      String executable,
      List<String> arguments, {
      Map<String, String>? environment,
      String? workingDirectory,
    });

class GoGatewayRuntimeDesktopClient implements GatewayRuntimeSessionClient {
  GoGatewayRuntimeDesktopClient({
    GoCoreLocator? goCoreLocator,
    GoGatewayRuntimeProcessStarter? processStarter,
  }) : _goCoreLocator = goCoreLocator ?? GoCoreLocator(),
       _processStarter =
           processStarter ??
           ((executable, arguments, {environment, workingDirectory}) {
             return Process.start(
               executable,
               arguments,
               environment: environment,
               workingDirectory: workingDirectory,
             );
           });

  final GoCoreLocator _goCoreLocator;
  final GoGatewayRuntimeProcessStarter _processStarter;

  final StreamController<GatewayRuntimeSessionUpdate> _updatesController =
      StreamController<GatewayRuntimeSessionUpdate>.broadcast();
  final Map<String, Completer<Map<String, dynamic>>> _pending =
      <String, Completer<Map<String, dynamic>>>{};

  Process? _localProcess;
  Uri? _localEndpoint;
  Future<Uri?>? _localEndpointFuture;
  WebSocket? _socket;
  StreamSubscription<dynamic>? _socketSubscription;
  Future<void>? _socketReadyFuture;
  int _requestCounter = 0;

  @override
  Stream<GatewayRuntimeSessionUpdate> get updates => _updatesController.stream;

  @override
  Future<GatewayRuntimeSessionConnectResult> connect(
    GatewayRuntimeSessionConnectRequest request,
  ) async {
    final result = await _request(
      method: 'xworkmate.gateway.connect',
      params: request.toJson(),
    );
    if (boolValue(result['ok']) != true) {
      throw _gatewayErrorFromResult(
        result,
        fallbackMessage: 'Gateway connect failed',
      );
    }
    return GatewayRuntimeSessionConnectResult.fromJson(result);
  }

  @override
  Future<dynamic> request({
    required String runtimeId,
    required String method,
    Map<String, dynamic>? params,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final result = await _request(
      method: 'xworkmate.gateway.request',
      params: <String, dynamic>{
        'runtimeId': runtimeId,
        'method': method,
        if (params != null && params.isNotEmpty) 'params': params,
        'timeoutMs': timeout.inMilliseconds,
      },
    );
    if (boolValue(result['ok']) != true) {
      throw _gatewayErrorFromResult(
        result,
        fallbackMessage: '$method request failed',
      );
    }
    return result['payload'];
  }

  @override
  Future<void> disconnect({required String runtimeId}) async {
    await _request(
      method: 'xworkmate.gateway.disconnect',
      params: <String, dynamic>{'runtimeId': runtimeId},
    );
  }

  @override
  Future<void> dispose() async {
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(
          GatewayRuntimeException(
            'Go gateway runtime transport disposed',
            code: 'GO_GATEWAY_RUNTIME_TRANSPORT_DISPOSED',
          ),
        );
      }
    }
    _pending.clear();
    await _socketSubscription?.cancel();
    _socketSubscription = null;
    try {
      await _socket?.close();
    } catch (_) {
      // Best effort only.
    }
    _socket = null;
    _socketReadyFuture = null;
    final process = _localProcess;
    _localProcess = null;
    _localEndpoint = null;
    _localEndpointFuture = null;
    if (process != null) {
      try {
        process.kill();
      } catch (_) {
        // Best effort only.
      }
    }
    await _updatesController.close();
  }

  Future<Map<String, dynamic>> _request({
    required String method,
    required Map<String, dynamic> params,
  }) async {
    await _ensureSocketReady();
    final socket = _socket;
    if (socket == null) {
      throw GatewayRuntimeException(
        'Missing Go gateway runtime transport',
        code: 'GO_GATEWAY_RUNTIME_TRANSPORT_UNAVAILABLE',
      );
    }
    final requestId =
        '${DateTime.now().microsecondsSinceEpoch}-$method-${_requestCounter++}';
    final completer = Completer<Map<String, dynamic>>();
    _pending[requestId] = completer;
    socket.add(
      jsonEncode(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': requestId,
        'method': method,
        'params': params,
      }),
    );
    try {
      return await completer.future.timeout(const Duration(seconds: 120));
    } finally {
      _pending.remove(requestId);
    }
  }

  Future<void> _ensureSocketReady() async {
    final inFlight = _socketReadyFuture;
    if (inFlight != null) {
      return inFlight;
    }
    final next = _openSocket();
    _socketReadyFuture = next;
    try {
      await next;
    } finally {
      _socketReadyFuture = null;
    }
  }

  Future<void> _openSocket() async {
    if (_socket != null) {
      return;
    }
    final endpoint = await _ensureLocalEndpoint();
    if (endpoint == null) {
      throw GatewayRuntimeException(
        'Missing Go gateway runtime endpoint',
        code: 'GO_GATEWAY_RUNTIME_ENDPOINT_MISSING',
      );
    }
    final wsEndpoint = endpoint.replace(
      scheme: endpoint.scheme == 'https' ? 'wss' : 'ws',
      path: '/acp',
    );
    final socket = await WebSocket.connect(wsEndpoint.toString()).timeout(
      const Duration(seconds: 6),
      onTimeout: () => throw GatewayRuntimeException(
        'Go gateway runtime websocket connect timeout',
        code: 'GO_GATEWAY_RUNTIME_WS_CONNECT_TIMEOUT',
      ),
    );
    _socket = socket;
    _socketSubscription = socket.listen(
      _handleSocketMessage,
      onError: (Object error, StackTrace stackTrace) {
        _failPending(
          GatewayRuntimeException(
            error.toString(),
            code: 'GO_GATEWAY_RUNTIME_WS_ERROR',
          ),
        );
      },
      onDone: () {
        _socket = null;
        _socketSubscription = null;
        _failPending(
          GatewayRuntimeException(
            'Go gateway runtime websocket closed',
            code: 'GO_GATEWAY_RUNTIME_WS_CLOSED',
          ),
        );
      },
      cancelOnError: true,
    );
  }

  void _handleSocketMessage(dynamic raw) {
    final json = _decodeMap(raw);
    final id = json['id']?.toString().trim();
    if (id != null && id.isNotEmpty) {
      final completer = _pending[id];
      if (completer != null && !completer.isCompleted) {
        final error = _castMap(json['error']);
        if (error.isNotEmpty) {
          completer.completeError(
            GatewayRuntimeException(
              error['message']?.toString() ??
                  'Go gateway runtime request failed',
              code: error['code']?.toString(),
            ),
          );
        } else {
          completer.complete(_castMap(json['result']));
        }
      }
      return;
    }
    final method = json['method']?.toString().trim() ?? '';
    if (method.isEmpty) {
      return;
    }
    try {
      _updatesController.add(
        GatewayRuntimeSessionUpdate.fromNotification(json),
      );
    } catch (_) {
      // Ignore unrelated ACP notifications.
    }
  }

  void _failPending(GatewayRuntimeException error) {
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }
    _pending.clear();
  }

  Future<Uri?> _ensureLocalEndpoint() async {
    if (_localEndpoint != null) {
      return _localEndpoint;
    }
    final inFlight = _localEndpointFuture;
    if (inFlight != null) {
      return inFlight;
    }
    final next = _startLocalProcess();
    _localEndpointFuture = next;
    try {
      _localEndpoint = await next;
      return _localEndpoint;
    } finally {
      _localEndpointFuture = null;
    }
  }

  Future<Uri?> _startLocalProcess() async {
    if (shouldBlockEmbeddedAgentLaunch(
      isAppleHost: Platform.isIOS || Platform.isMacOS,
    )) {
      return null;
    }
    final launch = await _goCoreLocator.locate();
    if (launch == null) {
      return null;
    }
    final reservedSocket = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final port = reservedSocket.port;
    await reservedSocket.close();
    final listenAddress = '127.0.0.1:$port';
    final process = await _processStarter(
      launch.executable,
      <String>[...launch.arguments, 'serve', '--listen', listenAddress],
      environment: Platform.environment,
      workingDirectory: launch.workingDirectory,
    );
    _localProcess = process;
    unawaited(process.stdout.drain<void>());
    unawaited(process.stderr.drain<void>());
    final endpoint = Uri(scheme: 'http', host: '127.0.0.1', port: port);
    final deadline = DateTime.now().add(const Duration(seconds: 8));
    while (DateTime.now().isBefore(deadline)) {
      if (_localProcess != process) {
        break;
      }
      final exitCode = await process.exitCode.timeout(
        const Duration(milliseconds: 20),
        onTimeout: () => -1,
      );
      if (exitCode != -1) {
        break;
      }
      try {
        final probe = await WebSocket.connect(
          endpoint.replace(scheme: 'ws', path: '/acp').toString(),
        ).timeout(const Duration(milliseconds: 300));
        await probe.close();
        return endpoint;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
    }
    return null;
  }

  GatewayRuntimeException _gatewayErrorFromResult(
    Map<String, dynamic> result, {
    required String fallbackMessage,
  }) {
    final error = _castMap(result['error']);
    return GatewayRuntimeException(
      error['message']?.toString() ?? fallbackMessage,
      code: error['code']?.toString(),
      details: error['details'],
    );
  }

  Map<String, dynamic> _decodeMap(dynamic raw) {
    if (raw is Map<String, dynamic>) {
      return raw;
    }
    if (raw is Map) {
      return raw.cast<String, dynamic>();
    }
    if (raw is String) {
      return _castMap(jsonDecode(raw));
    }
    if (raw is List<int>) {
      return _castMap(jsonDecode(utf8.decode(raw)));
    }
    return const <String, dynamic>{};
  }

  Map<String, dynamic> _castMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.cast<String, dynamic>();
    }
    return const <String, dynamic>{};
  }
}
