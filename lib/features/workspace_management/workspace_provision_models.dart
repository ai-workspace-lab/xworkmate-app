import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import '../../i18n/app_language.dart';

enum AuthMethod { password, sshKey }

enum ProvisionPhase { idle, checking, ready, running, success, failed }

enum StepStatus { pending, running, success, failed, skipped }

class ProvisionStep {
  ProvisionStep({
    required this.id,
    required this.title,
    required this.phaseGroup,
    this.status = StepStatus.pending,
    this.startedAt,
    this.finishedAt,
    this.message,
    this.errorDetail,
  });

  final String id;
  final String title;
  final String phaseGroup;
  StepStatus status;
  DateTime? startedAt;
  DateTime? finishedAt;
  String? message;
  String? errorDetail;

  ProvisionStep copy() {
    return ProvisionStep(
      id: id,
      title: title,
      phaseGroup: phaseGroup,
      status: status,
      startedAt: startedAt,
      finishedAt: finishedAt,
      message: message,
      errorDetail: errorDetail,
    );
  }
}

class ServerInfo {
  const ServerInfo({
    required this.os,
    required this.arch,
    required this.sudoAvailable,
    required this.dockerVersion,
    required this.systemdVersion,
    required this.caddyVersion,
    required this.ansibleVersion,
    required this.gitVersion,
    required this.dnsAddressCount,
    required this.port80ListenerCount,
    required this.port80Open,
    required this.port443ListenerCount,
    required this.port443Open,
    required this.bridgeDnsAddressCount,
    required this.bridgePort80ListenerCount,
    required this.bridgePort80Open,
    required this.bridgePort443ListenerCount,
    required this.bridgePort443Open,
  });

  final String os;
  final String arch;
  final bool sudoAvailable;
  final String dockerVersion;
  final String systemdVersion;
  final String caddyVersion;
  final String ansibleVersion;
  final String gitVersion;
  final int dnsAddressCount;
  final int port80ListenerCount;
  final bool port80Open;
  final int port443ListenerCount;
  final bool port443Open;
  final int bridgeDnsAddressCount;
  final int bridgePort80ListenerCount;
  final bool bridgePort80Open;
  final int bridgePort443ListenerCount;
  final bool bridgePort443Open;

  bool get gitMissing => _isMissing(gitVersion);
  bool get ansibleMissing => _isMissing(ansibleVersion);
  bool get hasMissingPrerequisites => gitMissing || ansibleMissing;
  bool get dnsResolved => dnsAddressCount > 0;
  bool get isPort80Available => port80ListenerCount == 0;
  bool get isPort443Available => port443ListenerCount == 0;
  bool get bridgeDnsResolved => bridgeDnsAddressCount > 0;
  bool get isBridgePort80Available => bridgePort80ListenerCount == 0;
  bool get isBridgePort443Available => bridgePort443ListenerCount == 0;

  String get displaySummary {
    final sudo = sudoAvailable ? 'sudo=yes' : 'sudo=no';
    return [
      if (os.trim().isNotEmpty) os.trim(),
      if (arch.trim().isNotEmpty) arch.trim(),
      sudo,
      dnsResolved ? 'dns=ok' : 'dns=missing',
      port80Open ? '80=open' : '80=blocked',
      isPort80Available ? '80=free' : '80=busy',
      port443Open ? '443=open' : '443=blocked',
      isPort443Available ? '443=free' : '443=busy',
      bridgeDnsResolved ? 'bridge-dns=ok' : 'bridge-dns=missing',
      bridgePort80Open ? 'bridge-80=open' : 'bridge-80=blocked',
      isBridgePort80Available ? 'bridge-80=free' : 'bridge-80=busy',
      bridgePort443Open ? 'bridge-443=open' : 'bridge-443=blocked',
      isBridgePort443Available ? 'bridge-443=free' : 'bridge-443=busy',
    ].join(', ');
  }

  static bool _isMissing(String value) =>
      value.trim().isEmpty || value.trim().toLowerCase() == 'missing';
}

