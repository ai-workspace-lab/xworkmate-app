import 'package:flutter/foundation.dart';
import 'package:yaml/yaml.dart';

import '../../i18n/app_language.dart';
import 'playbook_runner.dart';
import 'server_detector.dart';
import 'ssh_executor.dart';
import 'workspace_provision_models.dart';

class WorkspaceProvisionController extends ChangeNotifier {
  WorkspaceProvisionController({
    WorkspaceSshExecutor? executor,
    String initialWorkspaceDomain = '',
  }) : executor = executor ?? const DartSshExecutor(),
       workspaceDomain = initialWorkspaceDomain {
    steps = defaultProvisionSteps();
  }

  final WorkspaceSshExecutor executor;

  String serverAddress = '';
  String workspaceDomain = '';
  String sshUsername = 'root';
  AuthMethod authMethod = AuthMethod.sshKey;
  String? sshPassword;
  String? sshKeyContent;
  String? sshKeyPath;
  int sshPort = 22;
  String? sudoPassword;
  String installPath = '/opt/xworkspace/playbooks';
  final List<WorkspaceExtraConfig> extraConfigs = <WorkspaceExtraConfig>[
    WorkspaceExtraConfig(key: 'DEEPSEEK_API_KEY', value: '', note: ''),
    WorkspaceExtraConfig(key: 'NVIDIA_API_KEY', value: '', note: ''),
    WorkspaceExtraConfig(key: 'OLLAMA_API_KEY', value: '', note: ''),
    WorkspaceExtraConfig(key: 'OPENCLAW_GATEWAY_TOKEN', value: '', note: ''),
  ];
  bool showAdvanced = false;
  bool logsExpanded = false;

  static const String redactedValue = '__redacted__';

  ProvisionPhase phase = ProvisionPhase.idle;
  late List<ProvisionStep> steps;
  final ProvisionLogBuffer logBuffer = ProvisionLogBuffer();
  ServerInfo? serverInfo;
  WorkspaceDeploymentResult? deploymentResult;
  String? errorMessage;

  bool get isBusy =>
      phase == ProvisionPhase.checking || phase == ProvisionPhase.running;

  String get bridgeDomain => deriveBridgeDomain(workspaceDomain);

  String get bridgeBaseUrl {
    final domain = bridgeDomain.trim();
    return domain.isEmpty ? '' : 'https://$domain';
  }

  bool get canSubmit {
    final hasAuth = switch (authMethod) {
      AuthMethod.password => (sshPassword ?? '').trim().isNotEmpty,
      AuthMethod.sshKey =>
        (sshKeyContent ?? '').trim().isNotEmpty ||
            (sshKeyPath ?? '').trim().isNotEmpty,
    };
    return serverAddress.trim().isNotEmpty &&
        workspaceDomain.trim().isNotEmpty &&
        sshUsername.trim().isNotEmpty &&
        sshPort > 0 &&
        hasAuth;
  }

  SshConfig sshConfig() {
    return SshConfig(
      host: serverAddress.trim(),
      port: sshPort,
      username: sshUsername.trim(),
      authMethod: authMethod,
      password: sshPassword,
      privateKey: sshKeyContent,
      privateKeyPath: sshKeyPath,
      sudoPassword: sudoPassword,
    );
  }

  Future<void> detectServer() async {
    if (!canSubmit) {
      _fail(WorkspaceProvisionValidationException());
      return;
    }
    _prepareRun(ProvisionPhase.checking);
    _setStep('ssh_connect', StepStatus.running, null);
    try {
      final detected = await ServerDetector(executor).detect(
        sshConfig(),
        workspaceDomain.trim(),
        bridgeDomain,
      );
      serverInfo = detected;
      _setStep('ssh_connect', StepStatus.success, null);
      final blockingIssue = validatePrecheckBlockingIssueFor(detected);
      _setStep(
        'detect_env',
        blockingIssue == null ? StepStatus.success : StepStatus.failed,
        blockingIssue ?? detected.displaySummary,
      );
      if (blockingIssue != null) {
        _fail(WorkspaceProvisionPrecheckException(blockingIssue));
        return;
      }
      phase = ProvisionPhase.ready;
      _appendLog(appText('服务器检测完成。', 'Server detection completed.'));
      notifyListeners();
    } catch (error) {
      _setStep('ssh_connect', StepStatus.failed, error.toString());
      _fail(error);
    }
  }

