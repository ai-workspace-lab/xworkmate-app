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

  Uri? get _goCoreEndpoint => _endpointResolver(AssistantExecutionTarget.singleAgent);

  @override
  Future<void> syncProviders(List<GoAgentCoreSyncedProvider> providers) async {
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
  Future<GoAgentCoreCapabilities> loadCapabilities({
    required AssistantExecutionTarget target,
    bool forceRefresh = false,
  }) async {
    final endpoint = _goCoreEndpoint;
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
      params: request.toAcpParams(),
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
    return goAgentCoreRunResultFromResponse(
      response,
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
  Future<void> closeSession({
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
