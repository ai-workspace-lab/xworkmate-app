import 'dart:async';
import 'dart:io';

import 'embedded_agent_launch_policy.dart';
import 'gateway_acp_client.dart';
import 'go_core.dart';
import 'multi_agent_mount_resolver.dart';
import 'runtime_models.dart';

typedef GoMultiAgentMountProcessStarter =
    Future<Process> Function(
      String executable,
      List<String> arguments, {
      Map<String, String>? environment,
      String? workingDirectory,
    });

class GoMultiAgentMountDesktopClient implements MultiAgentMountResolver {
  GoMultiAgentMountDesktopClient({
    GatewayAcpClient? acpClient,
    GoCoreLocator? goCoreLocator,
    GoMultiAgentMountProcessStarter? processStarter,
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
  final GoMultiAgentMountProcessStarter _processStarter;

  Process? _localProcess;
  Uri? _localEndpoint;
  Future<Uri?>? _localEndpointFuture;

  @override
  Future<MultiAgentConfig?> reconcile({
    required MultiAgentConfig config,
    required String aiGatewayUrl,
    String configuredCodexCliPath = '',
    required String codexHome,
    required String opencodeHome,
    required ArisMountProbe arisProbe,
  }) async {
    final endpoint = await _ensureLocalEndpoint();
    if (endpoint == null) {
      return null;
    }
    final response = await _acpClient.request(
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
      endpointOverride: endpoint,
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
    final launch = await _goCoreLocator.locate();
    if (launch == null) {
      return null;
    }
    if (shouldBlockGoCoreLaunch(
      launch,
      isAppleHost: Platform.isIOS || Platform.isMacOS,
    )) {
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
