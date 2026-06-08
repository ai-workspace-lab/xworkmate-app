import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/features/workspace_management/playbook_runner.dart';
import 'package:xworkmate/features/workspace_management/server_detector.dart';
import 'package:xworkmate/features/workspace_management/ssh_executor.dart';
import 'package:xworkmate/features/workspace_management/workspace_provision_controller.dart';
import 'package:xworkmate/features/workspace_management/workspace_provision_models.dart';

void main() {
  group('workspace management models and parsers', () {
    test('default steps include the v1 provisioning flow', () {
      final steps = defaultProvisionSteps();

      expect(steps.map((step) => step.id), [
        'ssh_connect',
        'detect_env',
        'install_deps',
        'deploy_webrtc',
        'deploy_bridge',
        'config_caddy',
        'config_gateway',
        'start_services',
      ]);
      expect(steps.first.status, StepStatus.pending);
    });

    test('log buffer keeps only the newest lines', () {
      final buffer = ProvisionLogBuffer(maxLines: 2);

      buffer.add('one');
      buffer.add('two');
      buffer.add('three');

      expect(buffer.lines.length, 2);
      expect(buffer.text, contains('two'));
      expect(buffer.text, contains('three'));
      expect(buffer.text, isNot(contains('one')));
    });

    test('server detector parses command output', () {
      final info = ServerDetector.parseServerInfo('''
OS=Ubuntu 22.04.4 LTS
ARCH=x86_64
SUDO=yes
DOCKER=missing
SYSTEMD=systemd 249
CADDY=missing
ANSIBLE=missing
GIT=git version 2.34.1
DNS_OK=1
PORT_443_LISTENERS=0
PORT_443_OPEN=yes
''');

      expect(info.os, 'Ubuntu 22.04.4 LTS');
      expect(info.arch, 'x86_64');
      expect(info.sudoAvailable, isTrue);
      expect(info.ansibleMissing, isTrue);
      expect(info.gitMissing, isFalse);
      expect(info.dnsResolved, isTrue);
      expect(info.port443Open, isTrue);
      expect(info.isPort443Available, isTrue);
    });

    test('ansible parser maps human readable output to step events', () {
      final parser = AnsibleOutputParser();

      final start = parser.parseLine('TASK [Configure caddy TLS]');
      final ok = parser.parseLine('changed: [localhost]');

      expect(start?.stepId, 'config_caddy');
      expect(start?.status, StepStatus.running);
      expect(ok?.stepId, 'config_caddy');
      expect(ok?.status, StepStatus.success);
    });

    test('detection command quotes workspace domain', () {
      final command = ServerDetector.detectionCommand("a'b.example.com");

      expect(command, contains("'a'\"'\"'b.example.com'"));
      expect(command, contains('getent hosts'));
    });
  });

  group('WorkspaceProvisionController', () {
    test('detectServer moves to ready with parsed server info', () async {
      final controller = WorkspaceProvisionController(
        executor: _FakeSshExecutor(
          commandResults: [
            const SshResult(
              exitCode: 0,
              stdout: '''
OS=Ubuntu 24.04 LTS
ARCH=x86_64
SUDO=yes
DOCKER=missing
SYSTEMD=systemd 255
CADDY=missing
ANSIBLE=ansible [core 2.16]
GIT=git version 2.43.0
DNS_OK=1
PORT_443_LISTENERS=0
PORT_443_OPEN=yes
''',
              stderr: '',
            ),
          ],
        ),
      );
      addTearDown(controller.dispose);
      controller.updateForm(
        serverAddress: '203.0.113.10',
        workspaceDomain: 'workspace.example.com',
        sshKeyContent: 'key',
      );

      await controller.detectServer();

      expect(controller.phase, ProvisionPhase.ready);
      expect(controller.serverInfo?.os, 'Ubuntu 24.04 LTS');
      expect(
        controller.steps.firstWhere((step) => step.id == 'detect_env').status,
        StepStatus.success,
      );
    });

    test('createWorkspace runs playbook flow with fake SSH', () async {
      final executor = _FakeSshExecutor(
        commandResults: [
          const SshResult(exitCode: 0, stdout: 'pulled', stderr: ''),
          const SshResult(exitCode: 0, stdout: 'wrote', stderr: ''),
        ],
        streamingChunks: [
          'TASK [Install desktop packages]\nok: [localhost]\n',
          'TASK [Configure caddy TLS]\nchanged: [localhost]\n',
        ],
      );
      final controller = WorkspaceProvisionController(executor: executor);
      addTearDown(controller.dispose);
      controller.updateForm(
        serverAddress: '203.0.113.10',
        workspaceDomain: 'workspace.example.com',
        sshKeyContent: 'key',
      );
      controller.serverInfo = const ServerInfo(
        os: 'Ubuntu 22.04',
        arch: 'x86_64',
        sudoAvailable: true,
        dockerVersion: 'missing',
        systemdVersion: 'systemd 249',
        caddyVersion: 'missing',
        ansibleVersion: 'ansible [core 2.14]',
        gitVersion: 'git version 2.34.1',
        dnsAddressCount: 1,
        port443ListenerCount: 0,
        port443Open: true,
      );

      await controller.createWorkspace();

      expect(controller.phase, ProvisionPhase.success);
      expect(controller.deploymentResult?.url, 'https://workspace.example.com');
      expect(controller.deploymentResult?.bridgeToken, isNotEmpty);
      expect(executor.commands.join('\n'), contains('ansible-playbook'));
    });

    test('precheck blocks when 443 is not open', () async {
      final controller = WorkspaceProvisionController(executor: _FakeSshExecutor());
      addTearDown(controller.dispose);
      controller.updateForm(
        serverAddress: '203.0.113.10',
        workspaceDomain: 'xworkmate-bridge.example.com',
        sshKeyContent: 'key',
      );
      controller.serverInfo = const ServerInfo(
        os: 'Ubuntu 22.04',
        arch: 'x86_64',
        sudoAvailable: true,
        dockerVersion: 'missing',
        systemdVersion: 'systemd 249',
        caddyVersion: 'missing',
        ansibleVersion: 'ansible [core 2.14]',
        gitVersion: 'git version 2.34.1',
        dnsAddressCount: 1,
        port443ListenerCount: 0,
        port443Open: false,
      );

      expect(
        controller.validatePrecheckBlockingIssue(),
        contains('443'),
      );
    });

    test('precheck blocks unsupported non-Ubuntu systems', () async {
      final controller = WorkspaceProvisionController(executor: _FakeSshExecutor());
      addTearDown(controller.dispose);
      controller.updateForm(
        serverAddress: '203.0.113.10',
        workspaceDomain: 'xworkmate-bridge.example.com',
        sshKeyContent: 'key',
      );
      controller.serverInfo = const ServerInfo(
        os: 'Debian GNU/Linux 11 (bullseye)',
        arch: 'x86_64',
        sudoAvailable: true,
        dockerVersion: 'missing',
        systemdVersion: 'systemd 249',
        caddyVersion: 'missing',
        ansibleVersion: 'ansible [core 2.14]',
        gitVersion: 'git version 2.34.1',
        dnsAddressCount: 1,
        port443ListenerCount: 0,
        port443Open: true,
      );

      expect(
        controller.validatePrecheckBlockingIssue(),
        contains('Ubuntu'),
      );
    });
  });
}

class _FakeSshExecutor implements WorkspaceSshExecutor {
  _FakeSshExecutor({
    this.commandResults = const <SshResult>[],
    this.streamingChunks = const <String>[],
  });

  final List<SshResult> commandResults;
  final List<String> streamingChunks;
  final List<String> commands = <String>[];
  int _commandIndex = 0;

  @override
  Future<SshResult> execute(SshConfig config, String command) async {
    commands.add(command);
    return commandResults[_commandIndex++];
  }

  @override
  Stream<String> executeStreaming(SshConfig config, String command) async* {
    commands.add(command);
    for (final chunk in streamingChunks) {
      yield chunk;
    }
  }
}
