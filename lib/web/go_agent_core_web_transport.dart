import '../runtime/go_agent_core_client.dart';
import '../runtime/runtime_models.dart';
import 'web_acp_client.dart';

class GoAgentCoreWebTransport implements GoAgentCoreClient {
  const GoAgentCoreWebTransport({
    required WebAcpClient acpClient,
    required Uri? Function(AssistantExecutionTarget target) endpointResolver,
  }) : _acpClient = acpClient,
       _endpointResolver = endpointResolver;

  final WebAcpClient _acpClient;
  final Uri? Function(AssistantExecutionTarget target) _endpointResolver;

  @override
  Future<GoAgentCoreCapabilities> loadCapabilities({
    required AssistantExecutionTarget target,
    bool forceRefresh = false,
  }) async {
    final endpoint = _endpointResolver(target);
    if (endpoint == null) {
      return const GoAgentCoreCapabilities.empty();
    }
    final capabilities = await _acpClient.loadCapabilities(endpoint: endpoint);
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
    final endpoint = _endpointResolver(
      _targetForRouting(request, routingResult),
    );
    if (endpoint == null) {
      throw const WebAcpException(
        'Missing Go Agent-core endpoint',
        code: 'GO_AGENT_CORE_ENDPOINT_MISSING',
      );
    }
    var streamedText = '';
    String? completedMessage;
    final response = await _acpClient.request(
      endpoint: endpoint,
      method: request.resumeSession ? 'session.message' : 'session.start',
      params: _resolvedParams(request, routingResult),
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
    final endpoint = _endpointResolver(target);
    if (endpoint == null) {
      return;
    }
    await _acpClient.cancelSession(
      endpoint: endpoint,
      sessionId: sessionId,
      threadId: threadId,
    );
  }

  @override
  Future<void> closeSession({
    required AssistantExecutionTarget target,
    required String sessionId,
    required String threadId,
  }) async {
    final endpoint = _endpointResolver(target);
    if (endpoint == null) {
      return;
    }
    await _acpClient.request(
      endpoint: endpoint,
      method: 'session.close',
      params: <String, dynamic>{'sessionId': sessionId, 'threadId': threadId},
    );
  }

  @override
  Future<void> dispose() async {}

  Future<Map<String, dynamic>?> _resolveRouting(
    GoAgentCoreSessionRequest request,
  ) async {
    final routing = request.routing;
    if (routing == null) {
      return null;
    }
    final endpoint = _endpointResolver(AssistantExecutionTarget.singleAgent);
    if (endpoint == null) {
      return null;
    }
    try {
      final response = await _acpClient.request(
        endpoint: endpoint,
        method: 'xworkmate.routing.resolve',
        params: request.toAcpParams(),
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