  Future<void> createWorkspace({bool installMissingPrerequisites = false}) async {
    if (!canSubmit) {
      _fail(WorkspaceProvisionValidationException());
      return;
    }
    _prepareRun(ProvisionPhase.running, keepDetection: true);
    try {
      if (serverInfo == null) {
        final detected = await ServerDetector(executor).detect(
          sshConfig(),
          workspaceDomain.trim(),
          bridgeDomain,
        );
        serverInfo = detected;
      }
      final blockingIssue = validatePrecheckBlockingIssue();
      if (blockingIssue != null) {
        _setStep('detect_env', StepStatus.failed, blockingIssue);
        throw WorkspaceProvisionPrecheckException(blockingIssue);
      }
      if (serverInfo != null) {
        _setStep('ssh_connect', StepStatus.success, null);
        _setStep('detect_env', StepStatus.success, serverInfo!.displaySummary);
      }
      final bridgeToken = ensureBridgeToken();
      await PlaybookRunner(executor).run(
        ssh: sshConfig(),
        action: 'create',
        workspaceDomain: workspaceDomain.trim(),
        bridgeDomain: bridgeDomain,
        bridgeToken: bridgeToken,
        extraConfigs: extraConfigs,
        installPath: installPath.trim(),
        installMissingPrerequisites: installMissingPrerequisites,
        serverInfo: serverInfo,
        onStepUpdate: _setStep,
        onLog: _appendLog,
      );
      for (final step in steps) {
        if (step.status == StepStatus.pending || step.status == StepStatus.running) {
          _setStep(step.id, StepStatus.success, null);
        }
      }
      phase = ProvisionPhase.success;
      deploymentResult = WorkspaceDeploymentResult(
        url: bridgeBaseUrl,
        bridgeToken: bridgeToken,
      );
      errorMessage = null;
      _appendLog(appText('工作空间创建完成。', 'Workspace creation completed.'));
      notifyListeners();
    } catch (error) {
      _fail(error);
    }
  }

  Future<void> upgradeWorkspace() async {
    _fail(
      PlaybookRunException(
        appText(
          '升级功能等待 playbooks 仓库提供 upgrade-ai-workspace.yml 后启用。',
          'Upgrade waits for upgrade-ai-workspace.yml in the playbooks repository.',
        ),
      ),
    );
  }

  void reset() {
    phase = ProvisionPhase.idle;
    steps = defaultProvisionSteps();
    logBuffer.clear();
    serverInfo = null;
    deploymentResult = null;
    errorMessage = null;
    notifyListeners();
  }

  void updateForm({
    String? serverAddress,
    String? workspaceDomain,
    String? sshUsername,
    AuthMethod? authMethod,
    String? sshPassword,
    String? sshKeyContent,
    String? sshKeyPath,
    int? sshPort,
    String? sudoPassword,
    String? installPath,
    List<WorkspaceExtraConfig>? extraConfigs,
    bool? showAdvanced,
    bool? logsExpanded,
  }) {
    this.serverAddress = serverAddress ?? this.serverAddress;
    this.workspaceDomain = workspaceDomain ?? this.workspaceDomain;
    this.sshUsername = sshUsername ?? this.sshUsername;
    this.authMethod = authMethod ?? this.authMethod;
    this.sshPassword = sshPassword ?? this.sshPassword;
    this.sshKeyContent = sshKeyContent ?? this.sshKeyContent;
    this.sshKeyPath = sshKeyPath ?? this.sshKeyPath;
    this.sshPort = sshPort ?? this.sshPort;
    this.sudoPassword = sudoPassword ?? this.sudoPassword;
    this.installPath = installPath ?? this.installPath;
    if (extraConfigs != null) {
      this.extraConfigs
        ..clear()
        ..addAll(extraConfigs.map((config) => config.copyWith()));
    }
    this.showAdvanced = showAdvanced ?? this.showAdvanced;
    this.logsExpanded = logsExpanded ?? this.logsExpanded;
    notifyListeners();
  }

