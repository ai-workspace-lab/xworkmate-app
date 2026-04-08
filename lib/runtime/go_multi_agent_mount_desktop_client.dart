import 'go_acp_stdio_bridge.dart';
import 'multi_agent_mount_resolver.dart';
import 'runtime_models.dart';

class GoMultiAgentMountDesktopClient implements MultiAgentMountResolver {
  GoMultiAgentMountDesktopClient({GoAcpStdioBridge? bridge})
    : _bridge = bridge ?? GoAcpStdioBridge();

  final GoAcpStdioBridge _bridge;

  @override
  Future<MultiAgentConfig?> reconcile({
    required MultiAgentConfig config,
    required String aiGatewayUrl,
    String configuredCodexCliPath = '',
    required String codexHome,
    required String opencodeHome,
    required ArisMountProbe arisProbe,
  }) async {
    final response = await _bridge.request(
      method: 'xworkmate.mounts.reconcile',
      params: <String, dynamic>{
        'config': <String, dynamic>{
          'autoSync': config.autoSync,
          'usesAris': config.usesAris,
          'managedMcpServers': config.managedMcpServers
              .map((item) => item.toJson())
              .toList(growable: false),
        },
        'aiGatewayUrl': aiGatewayUrl.trim(),
        'configuredCodexCliPath': configuredCodexCliPath.trim(),
        'codexHome': codexHome.trim(),
        'opencodeHome': opencodeHome.trim(),
        'aris': arisProbe.toJson(),
      },
    );
    final result = _castMap(response['result']);
    final rawTargets = result['mountTargets'];
    final mountTargets = rawTargets is List
        ? rawTargets
              .whereType<Map>()
              .map(
                (item) => ManagedMountTargetState.fromJson(
                  item.cast<String, dynamic>(),
                ),
              )
              .toList(growable: false)
        : config.mountTargets;
    return config.copyWith(
      mountTargets: mountTargets,
      arisBundleVersion:
          result['arisBundleVersion']?.toString().trim().isNotEmpty == true
          ? result['arisBundleVersion'].toString().trim()
          : config.arisBundleVersion,
      arisCompatStatus:
          result['arisCompatStatus']?.toString().trim().isNotEmpty == true
          ? result['arisCompatStatus'].toString().trim()
          : config.arisCompatStatus,
    );
  }

  @override
  Future<void> dispose() => _bridge.dispose();

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
