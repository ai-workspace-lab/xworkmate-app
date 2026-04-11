import 'gateway_runtime.dart';
import 'go_task_service_client.dart';
import 'runtime_models.dart';

class DesktopGoTaskService implements GoTaskServiceClient {
  DesktopGoTaskService({
    required GatewayRuntime gateway,
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
  Future<ExternalCodeAgentAcpRoutingResolution> resolveExternalAcpRouting({
    required String taskPrompt,
    required String workingDirectory,
    required ExternalCodeAgentAcpRoutingConfig routing,
    String aiGatewayBaseUrl = '',
    String aiGatewayApiKey = '',
  }) => _acpTransport.resolveExternalAcpRouting(
    taskPrompt: taskPrompt,
    workingDirectory: workingDirectory,
    routing: routing,
    aiGatewayBaseUrl: aiGatewayBaseUrl,
    aiGatewayApiKey: aiGatewayApiKey,
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
