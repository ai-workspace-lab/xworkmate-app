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
PORT_80_LISTENERS=0
PORT_443_LISTENERS=0
PORT_80_OPEN=yes
PORT_443_OPEN=yes
BRIDGE_DNS_OK=1
BRIDGE_PORT_80_LISTENERS=0
BRIDGE_PORT_443_LISTENERS=0
BRIDGE_PORT_80_OPEN=yes
BRIDGE_PORT_443_OPEN=yes
''');

      expect(info.os, 'Ubuntu 22.04.4 LTS');
      expect(info.arch, 'x86_64');
      expect(info.sudoAvailable, isTrue);
      expect(info.ansibleMissing, isTrue);
      expect(info.gitMissing, isFalse);
      expect(info.dnsResolved, isTrue);
      expect(info.port80Open, isTrue);
      expect(info.isPort80Available, isTrue);
      expect(info.port443Open, isTrue);
      expect(info.isPort443Available, isTrue);
      expect(info.bridgeDnsResolved, isTrue);
      expect(info.bridgePort80Open, isTrue);
      expect(info.isBridgePort80Available, isTrue);
      expect(info.bridgePort443Open, isTrue);
      expect(info.isBridgePort443Available, isTrue);
      expect(info.displaySummary, contains('sudo 可用'));
      expect(info.displaySummary, contains('主域名 DNS 已解析'));
      expect(info.displaySummary, contains('桥接 443 端口当前空闲'));
    });

    test('setup script command passes env to remote bash', () {
      final command = PlaybookRunner.setupScriptCommand(
        ssh: const SshConfig(
          host: '203.0.113.10',
          port: 22,
          username: 'root',
          authMethod: AuthMethod.sshKey,
        ),
        action: 'create',
        workspaceDomain: 'workspace.example.com',
        bridgeDomain: 'xworkmate-bridge.workspace.example.com',
        bridgeToken: "tok'en",
        extraConfigs: [
          WorkspaceExtraConfig(
            key: 'AI_WORKSPACE_SECURITY_LEVEL',
            value: 'strict',
          ),
          WorkspaceExtraConfig(
            key: 'XWORKSPACE_CONSOLE_ENABLE_XRDP',
            value: 'true',
          ),
        ],
      );

      expect(command, contains('curl -sfL'));
      expect(command, contains(PlaybookRunner.setupScriptUrl));
      expect(command, contains('AI_WORKSPACE_SECURITY_LEVEL='));
      expect(command, contains('XWORKSPACE_CONSOLE_ENABLE_XRDP='));
      expect(command, contains('TOKEN='));
      expect(command, contains("'tok'\"'\"'en'"));
      expect(command, contains('bash -lc'));
    });

    test('detection command quotes workspace domain', () {
      final command = ServerDetector.detectionCommand(
        "a'b.example.com",
        'xworkmate-bridge.a\'b.example.com',
      );

      expect(command, contains("'a'\"'\"'b.example.com'"));
      expect(command, contains('xworkmate-bridge.a'));
      expect(command, contains('getent hosts'));
    });

    test('bridge domain uses user input when already a bridge host', () {
      expect(
        WorkspaceProvisionController.deriveBridgeDomain(
          'acp-bridge.onwalk.net',
        ),
        'acp-bridge.onwalk.net',
      );
    });

    test('exported yaml redacts sensitive values', () {
      final controller = WorkspaceProvisionController();
      addTearDown(controller.dispose);
      controller.updateForm(
        serverAddress: '203.0.113.10',
        workspaceDomain: 'onwalk.net',
        sshUsername: 'root',
        sshPassword: 'ssh-secret',
        showAdvanced: true,
        extraConfigs: [
          WorkspaceExtraConfig(
            key: 'DEEPSEEK_API_KEY',
            value: 'deepseek-secret',
            note: '深度搜索',
          ),
          WorkspaceExtraConfig(
            key: 'OPENCLAW_GATEWAY_TOKEN',
            value: 'gateway-secret',
            note: 'OpenClaw',
          ),
        ],
      );

      final yaml = controller.exportYaml();

      expect(yaml, contains('server_address: 203.0.113.10'));
      expect(yaml, contains('ssh_password_fixture: "example"'));
      expect(yaml, contains('extra_configs:'));
      expect(yaml, contains('key: DEEPSEEK_API_KEY'));
      expect(yaml, contains('value: "__redacted__"'));
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
PORT_80_LISTENERS=0
PORT_443_LISTENERS=0
PORT_80_OPEN=yes
PORT_443_OPEN=yes
BRIDGE_DNS_OK=1
BRIDGE_PORT_80_LISTENERS=0
BRIDGE_PORT_443_LISTENERS=0
BRIDGE_PORT_80_OPEN=yes
BRIDGE_PORT_443_OPEN=yes
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

    test('createWorkspace runs remote setup script with fake SSH', () async {
      final executor = _FakeSshExecutor(
        commandResults: [
          const SshResult(exitCode: 0, stdout: 'curl ready', stderr: ''),
          const SshResult(
            exitCode: 0,
            stdout: '''
