import 'dart:async';
import 'dart:io';

import 'embedded_agent_launch_policy.dart';
import 'gateway_acp_client.dart';
import 'go_agent_core_client.dart';
import 'go_core.dart';
import 'runtime_models.dart';

typedef GoAgentCoreProcessStarter =
    Future<Process> Function(
      String executable,
      List<String> arguments, {
      Map<String, String>? environment,
      String? workingDirectory,
    });

class GoAgentCoreDesktopTransport implements GoAgentCoreClient {
  GoAgentCoreDesktopTransport({
    required GatewayAcpClient acpClient,
    required Uri? Function(AssistantExecutionTarget target) endpointResolver,
    GoCoreLocator? goCoreLocator,
    GoAgentCoreProcessStarter? processStarter,
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
  final GoAgentCoreProcessStarter _processStarter;

  Process? _localProcess;
  Uri? _localEndpoint;
  Future<Uri?>? _localEndpointFuture;

  @override
  Future<GoAgentCoreCapabilities> loadCapabilities({
    required AssistantExecutionTarget target,
    bool forceRefresh = false,
  }) async {
    final endpoint = await _resolveEndpoint(target);
    if (endpoint == null) {
      return const GoAgentCoreCapabilities.empty();
    }
    final capabilities = await _acpClient.loadCapabilities(
      forceRefresh: forceRefresh,
      endpointOverride: endpoint,
    );
    return GoAgentCoreCapabilities(
      singleAgent: capabilities.singleAgent,
      multiAgent: capabilities.multiAgent,
      providers: capabilities.providers,
      raw: capabilities.raw,
    );
  }

  @override
  Future<GoAgentCoreRunResult> executeSession(
    GoAgentCoreSessionRequest request, {
    required void Function(GoAgentCoreSessionUpdate update) onUpdate,
  }) async {
    final routingResult = await _resolveRouting(request);
    final endpoint = await _resolveEndpoint(
      _targetForRouting(request, routingResult),
    );
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
      params: _resolvedParams(request, routingResult),
      endpointOverride: endpoint,
      onNotification: (notification) {
        final update = goAgentCoreUpdateFromNotification(notification);
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
    final mergedResponse = routingResult == null
        ? response
        : mergeGoAgentCoreResponseResult(response, routingResult);
    return goAgentCoreRunResultFromResponse(
      mergedResponse,
      streamedText: streamedText,
      completedMessage: completedMessage,
    );
  }

  @override
  Future<void> cancelSession({
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
  Future<void> closeSession({
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
    if (target == AssistantExecutionTarget.singleAgent) {
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

  Future<Map<String, dynamic>?> _resolveRouting(
    GoAgentCoreSessionRequest request,
  ) async {
    final routing = request.routing;
    if (routing == null) {
      return null;
    }
    final endpoint = await _ensureLocalEndpoint();
    if (endpoint == null) {
      return null;
    }
    try {
      final response = await _acpClient.request(
        method: 'xworkmate.routing.resolve',
        params: request.toAcpParams(),
        endpointOverride: endpoint,
      );
      return _castRoutingResult(response['result']);
    } on Object {
      return null;
    }
  }

  Map<String, dynamic> _resolvedParams(
    GoAgentCoreSessionRequest request,
    Map<String, dynamic>? routingResult,
  ) {
    final params = Map<String, dynamic>.from(request.toAcpParams());
    if (routingResult == null || routingResult.isEmpty) {
      return params;
    }
    final resolvedExecutionTarget =
        routingResult['resolvedExecutionTarget']?.toString().trim() ?? '';
    final resolvedEndpointTarget =
        routingResult['resolvedEndpointTarget']?.toString().trim() ?? '';
    final resolvedProviderId =
        routingResult['resolvedProviderId']?.toString().trim() ?? '';
    final resolvedModel =
        routingResult['resolvedModel']?.toString().trim() ?? '';
    final resolvedSkills = _castStringList(routingResult['resolvedSkills']);

    if (resolvedExecutionTarget.isNotEmpty) {
      params['mode'] = resolvedExecutionTarget;
      params['resolvedExecutionTarget'] = resolvedExecutionTarget;
    }
    if (resolvedEndpointTarget.isNotEmpty) {
      params['resolvedEndpointTarget'] = resolvedEndpointTarget;
      if (resolvedExecutionTarget == 'gateway-chat') {
        params['executionTarget'] = resolvedEndpointTarget;
      }
    }
    if (resolvedProviderId.isNotEmpty) {
      params['provider'] = resolvedProviderId;
      params['resolvedProviderId'] = resolvedProviderId;
    }
    if (resolvedModel.isNotEmpty) {
      params['model'] = resolvedModel;
      params['resolvedModel'] = resolvedModel;
    }
    if (resolvedSkills.isNotEmpty) {
      params['selectedSkills'] = resolvedSkills;
      params['resolvedSkills'] = resolvedSkills;
    }
    for (final key in <String>[
      'skillResolutionSource',
      'memorySources',
      'skillCandidates',
      'needsSkillInstall',
    ]) {
      if (routingResult.containsKey(key)) {
        params[key] = routingResult[key];
      }
    }
    return params;
  }

  AssistantExecutionTarget _targetForRouting(
    GoAgentCoreSessionRequest request,
    Map<String, dynamic>? routingResult,
  ) {
    if (routingResult == null || routingResult.isEmpty) {
      return request.target;
    }
    final resolvedExecutionTarget =
        routingResult['resolvedExecutionTarget']?.toString().trim() ?? '';
    if (resolvedExecutionTarget == 'gateway-chat') {
      final endpointTarget =
          routingResult['resolvedEndpointTarget']?.toString().trim() ?? '';
      return switch (endpointTarget) {
        'local' => AssistantExecutionTarget.local,
        'remote' => AssistantExecutionTarget.remote,
        _ => request.target,
      };
    }
    return AssistantExecutionTarget.singleAgent;
  }

  Map<String, dynamic> _castRoutingResult(Object? raw) {
    if (raw is Map<String, dynamic>) {
      return raw;
    }
    if (raw is Map) {
      return raw.cast<String, dynamic>();
    }
    return const <String, dynamic>{};
  }

  List<String> _castStringList(Object? raw) {
    if (raw is! List) {
      return const <String>[];
    }
    return raw
        .map((item) => item?.toString().trim() ?? '')
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
}
