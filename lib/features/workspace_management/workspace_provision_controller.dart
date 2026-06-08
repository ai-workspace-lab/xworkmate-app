import 'package:flutter/foundation.dart';

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
  bool showAdvanced = false;
  bool logsExpanded = false;

  ProvisionPhase phase = ProvisionPhase.idle;
  late List<ProvisionStep> steps;
  final ProvisionLogBuffer logBuffer = ProvisionLogBuffer();
  ServerInfo? serverInfo;
  WorkspaceDeploymentResult? deploymentResult;
  String? errorMessage;

  bool get isBusy =>
      phase == ProvisionPhase.checking || phase == ProvisionPhase.running;

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
        bridgeToken: bridgeToken,
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
        url: 'https://${workspaceDomain.trim()}',
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
    this.showAdvanced = showAdvanced ?? this.showAdvanced;
    this.logsExpanded = logsExpanded ?? this.logsExpanded;
    notifyListeners();
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
      url: 'https://${workspaceDomain.trim()}',
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
    if (!info.dnsResolved) {
      return appText(
        '部署前需要先把 ${workspaceDomain.trim()} 做好 DNS 解析。',
        'Configure DNS for ${workspaceDomain.trim()} before deploying.',
      );
    }
    if (!info.port443Open) {
      return appText(
        '目标服务器的 443 端口未开放，请先放通 HTTPS 访问。',
        'Port 443 is not open on the target server. Allow HTTPS traffic first.',
      );
    }
    if (!info.isPort443Available) {
      return appText(
        '目标服务器的 443 端口已被占用，请先释放。',
        'Port 443 is already in use on the target server.',
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