SERVICE_CADDY=active
SERVICE_XWORKMATE_BRIDGE=active
SERVICE_OPENCLAW_GATEWAY=active
SERVICE_HERMES_GATEWAY=active
''',
            stderr: '',
          ),
        ],
        streamingChunks: [
          'Installing desktop packages\n',
          'Configuring caddy TLS\n',
        ],
      );
      final controller = WorkspaceProvisionController(
        executor: executor,
        externalPortProbe: (_) async {},
      );
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
        port80ListenerCount: 0,
        port80Open: true,
        port443ListenerCount: 0,
        port443Open: true,
        bridgeDnsAddressCount: 1,
        bridgePort80ListenerCount: 0,
        bridgePort80Open: true,
        bridgePort443ListenerCount: 0,
        bridgePort443Open: true,
      );

      await controller.createWorkspace();

      expect(controller.phase, ProvisionPhase.success);
      expect(
        controller.deploymentResult?.url,
        'https://xworkmate-bridge.workspace.example.com',
      );
      expect(controller.deploymentResult?.bridgeToken, isNotEmpty);
      expect(executor.commands.join('\n'), contains('curl -sfL'));
      expect(
        executor.commands.join('\n'),
        contains('setup-ai-workspace-all-in-one.sh'),
      );
      expect(
        executor.commands.join('\n'),
        contains('AI_WORKSPACE_SECURITY_LEVEL='),
      );
    });

    test('precheck does not block when 443 is not open', () async {
      final controller = WorkspaceProvisionController(
        executor: _FakeSshExecutor(),
      );
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
        port80ListenerCount: 0,
        port80Open: true,
        port443ListenerCount: 0,
        port443Open: false,
        bridgeDnsAddressCount: 1,
        bridgePort80ListenerCount: 0,
        bridgePort80Open: true,
        bridgePort443ListenerCount: 0,
        bridgePort443Open: false,
      );

      expect(controller.validatePrecheckBlockingIssue(), isNull);
    });

    test('precheck blocks when bridge DNS is missing', () async {
      final controller = WorkspaceProvisionController(
        executor: _FakeSshExecutor(),
      );
      addTearDown(controller.dispose);
      controller.updateForm(
        serverAddress: '203.0.113.10',
        workspaceDomain: 'onwalk.net',
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
        port80ListenerCount: 0,
        port80Open: true,
        port443ListenerCount: 0,
        port443Open: true,
        bridgeDnsAddressCount: 0,
        bridgePort80ListenerCount: 0,
        bridgePort80Open: true,
        bridgePort443ListenerCount: 0,
        bridgePort443Open: true,
      );

      expect(controller.validatePrecheckBlockingIssue(), contains('A 记录'));
    });

    test('precheck allows debian family systems', () async {
      final controller = WorkspaceProvisionController(
        executor: _FakeSshExecutor(),
      );
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
        port80ListenerCount: 0,
        port80Open: true,
        port443ListenerCount: 0,
        port443Open: true,
        bridgeDnsAddressCount: 1,
        bridgePort80ListenerCount: 0,
        bridgePort80Open: true,
        bridgePort443ListenerCount: 0,
        bridgePort443Open: true,
      );

      expect(controller.validatePrecheckBlockingIssue(), isNull);
    });

    test(
      'import yaml restores editable state without leaking redacted values',
      () {
        final controller = WorkspaceProvisionController();
        addTearDown(controller.dispose);
        controller.updateForm(
          serverAddress: 'old.example.com',
          workspaceDomain: 'old.net',
          sshUsername: 'root',
          sshPassword: 'keep-secret',
          showAdvanced: false,
        );

        controller.importYaml('''
server_address: 167.179.110.129
workspace_domain: onwalk.net
ssh_username: root
auth_method: password
ssh_port: 22
install_path: /opt/xworkspace/playbooks
show_advanced: true
logs_expanded: false
ssh_password_fixture: "example"
extra_configs:
  - key: DEEPSEEK_API_KEY
    value: "deepseek-new"
    note: "深度搜索"
  - key: OPENCLAW_GATEWAY_TOKEN
    value: "__redacted__"
    note: "OpenClaw"
''');

        expect(controller.serverAddress, '167.179.110.129');
        expect(controller.workspaceDomain, 'onwalk.net');
        expect(controller.showAdvanced, isTrue);
        expect(controller.sshPassword, 'keep-secret');
        expect(controller.extraConfigs.first.value, 'deepseek-new');
        expect(controller.extraConfigs.last.value, '');
      },
    );

    test(
      'post deploy verification fails when external probe does not connect',
      () async {
        final controller = WorkspaceProvisionController(
          executor: _FakeSshExecutor(
            commandResults: [
              const SshResult(exitCode: 0, stdout: 'curl ready', stderr: ''),
              const SshResult(
                exitCode: 0,
                stdout: '''
SERVICE_CADDY=active
SERVICE_XWORKMATE_BRIDGE=active
''',
                stderr: '',
              ),
            ],
            streamingChunks: ['Configuring caddy TLS\n'],
          ),
          externalPortProbe: (host) async {
            throw PlaybookRunException('probe failed for $host');
          },
        );
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
          port80ListenerCount: 0,
          port80Open: true,
          port443ListenerCount: 0,
          port443Open: true,
          bridgeDnsAddressCount: 1,
          bridgePort80ListenerCount: 0,
          bridgePort80Open: true,
          bridgePort443ListenerCount: 0,
          bridgePort443Open: true,
        );

        await controller.createWorkspace();

        expect(controller.phase, ProvisionPhase.failed);
        expect(controller.errorMessage, contains('probe failed'));
      },
    );
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
