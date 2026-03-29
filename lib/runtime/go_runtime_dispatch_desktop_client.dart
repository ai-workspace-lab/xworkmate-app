import 'dart:async';
import 'dart:io';

import 'embedded_agent_launch_policy.dart';
import 'gateway_acp_client.dart';
import 'go_core.dart';
import 'runtime_dispatch_resolver.dart';
import 'runtime_external_code_agents.dart';

typedef GoRuntimeDispatchProcessStarter =
    Future<Process> Function(
      String executable,
      List<String> arguments, {
      Map<String, String>? environment,
      String? workingDirectory,
    });

class GoRuntimeDispatchDesktopClient implements RuntimeDispatchResolver {
  GoRuntimeDispatchDesktopClient({
    GatewayAcpClient? acpClient,
    GoCoreLocator? goCoreLocator,
    GoRuntimeDispatchProcessStarter? processStarter,
  }) : _acpClient = acpClient ?? GatewayAcpClient(endpointResolver: () => null),
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
  final GoCoreLocator _goCoreLocator;
  final GoRuntimeDispatchProcessStarter _processStarter;

  Process? _localProcess;
  Uri? _localEndpoint;
  Future<Uri?>? _localEndpointFuture;

  @override
  Future<String?> selectProviderId({
    required List<ExternalCodeAgentProvider> providers,
    String preferredProviderId = '',
    Iterable<String> requiredCapabilities = const <String>[],
  }) async {
    final endpoint = await _ensureLocalEndpoint();
    if (endpoint == null) {
      return null;
    }
    final response = await _acpClient.request(
      method: 'xworkmate.dispatch.resolve',
      params: <String, dynamic>{
        'preferredProviderId': preferredProviderId.trim(),
        'requiredCapabilities': requiredCapabilities
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList(growable: false),
        'providers': providers.map(_providerToJson).toList(growable: false),
      },
      endpointOverride: endpoint,
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
    final endpoint = await _ensureLocalEndpoint();
    if (endpoint == null) {
      return const RuntimeDispatchResolution(metadata: <String, dynamic>{});
    }
    final response = await _acpClient.request(
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
      endpointOverride: endpoint,
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
    await _acpClient.dispose();
  }

  Map<String, dynamic> _providerToJson(ExternalCodeAgentProvider provider) {
    return <String, dynamic>{
      'id': provider.id,
      'name': provider.name,
      'defaultArgs': provider.defaultArgs,
      'capabilities': provider.capabilities,
    };
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
