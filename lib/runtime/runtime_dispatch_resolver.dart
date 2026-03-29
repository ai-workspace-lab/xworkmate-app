import 'runtime_external_code_agents.dart';

class RuntimeDispatchResolution {
  const RuntimeDispatchResolution({
    required this.metadata,
    this.agentId,
    this.providerId,
    this.raw = const <String, dynamic>{},
  });

  final String? agentId;
  final String? providerId;
  final Map<String, dynamic> metadata;
  final Map<String, dynamic> raw;
}

abstract class RuntimeDispatchResolver {
  Future<String?> selectProviderId({
    required List<ExternalCodeAgentProvider> providers,
    String preferredProviderId = '',
    Iterable<String> requiredCapabilities = const <String>[],
  });

  Future<RuntimeDispatchResolution> resolveGatewayDispatch({
    required List<ExternalCodeAgentProvider> providers,
    required String preferredProviderId,
    required Iterable<String> requiredCapabilities,
    required Map<String, dynamic> nodeState,
    required Map<String, dynamic> nodeInfo,
  });

  Future<void> dispose();
}
