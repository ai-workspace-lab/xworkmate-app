import 'dart:async';
import 'dart:io';

import 'embedded_agent_launch_policy.dart';
import 'gateway_acp_client.dart';
import 'go_core.dart';
import 'go_task_service_client.dart';
import 'runtime_models.dart';

typedef ExternalCodeAgentAcpProcessStarter =
    Future<Process> Function(
      String executable,
      List<String> arguments, {
      Map<String, String>? environment,
      String? workingDirectory,
    });

class ExternalCodeAgentAcpDesktopTransport implements ExternalCodeAgentAcpTransport {
  ExternalCodeAgentAcpDesktopTransport({
    required GatewayAcpClient acpClient,
    required Uri? Function(AssistantExecutionTarget target) endpointResolver,
    GoCoreLocator? goCoreLocator,
    ExternalCodeAgentAcpProcessStarter? processStarter,
  }) : _acpClient = acpClient,
       _endpointResolver = endpointResolver,
       _goCoreLocator = goCoreLocator ?? GoCoreLocator(),
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

  final GatewayAcpClient _acpClient;
  final Uri? Function(AssistantExecutionTarget target) _endpointResolver;
  final GoCoreLocator _goCoreLocator;
  final ExternalCodeAgentAcpProcessStarter _processStarter;

  Process? _localProcess;
  Uri? _localEndpoint;
  Future<Uri?>? _localEndpointFuture;

  @override
  Future<void> syncExternalProviders(
    List<ExternalCodeAgentAcpSyncedProvider> providers,
  ) async {
    final endpoint = await _ensureLocalEndpoint();
    if (endpoint == null) {
      return;
    }
    await _acpClient.request(
      method: 'xworkmate.providers.sync',
      params: <String, dynamic>{
        'providers': providers.map((item) => item.toJson()).toList(growable: false),
      },
      endpointOverride: endpoint,
    );
  }

  @override
  Future<ExternalCodeAgentAcpCapabilities> loadExternalAcpCapabilities({
    required AssistantExecutionTarget target,
    bool forceRefresh = false,
  }) async {
    final endpoint = await _resolveEndpoint(target);
    if (endpoint == null) {
      return const ExternalCodeAgentAcpCapabilities.empty();
    }
    final capabilities = await _acpClient.loadCapabilities(
      forceRefresh: forceRefresh,
      endpointOverride: endpoint,
    );
    return ExternalCodeAgentAcpCapabilities(
      singleAgent: capabilities.singleAgent,
      multiAgent: capabilities.multiAgent,
      providers: capabilities.providers,
      raw: capabilities.raw,
    );
  }

  @override
  Future<GoTaskServiceResult> executeTask(
    GoTaskServiceRequest request, {
    required void Function(GoTaskServiceUpdate update) onUpdate,
  }) async {
    final endpoint = await _resolveEndpoint(request.target);
    if (endpoint == null) {
      throw const GatewayAcpException(
        'Missing Go Agent-core endpoint',
        code: 'GO_AGENT_CORE_ENDPOINT_MISSING',
      );
    }
    var streamedText = '';
    String? completedMessage;
    final response = await _acpClient.request(
      method: request.resumeSession ? 'session.message' : 'session.start',
      params: request.toExternalAcpParams(),
      endpointOverride: endpoint,
      onNotification: (notification) {
        final update = goTaskServiceUpdateFromAcpNotification(notification);
        if (update == null) {
          return;
        }
        if (update.isDelta) {
          streamedText += update.text;
        }
        if (update.isDone && update.message.trim().isNotEmpty) {
          completedMessage = update.message.trim();
        }
        onUpdate(update);
      },
    );
    return goTaskServiceResultFromAcpResponse(
      response,
      route: request.route,
      streamedText: streamedText,
      completedMessage: completedMessage,
    );
  }

  @override
  Future<void> cancelTask({
    required AssistantExecutionTarget target,
    required String sessionId,
    required String threadId,
  }) async {
    final endpoint = await _resolveEndpoint(target);
    if (endpoint == null) {
      return;
    }
    await _acpClient.cancelSession(
      sessionId: sessionId,
      threadId: threadId,
      endpointOverride: endpoint,
    );
  }

  @override
  Future<void> closeTask({
    required AssistantExecutionTarget target,
    required String sessionId,
    required String threadId,
  }) async {
    final endpoint = await _resolveEndpoint(target);
    if (endpoint == null) {
      return;
    }
    await _acpClient.closeSession(
      sessionId: sessionId,
      threadId: threadId,
      endpointOverride: endpoint,
    );
  }

  @override
  Future<void> dispose() async {
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
  }

  Future<Uri?> _resolveEndpoint(AssistantExecutionTarget target) async {
    if (target == AssistantExecutionTarget.singleAgent ||
        target == AssistantExecutionTarget.auto) {
      return _ensureLocalEndpoint();
    }
    return _endpointResolver(target);
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
    final launch = await _goCoreLocator.locate();
    if (launch == null) {
      return null;
    }
    if (shouldBlockGoCoreLaunch(
      launch,
      isAppleHost: Platform.isIOS || Platform.isMacOS,
    )) {
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
        await _acpClient.request(
          method: 'acp.capabilities',
          params: const <String, dynamic>{},
          endpointOverride: endpoint,
        );
        return endpoint;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
    }
    await dispose();
    return null;
  }
}
