import '../runtime/go_task_service_client.dart';
import '../runtime/runtime_models.dart';
import 'web_acp_client.dart';

class ExternalCodeAgentAcpWebTransport implements ExternalCodeAgentAcpTransport {
  const ExternalCodeAgentAcpWebTransport({
    required WebAcpClient acpClient,
    required Uri? Function(AssistantExecutionTarget target) endpointResolver,
  }) : _acpClient = acpClient,
       _endpointResolver = endpointResolver;

  final WebAcpClient _acpClient;
  final Uri? Function(AssistantExecutionTarget target) _endpointResolver;

  Uri? get _goCoreEndpoint => _endpointResolver(AssistantExecutionTarget.singleAgent);

  @override
  Future<void> syncExternalProviders(
    List<ExternalCodeAgentAcpSyncedProvider> providers,
  ) async {
    final endpoint = _goCoreEndpoint;
    if (endpoint == null) {
      return;
    }
    await _acpClient.request(
      endpoint: endpoint,
      method: 'xworkmate.providers.sync',
      params: <String, dynamic>{
        'providers': providers.map((item) => item.toJson()).toList(growable: false),
      },
    );
  }

  @override
  Future<ExternalCodeAgentAcpCapabilities> loadExternalAcpCapabilities({
    required AssistantExecutionTarget target,
    bool forceRefresh = false,
  }) async {
    final endpoint = _goCoreEndpoint;
    if (endpoint == null) {
      return const ExternalCodeAgentAcpCapabilities.empty();
    }
    final capabilities = await _acpClient.loadCapabilities(endpoint: endpoint);
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
    final endpoint = _goCoreEndpoint;
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
      params: request.toExternalAcpParams(),
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
    final endpoint = _goCoreEndpoint;
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
  Future<void> closeTask({
    required AssistantExecutionTarget target,
    required String sessionId,
    required String threadId,
  }) async {
    final endpoint = _goCoreEndpoint;
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
}
