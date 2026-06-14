import '../../i18n/app_language.dart';
import 'server_detector.dart';
import 'ssh_executor.dart';
import 'workspace_provision_models.dart';

class PlaybookRunner {
  const PlaybookRunner(this.executor);

  static const String setupScriptUrl =
      'https://raw.githubusercontent.com/ai-workspace-lab/xworkspace-console/main/scripts/setup-ai-workspace-all-in-one.sh';

  final WorkspaceSshExecutor executor;

  Future<void> run({
    required SshConfig ssh,
    required String action,
    required String workspaceDomain,
    required String bridgeDomain,
    required String bridgeToken,
    required ServerInfo? serverInfo,
    List<WorkspaceExtraConfig>? extraConfigs,
    required void Function(String stepId, StepStatus status, String? message)
    onStepUpdate,
    required void Function(String logLine) onLog,
  }) async {
    var info = serverInfo;
    if (info == null) {
      onStepUpdate('ssh_connect', StepStatus.running, null);
      info = await ServerDetector(
        executor,
      ).detect(ssh, workspaceDomain, bridgeDomain);
      onStepUpdate('ssh_connect', StepStatus.success, null);
      onStepUpdate('detect_env', StepStatus.success, info.displaySummary);
    }

    onStepUpdate(
      'install_deps',
      StepStatus.running,
      appText('检查 curl', 'Checking curl'),
    );
    await _executeChecked(ssh, _preflightInstallCommand(ssh), onLog);
    onStepUpdate(
      'install_deps',
      StepStatus.success,
      appText('curl 已就绪', 'curl is ready'),
    );

    await _runSetupScript(
      ssh: ssh,
      command: setupScriptCommand(
        ssh: ssh,
        action: action,
        workspaceDomain: workspaceDomain,
        bridgeDomain: bridgeDomain,
        bridgeToken: bridgeToken,
        extraConfigs: extraConfigs,
      ),
      onStepUpdate: onStepUpdate,
      onLog: onLog,
    );
  }

  Future<void> _executeChecked(
    SshConfig ssh,
    String command,
    void Function(String logLine) onLog,
  ) async {
    final result = await executor.execute(ssh, command);
    for (final line in result.combinedOutput.split(RegExp(r'\r?\n'))) {
      if (line.trim().isNotEmpty) {
        onLog(line);
      }
    }
    if (!result.success) {
      throw PlaybookRunException(result.combinedOutput.trim());
    }
  }

  Future<void> _runSetupScript({
    required SshConfig ssh,
    required String command,
    required void Function(String stepId, StepStatus status, String? message)
    onStepUpdate,
    required void Function(String logLine) onLog,
  }) async {
    final parser = SetupScriptOutputParser();
    var failed = false;
    onStepUpdate(
      'deploy_webrtc',
      StepStatus.running,
      appText('执行远程安装脚本', 'Running remote setup script'),
    );
    await for (final chunk in executor.executeStreaming(ssh, command)) {
      for (final raw in chunk.split(RegExp(r'\r?\n'))) {
        final line = raw.trimRight();
        if (line.isEmpty) {
          continue;
        }
        onLog(line);
        final event = parser.parseLine(line);
        if (event != null) {
          onStepUpdate(event.stepId, event.status, event.message);
          failed = failed || event.status == StepStatus.failed;
        }
        if (line.startsWith('REMOTE_EXIT_CODE=')) {
          failed = true;
        }
      }
    }
    if (failed) {
      throw PlaybookRunException(
        appText('远程安装脚本执行失败。', 'Remote setup script failed.'),
      );
    }
    for (final id in <String>[
      'install_deps',
      'deploy_webrtc',
      'deploy_bridge',
      'config_caddy',
      'config_gateway',
      'start_services',
    ]) {
      onStepUpdate(id, StepStatus.success, null);
    }
  }

  static String _preflightInstallCommand(SshConfig ssh) {
    final apt =
        'DEBIAN_FRONTEND=noninteractive apt-get update && '
        'DEBIAN_FRONTEND=noninteractive apt-get install -y curl ca-certificates';
    if (ssh.username == 'root') {
      return 'if command -v curl >/dev/null 2>&1; then echo curl ready; else $apt; fi';
    }
    final sudoPassword = ssh.sudoPassword?.trim();
    if (sudoPassword != null && sudoPassword.isNotEmpty) {
      return 'if command -v curl >/dev/null 2>&1; then echo curl ready; '
          "else printf '%s\\n' ${shellQuote(sudoPassword)} | sudo -S sh -lc ${shellQuote(apt)}; fi";
    }
    return 'if command -v curl >/dev/null 2>&1; then echo curl ready; '
        'else sudo -n sh -lc ${shellQuote(apt)}; fi';
  }