class SshConfig {
  const SshConfig({
    required this.host,
    required this.port,
    required this.username,
    required this.authMethod,
    this.password,
    this.privateKey,
    this.privateKeyPath,
    this.sudoPassword,
    this.connectTimeout = const Duration(seconds: 10),
  });

  final String host;
  final int port;
  final String username;
  final AuthMethod authMethod;
  final String? password;
  final String? privateKey;
  final String? privateKeyPath;
  final String? sudoPassword;
  final Duration connectTimeout;

  String get targetLabel => '$username@$host:$port';
}

class WorkspaceExtraConfig {
  WorkspaceExtraConfig({
    required this.key,
    required this.value,
    this.note = '',
  });

  String key;
  String value;
  String note;

  WorkspaceExtraConfig copyWith({
    String? key,
    String? value,
    String? note,
  }) {
    return WorkspaceExtraConfig(
      key: key ?? this.key,
      value: value ?? this.value,
      note: note ?? this.note,
    );
  }
}

class SshResult {
  const SshResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;

  bool get success => exitCode == 0;
  String get combinedOutput {
    if (stderr.trim().isEmpty) {
      return stdout;
    }
    if (stdout.trim().isEmpty) {
      return stderr;
    }
    return '$stdout\n$stderr';
  }
}

class ProvisionLogBuffer {
  ProvisionLogBuffer({this.maxLines = 500});

  final int maxLines;
  final ListQueue<String> _lines = ListQueue<String>();

  void add(String line, {DateTime? now}) {
    final timestamp = (now ?? DateTime.now()).toIso8601String();
    _lines.add('[$timestamp] $line');
    while (_lines.length > maxLines) {
      _lines.removeFirst();
    }
  }

  void clear() => _lines.clear();

  List<String> get lines => List<String>.unmodifiable(_lines);

  String get text => _lines.join('\n');
}

class WorkspaceDeploymentResult {
  const WorkspaceDeploymentResult({
    required this.url,
    required this.bridgeToken,
  });

  final String url;
  final String bridgeToken;

  String get downloadText {
    return 'XWorkmate Bridge URL: $url\n'
        'Bridge Auth Token: $bridgeToken\n';
  }
}

String generateBridgeToken({int length = 32}) {
  final random = Random.secure();
  final bytes = List<int>.generate(length, (_) => random.nextInt(256));
  return base64UrlEncode(bytes).replaceAll('=', '');
}

List<ProvisionStep> defaultProvisionSteps() {
  return <ProvisionStep>[
    ProvisionStep(
      id: 'ssh_connect',
      title: appText('SSH 连接成功', 'SSH connected'),
      phaseGroup: 'detect',
    ),
    ProvisionStep(
      id: 'detect_env',
      title: appText('检测系统环境', 'Detect system environment'),
      phaseGroup: 'detect',
    ),
    ProvisionStep(
      id: 'install_deps',
      title: appText('安装基础依赖', 'Install base dependencies'),
      phaseGroup: 'system',
    ),
    ProvisionStep(
      id: 'deploy_webrtc',
      title: appText('部署 WebRTC 远端桌面', 'Deploy WebRTC remote desktop'),
      phaseGroup: 'console',
    ),
    ProvisionStep(
      id: 'deploy_bridge',
      title: appText('部署 XWorkmate Bridge', 'Deploy XWorkmate Bridge'),
      phaseGroup: 'bridge',
    ),
    ProvisionStep(
      id: 'config_caddy',
      title: appText('配置 Caddy / TLS', 'Configure Caddy / TLS'),
      phaseGroup: 'bridge',
    ),
    ProvisionStep(
      id: 'config_gateway',
      title: appText('配置 OpenClaw Gateway', 'Configure OpenClaw Gateway'),
      phaseGroup: 'bridge',
    ),
    ProvisionStep(
      id: 'start_services',
      title: appText('启动系统服务', 'Start system services'),
      phaseGroup: 'bridge',
    ),
  ];
}
