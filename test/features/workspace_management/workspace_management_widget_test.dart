import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/features/workspace_management/ssh_executor.dart';
import 'package:xworkmate/features/workspace_management/workspace_management_panel.dart';
import 'package:xworkmate/features/workspace_management/workspace_provision_controller.dart';
import 'package:xworkmate/features/workspace_management/workspace_provision_models.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';
import 'package:xworkmate/theme/app_theme.dart';

void main() {
  testWidgets('panel renders form controls and keeps upgrade disabled', (
    tester,
  ) async {
    final appController = _NoopAppController(store: _MemorySecureConfigStore());
    final provisionController = WorkspaceProvisionController(
      executor: _FakeSshExecutor(),
      initialWorkspaceDomain: 'workspace.example.com',
    );
    addTearDown(() {
      provisionController.dispose();
      appController.dispose();
    });

    await tester.pumpWidget(
      _buildApp(
        WorkspaceManagementPanel(
          appController: appController,
          provisionController: provisionController,
        ),
      ),
    );

    expect(find.text('创建 / 升级 AI 工作空间'), findsOneWidget);
    expect(find.text('workspace.example.com'), findsOneWidget);
    expect(
      find.byKey(const Key('workspace-management-upgrade-button')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('workspace-management-upgrade-button')),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(find.text('高级选项'));
    await tester.pumpAndSettle();

    expect(find.text('安装路径'), findsOneWidget);
  });

  testWidgets('panel switches auth method and expands logs', (tester) async {
    final appController = _NoopAppController(store: _MemorySecureConfigStore());
    final provisionController = WorkspaceProvisionController(
      executor: _FakeSshExecutor(),
    );
    addTearDown(() {
      provisionController.dispose();
      appController.dispose();
    });

    await tester.pumpWidget(
      _buildApp(
        WorkspaceManagementPanel(
          appController: appController,
          provisionController: provisionController,
        ),
      ),
    );

    await tester.tap(find.text('密码'));
    await tester.pumpAndSettle();
    expect(find.text('SSH 密码 *'), findsOneWidget);

    provisionController.logBuffer.add('hello log');
    provisionController.updateForm(logsExpanded: true);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('workspace-management-log-content')),
      findsOneWidget,
    );
    expect(find.textContaining('hello log'), findsOneWidget);
  });

  testWidgets('success result shows url and bridge token', (tester) async {
    final appController = _NoopAppController(store: _MemorySecureConfigStore());
    final provisionController = WorkspaceProvisionController(
      executor: _FakeSshExecutor(),
    );
    addTearDown(() {
      provisionController.dispose();
      appController.dispose();
    });
    provisionController.deploymentResult = const WorkspaceDeploymentResult(
      url: 'https://xworkmate-bridge.example.com',
      bridgeToken: 'bridge-token-123',
    );
    provisionController.phase = ProvisionPhase.success;

    await tester.pumpWidget(
      _buildApp(
        WorkspaceManagementPanel(
          appController: appController,
          provisionController: provisionController,
        ),
      ),
    );

    expect(find.text('https://xworkmate-bridge.example.com'), findsOneWidget);
    expect(find.text('bridge-token-123'), findsOneWidget);
    expect(find.text('下载凭据'), findsOneWidget);
    expect(find.text('连接到该工作空间'), findsOneWidget);
    expect(find.text('设为默认保存配置'), findsOneWidget);
  });

  testWidgets('success result can save deployed bridge as default', (
    tester,
  ) async {
    final store = _MemorySecureConfigStore();
    final appController = _NoopAppController(store: store);
    final provisionController = WorkspaceProvisionController(
      executor: _FakeSshExecutor(),
    );
    await tester.binding.setSurfaceSize(const Size(1200, 1400));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });
    addTearDown(() {
      provisionController.dispose();
      appController.dispose();
    });
    provisionController.deploymentResult = const WorkspaceDeploymentResult(
      url: 'https://acp-bridge.onwalk.net',
      bridgeToken: 'save-token-123',
    );
    provisionController.phase = ProvisionPhase.success;

    await tester.pumpWidget(
      _buildApp(
        WorkspaceManagementPanel(
          appController: appController,
          provisionController: provisionController,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('设为默认保存配置'));
    await tester.tap(find.text('设为默认保存配置'));
    await tester.pumpAndSettle();

    expect(
      appController.settings.acpBridgeServerModeConfig.selfHosted.serverUrl,
      'https://acp-bridge.onwalk.net',
    );
    expect(
      await appController.settingsController.loadSecretValueByRef(
        appController.settings.acpBridgeServerModeConfig.selfHosted.passwordRef,
      ),
      'save-token-123',
    );
  });
}

Widget _buildApp(Widget child) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: Material(child: child),
  );
}

class _FakeSshExecutor implements WorkspaceSshExecutor {
  @override
  Future<SshResult> execute(SshConfig config, String command) async {
    return const SshResult(exitCode: 0, stdout: '', stderr: '');
  }

  @override
  Stream<String> executeStreaming(SshConfig config, String command) async* {}
}

class _NoopAppController extends AppController {
  _NoopAppController({required SecureConfigStore store})
    : super(environmentOverride: const <String, String>{}, store: store);
}

class _MemorySecureConfigStore extends SecureConfigStore {
  _MemorySecureConfigStore() : super(enableSecureStorage: false);

  SettingsSnapshot _settings = SettingsSnapshot.defaults();
  final Map<String, String> _secrets = <String, String>{};

  @override
  Future<void> initialize() async {}

  @override
  Future<SettingsSnapshot> loadSettingsSnapshot() async => _settings;

  @override
  Future<void> saveSettingsSnapshot(SettingsSnapshot snapshot) async {
    _settings = snapshot;
  }

  @override
  Future<Map<String, String>> loadSecureRefs() async => _secrets;

  @override
  Future<List<SecretAuditEntry>> loadAuditTrail() async =>
      const <SecretAuditEntry>[];

  @override
  Future<void> appendAudit(SecretAuditEntry entry) async {}

  @override
  Future<String?> loadSecretValueByRef(String refName) async =>
      _secrets[refName];

  @override
  Future<void> saveSecretValueByRef(String refName, String value) async {
    _secrets[refName] = value;
  }

  @override
  Future<String?> loadAccountSessionToken() async => null;

  @override
  Future<AccountSessionSummary?> loadAccountSessionSummary() async => null;

  @override
  Future<AccountSyncState?> loadAccountSyncState() async => null;
}