  String exportYaml() {
    final buffer = StringBuffer();
    final entries = <MapEntry<String, Object?>>[
      MapEntry('server_address', serverAddress.trim()),
      MapEntry('workspace_domain', workspaceDomain.trim()),
      MapEntry('ssh_username', sshUsername.trim()),
      MapEntry('auth_method', authMethod.name),
      MapEntry('ssh_port', sshPort),
      MapEntry('install_path', installPath.trim()),
      MapEntry('show_advanced', showAdvanced),
      MapEntry('logs_expanded', logsExpanded),
      MapEntry('ssh_password', redact(sshPassword)),
      MapEntry('ssh_key_content', redact(sshKeyContent)),
      MapEntry('ssh_key_path', redact(sshKeyPath)),
      MapEntry('sudo_password', redact(sudoPassword)),
    ];
    for (final entry in entries) {
      buffer.writeln('${entry.key}: ${yamlScalar(entry.value)}');
    }
    buffer.writeln('extra_configs:');
    for (final config in extraConfigs) {
      buffer.writeln('  - key: ${yamlScalar(config.key.trim())}');
      buffer.writeln('    value: ${yamlScalar(redact(config.value))}');
      buffer.writeln('    note: ${yamlScalar(sanitizeNote(config.note))}');
    }
    return buffer.toString().trimRight();
  }

  void importYaml(String raw) {
    final decoded = loadYaml(raw);
    if (decoded is! YamlMap) {
      throw const FormatException('Invalid YAML document');
    }
    final map = <String, Object?>{};
    for (final entry in decoded.nodes.entries) {
      map['${entry.key.value}'] = entry.value.value;
    }
    updateForm(
      serverAddress: stringValue(map['server_address']),
      workspaceDomain: stringValue(map['workspace_domain']),
      sshUsername: stringValue(map['ssh_username']),
      authMethod: parseAuthMethod(map['auth_method']),
      sshPassword: secretValue(map['ssh_password'], sshPassword),
      sshKeyContent: secretValue(map['ssh_key_content'], sshKeyContent),
      sshKeyPath: secretValue(map['ssh_key_path'], sshKeyPath),
      sshPort: intValue(map['ssh_port'], sshPort),
      sudoPassword: secretValue(map['sudo_password'], sudoPassword),
      installPath: stringValue(map['install_path']),
      extraConfigs: parseExtraConfigs(map['extra_configs'], extraConfigs),
      showAdvanced: boolValue(map['show_advanced'], showAdvanced),
      logsExpanded: boolValue(map['logs_expanded'], logsExpanded),
    );
  }

  void _prepareRun(ProvisionPhase nextPhase, {bool keepDetection = false}) {
    phase = nextPhase;
    errorMessage = null;
    deploymentResult = null;
    logBuffer.clear();
    final existingInfo = keepDetection ? serverInfo : null;
    steps = defaultProvisionSteps();
    serverInfo = existingInfo;
    notifyListeners();
  }

  void _setStep(String stepId, StepStatus status, String? message) {
    final index = steps.indexWhere((step) => step.id == stepId);
    if (index < 0) {
      return;
    }
    final step = steps[index];
    step.status = status;
    step.message = message ?? step.message;
    if (status == StepStatus.running) {
      step.startedAt ??= DateTime.now();
      step.finishedAt = null;
    }
    if (status == StepStatus.success ||
        status == StepStatus.failed ||
        status == StepStatus.skipped) {
      step.finishedAt = DateTime.now();
    }
    if (status == StepStatus.failed) {
      step.errorDetail = message;
    }
    notifyListeners();
  }

  void _appendLog(String line) {
    logBuffer.add(line);
    notifyListeners();
  }

  void _fail(Object error) {
    phase = ProvisionPhase.failed;
    errorMessage = error.toString();
    _appendLog(errorMessage ?? '');
    notifyListeners();
  }

  String ensureBridgeToken() {
    deploymentResult ??= WorkspaceDeploymentResult(
      url: bridgeBaseUrl,
      bridgeToken: generateBridgeToken(),
    );
    return deploymentResult!.bridgeToken;
  }

  String? validatePrecheckBlockingIssue() {
    return validatePrecheckBlockingIssueFor(serverInfo);
  }