  static String setupScriptCommand({
    required SshConfig ssh,
    required String action,
    required String workspaceDomain,
    required String bridgeDomain,
    required String bridgeToken,
    List<WorkspaceExtraConfig>? extraConfigs,
  }) {
    final domain = workspaceDomain.trim();
    final bridge = bridgeDomain.trim();
    final bridgeUrl = 'https://$bridge';
    final env = <String, String>{
      'XWORKSPACE_SETUP_ACTION': action.trim().isEmpty
          ? 'create'
          : action.trim(),
      'WORKSPACE_DOMAIN': domain,
      'XWORKSPACE_CONSOLE_DOMAIN': domain,
      'XWORKMATE_BRIDGE_DOMAIN': bridge,
      'XWORKMATE_BRIDGE_PUBLIC_BASE_URL': bridgeUrl,
      'XWORKMATE_BRIDGE_SERVICE_DOMAIN': bridge,
      'XWORKMATE_BRIDGE_SERVICE_PUBLIC_BASE_URL': bridgeUrl,
      'XWORKMATE_BRIDGE_AUTH_TOKEN': bridgeToken.trim(),
      'TOKEN': bridgeToken.trim(),
    };
    for (final config in extraConfigs ?? const <WorkspaceExtraConfig>[]) {
      final key = config.key.trim();
      final value = config.value.trim();
      if (key.isEmpty || value.isEmpty) {
        continue;
      }
      env[key] = value;
    }
    final envArgs = env.entries
        .where((entry) => _isValidEnvKey(entry.key))
        .map((entry) => '${entry.key}=${shellQuote(entry.value)}')
        .join(' ');
    final script =
        'set -o pipefail; curl -sfL ${shellQuote(setupScriptUrl)} | bash -';
    final command = 'env $envArgs bash -lc ${shellQuote(script)} 2>&1';
    if (ssh.username == 'root') {
      return command;
    }
    final sudoPassword = ssh.sudoPassword?.trim();
    if (sudoPassword != null && sudoPassword.isNotEmpty) {
      return "printf '%s\\n' ${shellQuote(sudoPassword)} | sudo -S $command";
    }
    return 'sudo -n $command';
  }

  static bool _isValidEnvKey(String key) {
    return RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(key);
  }
}

class SetupScriptStepEvent {
  const SetupScriptStepEvent(this.stepId, this.status, this.message);

  final String stepId;
  final StepStatus status;
  final String? message;
}

class SetupScriptOutputParser {
  SetupScriptStepEvent? parseLine(String line) {
    final lower = line.toLowerCase();
    if (lower.contains('error') ||
        lower.contains('failed') ||
        lower.contains('fatal')) {
      return SetupScriptStepEvent(
        stepIdForText(lower),
        StepStatus.failed,
        line,
      );
    }
    final stepId = stepIdForText(lower);
    if (lower.contains('install') ||
        lower.contains('deploy') ||
        lower.contains('config') ||
        lower.contains('start') ||
        lower.contains('enable') ||
        lower.contains('caddy') ||
        lower.contains('gateway') ||
        lower.contains('bridge') ||
        lower.contains('xworkspace')) {
      return SetupScriptStepEvent(stepId, StepStatus.running, line);
    }
    if (lower.contains('done') ||
        lower.contains('success') ||
        lower.contains('complete')) {
      return SetupScriptStepEvent(stepId, StepStatus.success, line);
    }
    return null;
  }

  static String stepIdForText(String text) {
    if (text.contains('bridge') || text.contains('acp_server')) {
      return 'deploy_bridge';
    }
    if (text.contains('caddy') ||
        text.contains('tls') ||
        text.contains('cert')) {
      return 'config_caddy';
    }
    if (text.contains('gateway') || text.contains('openclaw')) {
      return 'config_gateway';
    }
    if (text.contains('systemd') ||
        text.contains('service') ||
        text.contains('enable') ||
        text.contains('start') ||
        text.contains('restart')) {
      return 'start_services';
    }
    if (text.contains('xworkspace') ||
        text.contains('console') ||
        text.contains('desktop') ||
        text.contains('ttyd') ||
        text.contains('chrome')) {
      return 'deploy_webrtc';
    }
    return 'install_deps';
  }
}

class PlaybookRunException implements Exception {
  const PlaybookRunException(this.message);

  final String message;

  @override
  String toString() => message.isEmpty ? 'Playbook failed' : message;
}
