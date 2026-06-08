import 'dart:async';

import '../../i18n/app_language.dart';
import 'server_detector.dart';
import 'ssh_executor.dart';
import 'workspace_provision_models.dart';

class PlaybookRunner {
  const PlaybookRunner(this.executor);

  static const String playbookRepoUrl = 'https://github.com/x-evor/playbooks.git';
  static const String createPlaybook = 'setup-ai-workspace-all-in-one.yml';
  static const String upgradePlaybook = 'upgrade-ai-workspace.yml';

  final WorkspaceSshExecutor executor;

  Future<void> run({
    required SshConfig ssh,
    required String action,
    required String workspaceDomain,
    required String bridgeDomain,
    required String bridgeToken,
    required String installPath,
    required bool installMissingPrerequisites,
    required ServerInfo? serverInfo,
    List<WorkspaceExtraConfig>? extraConfigs,
    required void Function(String stepId, StepStatus status, String? message)
    onStepUpdate,
    required void Function(String logLine) onLog,
  }) async {
    if (action == 'upgrade') {
      throw PlaybookRunException(
        appText(
          'playbooks 仓库尚未提供 $upgradePlaybook。',
          'The playbooks repository does not provide $upgradePlaybook yet.',
        ),
      );
    }

    var info = serverInfo;
    if (info == null) {
      onStepUpdate('ssh_connect', StepStatus.running, null);
      info = await ServerDetector(executor).detect(
        ssh,
        workspaceDomain,
        bridgeDomain,
      );
      onStepUpdate('ssh_connect', StepStatus.success, null);
      onStepUpdate('detect_env', StepStatus.success, info.displaySummary);
    }

    if (info.hasMissingPrerequisites) {
      if (!installMissingPrerequisites) {
        throw PlaybookRunException(
          appText(
            '目标服务器缺少 git 或 ansible。',
            'The target server is missing git or ansible.',
          ),
        );
      }
      onStepUpdate('install_deps', StepStatus.running, appText('安装 git/ansible', 'Installing git/ansible'));
      await _executeChecked(ssh, _preflightInstallCommand(ssh), onLog);
      onStepUpdate('install_deps', StepStatus.success, appText('基础依赖已安装', 'Base dependencies installed'));
    }

    onStepUpdate('install_deps', StepStatus.running, appText('拉取 playbooks', 'Fetching playbooks'));
    await _executeChecked(ssh, _cloneOrPullCommand(installPath), onLog);

    final inventoryPath = '/tmp/xworkspace-inventory.ini';
    final varsPath = '/tmp/xworkspace-vars.yml';
    await _executeChecked(
      ssh,
      _writeInventoryAndVarsCommand(
        inventoryPath: inventoryPath,
        varsPath: varsPath,
        workspaceDomain: workspaceDomain,
        bridgeDomain: bridgeDomain,
        bridgeToken: bridgeToken,
        extraConfigs: extraConfigs,
      ),
      onLog,
    );

    await _runAnsible(
      ssh: ssh,
      command: _ansibleCommand(
        installPath: installPath,
        inventoryPath: inventoryPath,
        varsPath: varsPath,
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

  Future<void> _runAnsible({
    required SshConfig ssh,
    required String command,
    required void Function(String stepId, StepStatus status, String? message)
    onStepUpdate,
    required void Function(String logLine) onLog,
  }) async {
    final parser = AnsibleOutputParser();
    var failed = false;
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
      throw PlaybookRunException(appText('Playbook 执行失败。', 'Playbook execution failed.'));
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
    final apt = 'DEBIAN_FRONTEND=noninteractive apt-get update && '
        'DEBIAN_FRONTEND=noninteractive apt-get install -y git ansible';
    if (ssh.username == 'root') {
      return apt;
    }
    final sudoPassword = ssh.sudoPassword?.trim();
    if (sudoPassword != null && sudoPassword.isNotEmpty) {
      return "printf '%s\\n' ${shellQuote(sudoPassword)} | sudo -S sh -lc ${shellQuote(apt)}";
    }
    return 'sudo -n sh -lc ${shellQuote(apt)}';
  }

  static String _cloneOrPullCommand(String installPath) {
    final path = shellQuote(installPath.trim());
    final repo = shellQuote(playbookRepoUrl);
    return 'mkdir -p $path && cd $path && '
        'if [ -d .git ]; then git pull --ff-only origin main; '
        'else git clone $repo .; fi';
  }

  static String _writeInventoryAndVarsCommand({
    required String inventoryPath,
    required String varsPath,
    required String workspaceDomain,
    required String bridgeDomain,
    required String bridgeToken,
    List<WorkspaceExtraConfig>? extraConfigs,
  }) {
    final domain = workspaceDomain.trim();
    final bridge = bridgeDomain.trim();
    final bridgeUrl = 'https://$bridge';
    final extraEnvVars = <String>[];
    for (final config in extraConfigs ?? const <WorkspaceExtraConfig>[]) {
      final key = config.key.trim();
      final value = config.value.trim();
      if (key.isEmpty || value.isEmpty) {
        continue;
      }
      extraEnvVars.add('$key: ${shellQuote(value)}');
      final note = config.note.trim();
      if (note.isNotEmpty) {
        extraEnvVars.add('# ${note.length > 20 ? note.substring(0, 20) : note}');
      }
    }
    final extraEnvBlock =
        extraEnvVars.isEmpty ? '' : '${extraEnvVars.join('\n')}\n';
    return '''
cat > ${shellQuote(inventoryPath)} <<'EOF'
[all]
localhost ansible_connection=local
EOF
cat > ${shellQuote(varsPath)} <<'EOF'
workspace_domain: $domain
xworkmate_bridge_domain: $bridge
xworkmate_bridge_public_base_url: $bridgeUrl
xworkmate_bridge_service_domain: $bridge
xworkmate_bridge_service_public_base_url: $bridgeUrl
xworkmate_bridge_auth_token: ${bridgeToken.trim()}
${extraEnvBlock}EOF
''';
  }

  static String _ansibleCommand({
    required String installPath,
    required String inventoryPath,
    required String varsPath,
  }) {
    return 'cd ${shellQuote(installPath.trim())} && '
        'ANSIBLE_FORCE_COLOR=0 ansible-playbook '
        '-i ${shellQuote(inventoryPath)} '
        '${shellQuote(createPlaybook)} '
        '-e @${shellQuote(varsPath)} 2>&1';
  }
}

class AnsibleStepEvent {
  const AnsibleStepEvent(this.stepId, this.status, this.message);

  final String stepId;
  final StepStatus status;
  final String? message;
}

class AnsibleOutputParser {
  String? _currentStepId;
  String? _currentTask;

  AnsibleStepEvent? parseLine(String line) {
    final taskMatch = RegExp(r'^TASK \[(.+?)\]').firstMatch(line);
    if (taskMatch != null) {
      _currentTask = taskMatch.group(1);
      _currentStepId = stepIdForTask(_currentTask ?? '');
      return AnsibleStepEvent(_currentStepId!, StepStatus.running, _currentTask);
    }
    if (_currentStepId == null) {
      return null;
    }
    final lower = line.toLowerCase();
    if (lower.startsWith('fatal:') || lower.contains(' failed=')) {
      return AnsibleStepEvent(_currentStepId!, StepStatus.failed, line);
    }
    if (lower.startsWith('ok:') || lower.startsWith('changed:')) {
      return AnsibleStepEvent(_currentStepId!, StepStatus.success, _currentTask);
    }
    if (lower.startsWith('skipping:')) {
      return AnsibleStepEvent(_currentStepId!, StepStatus.skipped, _currentTask);
    }
    return null;
  }

  static String stepIdForTask(String task) {
    final text = task.toLowerCase();
    if (text.contains('bridge') || text.contains('acp_server')) {
      return 'deploy_bridge';
    }
    if (text.contains('caddy') || text.contains('tls') || text.contains('cert')) {
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