  String? validatePrecheckBlockingIssueFor(ServerInfo? info) {
    if (info == null) {
      return null;
    }
    final os = info.os.toLowerCase();
    if (!(os.contains('ubuntu') || os.contains('debian'))) {
      return appText(
        '当前仅支持 Ubuntu / Debian 系列，检测到 ${info.os}。',
        'Only Ubuntu / Debian family systems are supported. Detected: ${info.os}.',
      );
    }
    if (!info.bridgeDnsResolved) {
      return appText(
        '目标服务器当前无法解析 $bridgeDomain。请先在 DNS 服务商添加这条主机名的 A 记录，并确认在 VPS 上执行 dig/getent 能返回地址。',
        'The target server cannot resolve $bridgeDomain. Add an A record for this host at your DNS provider, then confirm dig/getent returns an address on the VPS.',
      );
    }
    if (!info.bridgePort443Open) {
      return appText(
        '$bridgeDomain 的 443 端口未开放，请先放通 HTTPS 访问。',
        'Port 443 is not open for $bridgeDomain. Allow HTTPS traffic first.',
      );
    }
    if (!info.isBridgePort443Available) {
      return appText(
        '$bridgeDomain 的 443 端口已被占用，请先释放。',
        'Port 443 is already in use for $bridgeDomain.',
      );
    }
    return null;
  }

  @override
  void dispose() {
    sshPassword = null;
    sshKeyContent = null;
    sudoPassword = null;
    super.dispose();
  }

  static String deriveBridgeDomain(String input) {
    final domain = input.trim().toLowerCase();
    if (domain.isEmpty) {
      return '';
    }
    if (domain.contains('bridge.') || domain.startsWith('bridge.')) {
      return domain;
    }
    return 'xworkmate-bridge.$domain';
  }

  static String redact(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? '' : redactedValue;
  }

  static String yamlScalar(Object? value) {
    if (value == null) {
      return '""';
    }
    if (value is bool || value is num) {
      return '$value';
    }
    final text = '$value';
    if (text.isEmpty) {
      return '""';
    }
    if (text == redactedValue || text.contains(RegExp(r'[:#\n\r\t]')) || text.startsWith(' ') || text.endsWith(' ')) {
      return '"${text.replaceAll('"', '\\"')}"';
    }
    return text;
  }

  static String stringValue(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text == redactedValue ? '' : text;
  }

  static String? secretValue(Object? value, String? current) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty || text == redactedValue) {
      return current;
    }
    return text;
  }

  static int intValue(Object? value, int fallback) {
    return int.tryParse(value?.toString().trim() ?? '') ?? fallback;
  }

  static bool boolValue(Object? value, bool fallback) {
    final text = value?.toString().trim().toLowerCase();
    if (text == null || text.isEmpty) {
      return fallback;
    }
    if (text == 'true' || text == 'yes' || text == '1') {
      return true;
    }
    if (text == 'false' || text == 'no' || text == '0') {
      return false;
    }
    return fallback;
  }

  static AuthMethod parseAuthMethod(Object? value) {
    final text = value?.toString().trim().toLowerCase() ?? '';
    return text == 'password' ? AuthMethod.password : AuthMethod.sshKey;
  }

  static String sanitizeNote(String note) {
    final trimmed = note.trim();
    return trimmed.length <= 20 ? trimmed : trimmed.substring(0, 20);
  }

  static List<WorkspaceExtraConfig> parseExtraConfigs(
    Object? value,
    List<WorkspaceExtraConfig> current,
  ) {
    final existing = {
      for (final config in current) config.key.trim(): config,
    };
    final parsed = <WorkspaceExtraConfig>[];
    if (value is YamlList) {
      for (final item in value) {
        if (item is! YamlMap) {
          continue;
        }
        final key = item['key']?.toString().trim() ?? '';
        if (key.isEmpty) {
          continue;
        }
        final rawValue = item['value']?.toString().trim() ?? '';
        final note = sanitizeNote(item['note']?.toString() ?? '');
        parsed.add(
          WorkspaceExtraConfig(
            key: key,
            value: rawValue == redactedValue
                ? (existing[key]?.value ?? '')
                : rawValue,
            note: note,
          ),
        );
      }
    }
    if (parsed.isNotEmpty) {
      return parsed;
    }
    return current.map((config) => config.copyWith()).toList();
  }
}

class WorkspaceProvisionPrecheckException implements Exception {
  const WorkspaceProvisionPrecheckException(this.message);

  final String message;

  @override
  String toString() => message;
}

class WorkspaceProvisionValidationException implements Exception {
  @override
  String toString() => appText(
    '请填写服务器地址、Workspace 域名和认证信息。',
    'Enter server address, workspace domain, and authentication.',
  );
}
