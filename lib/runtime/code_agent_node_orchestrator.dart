import '../app/app_metadata.dart';
import 'runtime_coordinator.dart';
import 'runtime_models.dart';

/// Snapshot of the app-mediated node state sent to the gateway.
class CodeAgentNodeState {
  const CodeAgentNodeState({
    required this.selectedAgentId,
    required this.gatewayConnected,
    required this.executionTarget,
    required this.runtimeMode,
    required this.bridgeEnabled,
    required this.bridgeState,
    required this.preferredProviderId,
  });

  final String selectedAgentId;
  final bool gatewayConnected;
  final AssistantExecutionTarget executionTarget;
  final CodeAgentRuntimeMode runtimeMode;
  final bool bridgeEnabled;
  final String bridgeState;
  final String preferredProviderId;
}

/// Resolved gateway dispatch envelope for the app-mediated node.
class CodeAgentGatewayDispatch {
  const CodeAgentGatewayDispatch({required this.metadata, this.agentId});

  final String? agentId;
  final Map<String, dynamic> metadata;
}

/// Builds the gateway-facing node metadata while keeping local providers
/// behind the XWorkmate app boundary.
class CodeAgentNodeOrchestrator {
  CodeAgentNodeOrchestrator(this._runtimeCoordinator);

  final RuntimeCoordinator _runtimeCoordinator;

  Future<CodeAgentGatewayDispatch> buildGatewayDispatch(
    CodeAgentNodeState state,
  ) async {
    final resolver = _runtimeCoordinator.dispatchResolver;
    if (resolver != null) {
      final resolution = await resolver.resolveGatewayDispatch(
        providers: _runtimeCoordinator.externalCodeAgents,
        preferredProviderId: state.preferredProviderId,
        requiredCapabilities: const <String>['gateway-bridge'],
        nodeState: <String, dynamic>{
          'selectedAgentId': state.selectedAgentId,
          'gatewayConnected': state.gatewayConnected,
          'executionTarget': state.executionTarget.promptValue,
          'runtimeMode': state.runtimeMode.name,
          'bridgeEnabled': state.bridgeEnabled,
          'bridgeState': state.bridgeState,
        },
        nodeInfo: const <String, dynamic>{
          'id': 'xworkmate-app',
          'name': kSystemAppName,
          'version': kAppVersion,
        },
      );
      if (resolution.metadata.isNotEmpty) {
        return CodeAgentGatewayDispatch(
          agentId: resolution.agentId,
          metadata: resolution.metadata,
        );
      }
    }

    final provider = state.bridgeEnabled
        ? await _runtimeCoordinator.selectExternalCodeAgent(
            preferredProviderId: state.preferredProviderId,
            requiredCapabilities: const <String>['gateway-bridge'],
          )
        : null;
    final normalizedAgentId = state.selectedAgentId.trim();

    final metadata = <String, dynamic>{
      'node': <String, dynamic>{
        'id': 'xworkmate-app',
        'name': kSystemAppName,
        'version': kAppVersion,
        'kind': 'app-mediated-cooperative-node',
        'gatewayTransport': 'websocket-rpc',
      },
      'dispatch': <String, dynamic>{
        'mode': state.bridgeEnabled ? 'cooperative' : 'gateway-only',
        'executionTarget': state.executionTarget.promptValue,
      },
      'bridge': <String, dynamic>{
        'enabled': state.bridgeEnabled,
        'state': state.bridgeState,
        'gatewayConnected': state.gatewayConnected,
        'runtimeMode': state.runtimeMode.name,
        'localTransport': switch (state.runtimeMode) {
          CodeAgentRuntimeMode.externalCli => 'stdio-jsonrpc',
          CodeAgentRuntimeMode.builtIn => 'ffi-runtime',
        },
      },
      if (provider != null)
        'provider': <String, dynamic>{
          'id': provider.id,
          'name': provider.name,
          'defaultArgs': provider.defaultArgs,
          'capabilities': provider.capabilities,
        },
    };

    return CodeAgentGatewayDispatch(
      agentId: normalizedAgentId.isEmpty ? null : normalizedAgentId,
      metadata: metadata,
    );
  }
}
