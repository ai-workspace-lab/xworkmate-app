import '../runtime/go_task_service_client.dart';
import '../runtime/runtime_models.dart';
import 'web_relay_gateway_client.dart';

class WebGoTaskService implements GoTaskServiceClient {
  WebGoTaskService({
    required WebRelayGatewayClient relayClient,
    required ExternalCodeAgentAcpTransport acpTransport,
  }) : _acpTransport = acpTransport;

  final ExternalCodeAgentAcpTransport _acpTransport;

  @override
  Future<void> syncExternalProviders(
    List<ExternalCodeAgentAcpSyncedProvider> providers,
  ) => _acpTransport.syncExternalProviders(providers);

  @override
  Future<ExternalCodeAgentAcpCapabilities> loadExternalAcpCapabilities({
    required AssistantExecutionTarget target,
    bool forceRefresh = false,
  }) => _acpTransport.loadExternalAcpCapabilities(
    target: target,
    forceRefresh: forceRefresh,
  );

  @override
  Future<GoTaskServiceResult> executeTask(
    GoTaskServiceRequest request, {
    required void Function(GoTaskServiceUpdate update) onUpdate,
  }) => _acpTransport.executeTask(request, onUpdate: onUpdate);

  @override
  Future<void> cancelTask({
    required GoTaskServiceRoute route,
    required AssistantExecutionTarget target,
    required String sessionId,
    required String threadId,
  }) => _acpTransport.cancelTask(
    target: target,
    sessionId: sessionId,
    threadId: threadId,
  );

  @override
  Future<void> closeTask({
    required GoTaskServiceRoute route,
    required AssistantExecutionTarget target,
    required String sessionId,
    required String threadId,
  }) => _acpTransport.closeTask(
    target: target,
    sessionId: sessionId,
    threadId: threadId,
  );

  @override
  Future<void> dispose() async {
    await _acpTransport.dispose();
  }
}
