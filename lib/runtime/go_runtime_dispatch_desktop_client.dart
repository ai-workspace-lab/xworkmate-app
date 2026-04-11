import 'gateway_acp_client.dart';
import 'runtime_dispatch_resolver.dart';
import 'runtime_external_code_agents.dart';

class GoRuntimeDispatchDesktopClient implements RuntimeDispatchResolver {
  GoRuntimeDispatchDesktopClient({
    required GatewayAcpClient client,
    required Uri? Function() endpointResolver,
  }) : _client = client,
       _endpointResolver = endpointResolver;

  final GatewayAcpClient _client;
  final Uri? Function() _endpointResolver;

  @override
  Future<String?> selectProviderId({
    required List<ExternalCodeAgentProvider> providers,
    String preferredProviderId = '',
    Iterable<String> requiredCapabilities = const <String>[],
  }) async {
    final response = await _client.request(
      method: 'xworkmate.dispatch.resolve',
      params: <String, dynamic>{
        'preferredProviderId': preferredProviderId.trim(),
        'requiredCapabilities': requiredCapabilities
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList(growable: false),
        'providers': providers.map(_providerToJson).toList(growable: false),
      },
      endpointOverride: _endpointResolver(),
    );
    final result = _castMap(response['result']);
    return result['providerId']?.toString().trim().isNotEmpty == true
        ? result['providerId'].toString().trim()
        : null;
  }

  @override
  Future<RuntimeDispatchResolution> resolveGatewayDispatch({
    required List<ExternalCodeAgentProvider> providers,
    required String preferredProviderId,
    required Iterable<String> requiredCapabilities,
    required Map<String, dynamic> nodeState,
    required Map<String, dynamic> nodeInfo,
  }) async {
    final response = await _client.request(
      method: 'xworkmate.dispatch.resolve',
      params: <String, dynamic>{
        'preferredProviderId': preferredProviderId.trim(),
        'requiredCapabilities': requiredCapabilities
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList(growable: false),
        'providers': providers.map(_providerToJson).toList(growable: false),
        'nodeState': nodeState,
        'nodeInfo': nodeInfo,
      },
      endpointOverride: _endpointResolver(),
    );
    final result = _castMap(response['result']);
    return RuntimeDispatchResolution(
      agentId: result['agentId']?.toString().trim().isNotEmpty == true
          ? result['agentId'].toString().trim()
          : null,
      providerId: result['providerId']?.toString().trim().isNotEmpty == true
          ? result['providerId'].toString().trim()
          : null,
      metadata: _castMap(result['metadata']),
      raw: result,
    );
  }

  @override
  Future<void> dispose() => _client.dispose();

  Map<String, dynamic> _providerToJson(ExternalCodeAgentProvider provider) {
    return <String, dynamic>{
      'id': provider.id,
      'name': provider.name,
      'defaultArgs': provider.defaultArgs,
      'capabilities': provider.capabilities,
    };
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
