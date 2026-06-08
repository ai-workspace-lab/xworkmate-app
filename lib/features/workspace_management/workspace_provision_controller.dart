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
  String? deepseekApiKey;
  String? nvidiaApiKey;
  String? ollamaApiKey;
  String? openclawGatewayToken;
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
        deepseekApiKey: deepseekApiKey,
        nvidiaApiKey: nvidiaApiKey,
        ollamaApiKey: ollamaApiKey,
        openclawGatewayToken: openclawGatewayToken,
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
    String? deepseekApiKey,
    String? nvidiaApiKey,
    String? ollamaApiKey,
    String? openclawGatewayToken,
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
    this.deepseekApiKey = deepseekApiKey ?? this.deepseekApiKey;
    this.nvidiaApiKey = nvidiaApiKey ?? this.nvidiaApiKey;
    this.ollamaApiKey = ollamaApiKey ?? this.ollamaApiKey;
    this.openclawGatewayToken =
        openclawGatewayToken ?? this.openclawGatewayToken;
    this.showAdvanced = showAdvanced ?? this.showAdvanced;
    this.logsExpanded = logsExpanded ?? this.logsExpanded;
    notifyListeners();
  }

  String exportYaml() {
    final data = <String, Object?>{
      'server_address': serverAddress.trim(),
      'workspace_domain': workspaceDomain.trim(),
      'ssh_username': sshUsername.trim(),
      'auth_method': authMethod.name,
      'ssh_port': sshPort,
      'install_path': installPath.trim(),
      'show_advanced': showAdvanced,
      'logs_expanded': logsExpanded,
      'ssh_password': redact(sshPassword),
      'ssh_key_content': redact(sshKeyContent),
      'ssh_key_path': redact(sshKeyPath),
      'sudo_password': redact(sudoPassword),
      'deepseek_api_key': redact(deepseekApiKey),
      'nvidia_api_key': redact(nvidiaApiKey),
      'ollama_api_key': redact(ollamaApiKey),
      'openclaw_gateway_token': redact(openclawGatewayToken),
    };
    final buffer = StringBuffer();
    for (final entry in data.entries) {
      buffer.writeln('${entry.key}: ${yamlScalar(entry.value)}');
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
      deepseekApiKey: secretValue(map['deepseek_api_key'], deepseekApiKey),
      nvidiaApiKey: secretValue(map['nvidia_api_key'], nvidiaApiKey),
      ollamaApiKey: secretValue(map['ollama_api_key'], ollamaApiKey),
      openclawGatewayToken: secretValue(
        map['openclaw_gateway_token'],
        openclawGatewayToken,
      ),
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
        '部署前需要先把 $bridgeDomain 做好 DNS 解析。',
        'Configure DNS for $bridgeDomain before deploying.',
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
    deepseekApiKey = null;
    nvidiaApiKey = null;
    ollamaApiKey = null;
    openclawGatewayToken = null;
    super.dispose();
  }

  static String deriveBridgeDomain(String input) {
    final domain = input.trim().toLowerCase();
    if (domain.isEmpty) {
      return '';
    }
    if (domain.startsWith('xworkmate-bridge.')) {
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
