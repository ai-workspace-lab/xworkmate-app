import 'package:flutter/material.dart';

import '../../i18n/app_language.dart';
import '../../runtime/runtime_models.dart';
import 'local_git_repository_connection.dart';

class SettingsAccountPanel extends StatefulWidget {
  const SettingsAccountPanel({
    super.key,
    required this.settings,
    required this.accountSession,
    required this.accountState,
    required this.accountBusy,
    this.accountStatus = '',
    required this.accountSignedIn,
    required this.accountMfaRequired,
    this.gitHubRepositoryEnabled = true,
    required this.accountBaseUrlController,
    required this.accountIdentifierController,
    required this.accountPasswordController,
    required this.accountMfaCodeController,
    required this.bridgeUrlController,
    required this.bridgeTokenController,
    required this.onSaveAccountProfile,
    required this.onLogin,
    required this.onVerifyMfa,
    required this.onCancelMfa,
    required this.onSync,
    required this.onResetManualBridge,
    required this.onLogout,
    this.onSaveGitHubRepository,
  });

  final SettingsSnapshot settings;
  final AccountSessionSummary? accountSession;
  final AccountSyncState? accountState;
  final bool accountBusy;
  final String accountStatus;
  final bool accountSignedIn;
  final bool accountMfaRequired;
  final bool gitHubRepositoryEnabled;
  final TextEditingController accountBaseUrlController;
  final TextEditingController accountIdentifierController;
  final TextEditingController accountPasswordController;
  final TextEditingController accountMfaCodeController;
  final TextEditingController bridgeUrlController;
  final TextEditingController bridgeTokenController;
  final Future<void> Function({required bool isManualBridge})
  onSaveAccountProfile;
  final Future<void> Function() onLogin;
  final Future<void> Function() onVerifyMfa;
  final Future<void> Function() onCancelMfa;
  final Future<void> Function() onSync;
  final Future<void> Function() onResetManualBridge;
  final Future<void> Function() onLogout;
  final Future<void> Function(
    GitHubRepositoryConnectorConfig config,
    String token,
  )?
  onSaveGitHubRepository;

  @override
  State<SettingsAccountPanel> createState() => _SettingsAccountPanelState();
}

class _SettingsAccountPanelState extends State<SettingsAccountPanel> {
  @override
  Widget build(BuildContext context) {
    final isManualBridgeConfigured =
        widget.settings.acpBridgeServerModeConfig.effective.source == 'bridge';
    if (!widget.accountSignedIn &&
        !widget.accountMfaRequired &&
        !isManualBridgeConfigured) {
      return _AvailableConnectorsPanel(
        accountBusy: widget.accountBusy,
        gitHubRepositoryEnabled: widget.gitHubRepositoryEnabled,
        githubRepository: widget.settings.githubRepository,
        accountBaseUrlController: widget.accountBaseUrlController,
        accountIdentifierController: widget.accountIdentifierController,
        accountPasswordController: widget.accountPasswordController,
        bridgeUrlController: widget.bridgeUrlController,
        bridgeTokenController: widget.bridgeTokenController,
        onSaveAccountProfile: widget.onSaveAccountProfile,
        onLogin: widget.onLogin,
        onSaveGitHubRepository: widget.onSaveGitHubRepository,
      );
    }
    if (widget.accountMfaRequired) {
      return _PendingMfaAccountPanel(
        accountBusy: widget.accountBusy,
        accountBaseUrlController: widget.accountBaseUrlController,
        accountIdentifierController: widget.accountIdentifierController,
        accountMfaCodeController: widget.accountMfaCodeController,
        onVerifyMfa: widget.onVerifyMfa,
        onCancelMfa: widget.onCancelMfa,
      );
    }
    return _SignedInAccountPanel(
      settings: widget.settings,
      accountSession: widget.accountSession,
      accountState: widget.accountState,
      accountBusy: widget.accountBusy,
      accountStatus: widget.accountStatus,
      onSaveAccountProfile: widget.onSaveAccountProfile,
      onSync: widget.onSync,
      onResetManualBridge: widget.onResetManualBridge,
      onLogout: widget.onLogout,
    );
  }
}

enum _ConnectorSelection { svcPlus, selfHosted, localGitRepository }

class _AvailableConnectorsPanel extends StatefulWidget {
  const _AvailableConnectorsPanel({
    required this.accountBusy,
    required this.gitHubRepositoryEnabled,
    required this.githubRepository,
    required this.accountBaseUrlController,
    required this.accountIdentifierController,
    required this.accountPasswordController,
    required this.bridgeUrlController,
    required this.bridgeTokenController,
    required this.onSaveAccountProfile,
    required this.onLogin,
    required this.onSaveGitHubRepository,
  });

  final bool accountBusy;
  final bool gitHubRepositoryEnabled;
  final GitHubRepositoryConnectorConfig githubRepository;
  final TextEditingController accountBaseUrlController;
  final TextEditingController accountIdentifierController;
  final TextEditingController accountPasswordController;
  final TextEditingController bridgeUrlController;
  final TextEditingController bridgeTokenController;
  final Future<void> Function({required bool isManualBridge})
  onSaveAccountProfile;
  final Future<void> Function() onLogin;
  final Future<void> Function(
    GitHubRepositoryConnectorConfig config,
    String token,
  )?
  onSaveGitHubRepository;

  @override
  State<_AvailableConnectorsPanel> createState() =>
      _AvailableConnectorsPanelState();
}

class _AvailableConnectorsPanelState extends State<_AvailableConnectorsPanel> {
  _ConnectorSelection? _selection;
  late final TextEditingController _gitRepositoryUrlController;
  late final TextEditingController _gitHubTokenController;
  late final TextEditingController _gitBranchController;
  late final TextEditingController _gitPublishPathController;

  @override
  void initState() {
    super.initState();
    _gitRepositoryUrlController = TextEditingController(
      text: widget.githubRepository.repository,
    );
    _gitHubTokenController = TextEditingController();
    _gitBranchController = TextEditingController(
      text: widget.githubRepository.branch,
    );
    _gitPublishPathController = TextEditingController(
      text: widget.githubRepository.publishPath,
    );
  }

  @override
  void dispose() {
    _gitRepositoryUrlController.dispose();
    _gitHubTokenController.dispose();
    _gitBranchController.dispose();
    _gitPublishPathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            appText('连接器', 'Connectors'),
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 6),
          Text(
            appText(
              '连接外部服务，为 XWorkmate 增加工作空间与协作能力。',
              'Connect external services to add workspace and collaboration capabilities to XWorkmate.',
            ),
          ),
          const SizedBox(height: 20),
          Text(
            appText('可用连接器', 'Available connectors'),
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          if (widget.gitHubRepositoryEnabled) ...[
            _ConnectorCard(
              connectorId: 'local-git-repository',
              icon: Icons.account_tree_outlined,
              title: appText('GitHub 仓库（API）', 'GitHub Repository (API)'),
              subtitle: appText(
                '通过 GitHub API 发布对话，无需启动本机 Git。',
                'Publish conversations through the GitHub API without starting local Git.',
              ),
              actionLabel: widget.githubRepository.isConfigured
                  ? appText('配置', 'Configure')
                  : appText('连接', 'Connect'),
              onAction: () => setState(
                () => _selection = _ConnectorSelection.localGitRepository,
              ),
            ),
            const SizedBox(height: 12),
          ],
          _ConnectorCard(
            connectorId: 'svc-plus-workspace',
            icon: Icons.cloud_outlined,
            title: 'svc.plus Workspace',
            subtitle: appText(
              '连接你已有的工作空间配置。',
              'Connect an existing workspace configuration.',
            ),
            actionLabel: appText('连接', 'Connect'),
            onAction: () =>
                setState(() => _selection = _ConnectorSelection.svcPlus),
          ),
          const SizedBox(height: 12),
          _ConnectorCard(
            connectorId: 'self-hosted-workspace',
            icon: Icons.dns_outlined,
            title: appText('自托管工作空间', 'Self-hosted Workspace'),
            subtitle: appText(
              '连接你自行部署的 AI Workspace。',
              'Connect an AI Workspace that you deploy and manage.',
            ),
            actionLabel: appText('连接', 'Connect'),
            onAction: () =>
                setState(() => _selection = _ConnectorSelection.selfHosted),
          ),
          if (_selection != null) ...[
            const SizedBox(height: 20),
            _ConnectorConfiguration(
              title: _selection == _ConnectorSelection.svcPlus
                  ? 'svc.plus Workspace'
                  : _selection == _ConnectorSelection.selfHosted
                  ? appText('自托管工作空间', 'Self-hosted Workspace')
                  : appText('GitHub 仓库（API）', 'GitHub Repository (API)'),
              onClose: () => setState(() => _selection = null),
              child: _selection == _ConnectorSelection.svcPlus
                  ? _SignedOutAccountPanel(
                      accountBusy: widget.accountBusy,
                      accountBaseUrlController: widget.accountBaseUrlController,
                      accountIdentifierController:
                          widget.accountIdentifierController,
                      accountPasswordController:
                          widget.accountPasswordController,
                      onSaveAccountProfile: widget.onSaveAccountProfile,
                      onLogin: widget.onLogin,
                    )
                  : _selection == _ConnectorSelection.selfHosted
                  ? _ManualBridgePanel(
                      settings: SettingsSnapshot.defaults(),
                      accountBusy: widget.accountBusy,
                      bridgeUrlController: widget.bridgeUrlController,
                      bridgeTokenController: widget.bridgeTokenController,
                      onSaveAccountProfile: widget.onSaveAccountProfile,
                    )
                  : _LocalGitRepositoryPanel(
                      repositoryUrlController: _gitRepositoryUrlController,
                      tokenController: _gitHubTokenController,
                      branchController: _gitBranchController,
                      publishPathController: _gitPublishPathController,
                      onSave: widget.onSaveGitHubRepository,
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LocalGitRepositoryPanel extends StatefulWidget {
  const _LocalGitRepositoryPanel({
    required this.repositoryUrlController,
    required this.tokenController,
    required this.branchController,
    required this.publishPathController,
    required this.onSave,
  });

  final TextEditingController repositoryUrlController;
  final TextEditingController tokenController;
  final TextEditingController branchController;
  final TextEditingController publishPathController;
  final Future<void> Function(
    GitHubRepositoryConnectorConfig config,
    String token,
  )?
  onSave;

  @override
  State<_LocalGitRepositoryPanel> createState() =>
      _LocalGitRepositoryPanelState();
}

class _LocalGitRepositoryPanelState extends State<_LocalGitRepositoryPanel> {
  bool _checking = false;
  String? _connectionStatus;

  Future<void> _verifyConnection() async {
    setState(() {
      _checking = true;
      _connectionStatus = null;
    });
    final result = await verifyGitHubRepositoryConnection(
      repository: widget.repositoryUrlController.text,
      token: widget.tokenController.text,
    );
    if (!mounted) return;
    if (result.success && widget.onSave != null) {
      await widget.onSave!(
        GitHubRepositoryConnectorConfig(
          repository: widget.repositoryUrlController.text.trim(),
          branch: widget.branchController.text.trim(),
          publishPath: widget.publishPathController.text.trim(),
          connected: true,
        ),
        widget.tokenController.text,
      );
    }
    if (!mounted) return;
    setState(() {
      _checking = false;
      _connectionStatus = result.message;
    });
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        appText(
          '使用 GitHub Fine-grained token 连接仓库。令牌只用于当前请求，且不会写入日志。',
          'Connect with a GitHub fine-grained token. It is only used for this request and never written to logs.',
        ),
      ),
      const SizedBox(height: 16),
      TextFormField(
        key: const ValueKey('settings-local-git-repository-url-field'),
        controller: widget.repositoryUrlController,
        decoration: InputDecoration(
          labelText: appText('GitHub 仓库', 'GitHub repository'),
          hintText: 'haitaopanhq/knowledge',
        ),
        keyboardType: TextInputType.url,
        autofillHints: const <String>[],
      ),
      const SizedBox(height: 12),
      TextFormField(
        key: const ValueKey('settings-github-token-field'),
        controller: widget.tokenController,
        decoration: InputDecoration(
          labelText: appText('Fine-grained token', 'Fine-grained token'),
        ),
        obscureText: true,
        enableSuggestions: false,
        autocorrect: false,
        autofillHints: const <String>[],
      ),
      const SizedBox(height: 12),
      TextFormField(
        key: const ValueKey('settings-local-git-branch-field'),
        controller: widget.branchController,
        decoration: InputDecoration(labelText: appText('分支', 'Branch')),
      ),
      const SizedBox(height: 12),
      TextFormField(
        key: const ValueKey('settings-local-git-publish-path-field'),
        controller: widget.publishPathController,
        decoration: InputDecoration(
          labelText: appText('对话发布目录', 'Conversation publish directory'),
          hintText: 'conversations',
        ),
      ),
      const SizedBox(height: 16),
      Align(
        alignment: Alignment.centerRight,
        child: FilledButton.icon(
          key: const ValueKey('settings-local-git-test-connection'),
          onPressed: _checking ? null : _verifyConnection,
          icon: _checking
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.link_outlined),
          label: Text(appText('连接并保存', 'Connect and save')),
        ),
      ),
      if (_connectionStatus case final status?) ...[
        const SizedBox(height: 10),
        Text(
          status,
          key: const ValueKey('settings-local-git-connection-status'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
      const SizedBox(height: 16),
      Text(
        appText(
          '验证连接只会调用 GitHub 的 HTTPS API；不会启动外部进程，也不会读取 SSH 私钥。',
          'Verification only calls the GitHub HTTPS API. It never starts an external process or reads SSH private keys.',
        ),
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );
}

class _ConnectorConfiguration extends StatelessWidget {
  const _ConnectorConfiguration({
    required this.title,
    required this.onClose,
    required this.child,
  });
  final String title;
  final VoidCallback onClose;
  final Widget child;
  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    borderRadius: BorderRadius.circular(16),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  appText('连接 $title', 'Connect $title'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded),
                tooltip: appText('关闭', 'Close'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    ),
  );
}

class _ConnectorCard extends StatelessWidget {
  const _ConnectorCard({
    required this.connectorId,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });
  final String connectorId;
  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Material(
    key: ValueKey('settings-connector-$connectorId'),
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    borderRadius: BorderRadius.circular(16),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 3),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          if (actionLabel != null)
            FilledButton.tonal(
              key: ValueKey('settings-connector-action-$connectorId'),
              onPressed: onAction,
              child: Text(actionLabel!),
            ),
        ],
      ),
    ),
  );
}

class _ManualBridgePanel extends StatelessWidget {
  const _ManualBridgePanel({
    required this.settings,
    required this.accountBusy,
    required this.bridgeUrlController,
    required this.bridgeTokenController,
    required this.onSaveAccountProfile,
  });

  final SettingsSnapshot settings;
  final bool accountBusy;
  final TextEditingController bridgeUrlController;
  final TextEditingController bridgeTokenController;
  final Future<void> Function({required bool isManualBridge})
  onSaveAccountProfile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              Icons.link_outlined,
              size: 72,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              appText('自托管工作空间', 'Self-hosted Workspace'),
              style: theme.textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              appText(
                '连接你自行部署的 AI Workspace。',
                'Connect an AI Workspace that you deploy and manage.',
              ),
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.textTheme.bodyMedium?.color?.withValues(
                  alpha: 0.8,
                ),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            TextFormField(
              key: const ValueKey('settings-manual-bridge-url-field'),
              controller: bridgeUrlController,
              decoration: InputDecoration(
                labelText: appText('服务地址', 'Service URL'),
                prefixIcon: const Icon(Icons.dns_outlined),
                hintText: 'https://xworkmate-bridge.svc.plus',
              ),
              onFieldSubmitted: (_) =>
                  onSaveAccountProfile(isManualBridge: true),
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const ValueKey('settings-manual-bridge-token-field'),
              controller: bridgeTokenController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: appText('访问令牌', 'Access token'),
                prefixIcon: const Icon(Icons.key_outlined),
              ),
              onFieldSubmitted: (_) =>
                  onSaveAccountProfile(isManualBridge: true),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const ValueKey('settings-manual-bridge-save-button'),
                onPressed: accountBusy
                    ? null
                    : () => onSaveAccountProfile(isManualBridge: true),
                child: Text(appText('连接', 'Connect')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SignedOutAccountPanel extends StatelessWidget {
  const _SignedOutAccountPanel({
    required this.accountBusy,
    required this.accountBaseUrlController,
    required this.accountIdentifierController,
    required this.accountPasswordController,
    required this.onSaveAccountProfile,
    required this.onLogin,
  });

  final bool accountBusy;
  final TextEditingController accountBaseUrlController;
  final TextEditingController accountIdentifierController;
  final TextEditingController accountPasswordController;
  final Future<void> Function({required bool isManualBridge})
  onSaveAccountProfile;
  final Future<void> Function() onLogin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              Icons.cloud_outlined,
              size: 72,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              appText('连接 svc.plus Workspace', 'Connect svc.plus Workspace'),
              style: theme.textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              appText(
                '访问你已有的工作空间配置。',
                'Access an existing workspace configuration.',
              ),
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.textTheme.bodyMedium?.color?.withValues(
                  alpha: 0.8,
                ),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            TextFormField(
              key: const ValueKey('settings-account-base-url-field'),
              controller: accountBaseUrlController,
              decoration: InputDecoration(
                labelText: appText('服务地址', 'Service URL'),
                prefixIcon: const Icon(Icons.dns_outlined),
              ),
              onFieldSubmitted: (_) =>
                  onSaveAccountProfile(isManualBridge: false),
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const ValueKey('settings-account-identifier-field'),
              controller: accountIdentifierController,
              decoration: InputDecoration(
                labelText: appText('邮箱或账号', 'Email or Username'),
                prefixIcon: const Icon(Icons.person_outline_rounded),
              ),
              onFieldSubmitted: (_) =>
                  onSaveAccountProfile(isManualBridge: false),
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const ValueKey('settings-account-password-field'),
              controller: accountPasswordController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: appText('密码', 'Password'),
                prefixIcon: const Icon(Icons.lock_outline_rounded),
              ),
              onFieldSubmitted: (_) => onLogin(),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const ValueKey('settings-account-login-button'),
                onPressed: accountBusy ? null : () => onLogin(),
                child: Text(appText('连接', 'Connect')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PendingMfaAccountPanel extends StatelessWidget {
  const _PendingMfaAccountPanel({
    required this.accountBusy,
    required this.accountBaseUrlController,
    required this.accountIdentifierController,
    required this.accountMfaCodeController,
    required this.onVerifyMfa,
    required this.onCancelMfa,
  });

  final bool accountBusy;
  final TextEditingController accountBaseUrlController;
  final TextEditingController accountIdentifierController;
  final TextEditingController accountMfaCodeController;
  final Future<void> Function() onVerifyMfa;
  final Future<void> Function() onCancelMfa;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              Icons.verified_user_outlined,
              size: 72,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              appText('双重验证', 'Multi-Factor Authentication'),
              style: theme.textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              appText(
                '请输入验证码以完成此连接。',
                'Enter your code to complete this connection.',
              ),
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.textTheme.bodyMedium?.color?.withValues(
                  alpha: 0.8,
                ),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            TextFormField(
              key: const ValueKey('settings-account-base-url-field'),
              controller: accountBaseUrlController,
              readOnly: true,
              decoration: InputDecoration(
                labelText: appText('服务地址', 'Service URL'),
                prefixIcon: const Icon(Icons.dns_outlined),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const ValueKey('settings-account-identifier-field'),
              controller: accountIdentifierController,
              readOnly: true,
              decoration: InputDecoration(
                labelText: appText('邮箱或账号', 'Email or Username'),
                prefixIcon: const Icon(Icons.person_outline_rounded),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const ValueKey('settings-account-mfa-code-field'),
              controller: accountMfaCodeController,
              decoration: InputDecoration(
                labelText: appText('双重验证代码', 'MFA Code'),
                prefixIcon: const Icon(Icons.key_outlined),
              ),
              onFieldSubmitted: (_) => onVerifyMfa(),
            ),
            const SizedBox(height: 24),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton(
                  key: const ValueKey('settings-account-mfa-verify-button'),
                  onPressed: accountBusy ? null : () => onVerifyMfa(),
                  child: Text(appText('验证并连接', 'Verify & Connect')),
                ),
                FilledButton.tonal(
                  key: const ValueKey('settings-account-mfa-cancel-button'),
                  onPressed: accountBusy ? null : () => onCancelMfa(),
                  child: Text(appText('返回编辑', 'Back to Edit')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SignedInAccountPanel extends StatelessWidget {
  const _SignedInAccountPanel({
    required this.settings,
    required this.accountSession,
    required this.accountState,
    required this.accountBusy,
    required this.accountStatus,
    required this.onSaveAccountProfile,
    required this.onSync,
    required this.onResetManualBridge,
    required this.onLogout,
  });

  final SettingsSnapshot settings;
  final AccountSessionSummary? accountSession;
  final AccountSyncState? accountState;
  final bool accountBusy;
  final String accountStatus;
  final Future<void> Function({required bool isManualBridge})
  onSaveAccountProfile;
  final Future<void> Function() onSync;
  final Future<void> Function() onResetManualBridge;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
    final mode = _signedInAccountModeFromSettings(
      settings: settings,
      accountState: accountState,
    );
    final isAccountSyncMode = mode == _SignedInAccountMode.accountSync;
    final cloudSync = settings.acpBridgeServerModeConfig.cloudSynced;
    final serviceUrl = cloudSync.accountBaseUrl.trim().isNotEmpty
        ? cloudSync.accountBaseUrl.trim()
        : settings.accountBaseUrl.trim();
    final accountIdentifier = cloudSync.accountIdentifier.trim().isNotEmpty
        ? cloudSync.accountIdentifier.trim()
        : settings.accountUsername.trim().isNotEmpty
        ? settings.accountUsername.trim()
        : (accountSession?.email.trim() ?? '');
    final remoteSummary = cloudSync.remoteServerSummary.endpoint.trim();
    final syncScope = accountState?.profileScope.trim().isNotEmpty == true
        ? accountState!.profileScope.trim()
        : appText('待同步', 'Pending sync');
    final syncState = accountState?.syncState.trim().isNotEmpty == true
        ? accountState!.syncState.trim()
        : 'idle';
    final syncMessage = accountState?.syncMessage.trim().isNotEmpty == true
        ? accountState!.syncMessage.trim()
        : appText('尚未同步远端配置', 'Remote config not synced yet');
    final modeStateLabel = accountBusy
        ? (isAccountSyncMode
              ? appText('同步中', 'Syncing')
              : appText('保存中', 'Saving'))
        : (isAccountSyncMode
              ? _describeAccountSyncState(syncState)
              : _describeBridgeSaveState(settings));
    final modeStatusLabel = accountBusy && accountStatus.trim().isNotEmpty
        ? accountStatus.trim()
        : syncMessage;
    final modeIcon = isAccountSyncMode
        ? Icons.cloud_outlined
        : Icons.link_outlined;
    final modeTitle = isAccountSyncMode
        ? 'svc.plus Workspace'
        : appText('自托管工作空间', 'Self-hosted Workspace');
    final primaryActionLabel = isAccountSyncMode
        ? appText('刷新连接', 'Refresh connection')
        : appText('断开连接', 'Disconnect');
    final primaryActionKey = isAccountSyncMode
        ? 'settings-account-sync-button'
        : 'settings-account-manual-reset-button';
    final primaryAction = isAccountSyncMode ? onSync : onResetManualBridge;
    final exitAction = isAccountSyncMode ? onLogout : onResetManualBridge;
    final mfaEnabled =
        accountSession?.totpEnabled == true ||
        accountSession?.mfaEnabled == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          appText('已连接的连接器', 'Connected connectors'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          appText(
            '已连接的服务优先显示；详细连接信息默认折叠。',
            'Connected services appear first; connection details stay collapsed by default.',
          ),
        ),
        const SizedBox(height: 16),
        Material(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      modeIcon,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            modeTitle,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isAccountSyncMode
                                ? '${appText('连接状态', 'Connection status')}: $modeStateLabel'
                                : '${appText('连接状态', 'Connection status')}: $modeStateLabel',
                            key: const ValueKey('settings-account-sync-status'),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            accountSession?.email.trim().isNotEmpty == true
                                ? accountSession!.email.trim()
                                : appText('当前账号', 'Current account'),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.color
                                      ?.withValues(alpha: 0.78),
                                ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      alignment: WrapAlignment.end,
                      children: [
                        FilledButton.tonal(
                          key: ValueKey(primaryActionKey),
                          onPressed: accountBusy ? null : () => primaryAction(),
                          child: accountBusy
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        key: const ValueKey(
                                          'settings-account-sync-progress',
                                        ),
                                        strokeWidth: 2,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      isAccountSyncMode
                                          ? appText('同步中', 'Syncing')
                                          : appText('保存中', 'Saving'),
                                    ),
                                  ],
                                )
                              : Text(primaryActionLabel),
                        ),
                        TextButton(
                          key: const ValueKey('settings-account-logout-button'),
                          onPressed: accountBusy ? null : () => exitAction(),
                          child: Text(appText('断开连接', 'Disconnect')),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  isAccountSyncMode
                      ? '${appText('连接说明', 'Connection summary')}: $modeStatusLabel'
                      : '${appText('连接说明', 'Connection summary')}: $modeStatusLabel',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(
                      context,
                    ).textTheme.bodySmall?.color?.withValues(alpha: 0.78),
                  ),
                ),
                const SizedBox(height: 8),
                ExpansionTile(
                  key: const ValueKey('settings-account-summary-expansion'),
                  initiallyExpanded: false,
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(top: 8),
                  title: Text(
                    appText('详细信息', 'Details'),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  subtitle: Text(
                    appText(
                      '查看服务地址、令牌与远端摘要',
                      'View service URL, tokens, and remote summary',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  children: [
                    _SignedInAccountDetails(
                      settings: settings,
                      accountSession: accountSession,
                      accountState: accountState,
                      serviceUrl: serviceUrl,
                      accountIdentifier: accountIdentifier,
                      remoteSummary: remoteSummary,
                      syncScope: syncScope,
                      mfaEnabled: mfaEnabled,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SignedInAccountDetails extends StatelessWidget {
  const _SignedInAccountDetails({
    required this.settings,
    required this.accountSession,
    required this.accountState,
    required this.serviceUrl,
    required this.accountIdentifier,
    required this.remoteSummary,
    required this.syncScope,
    required this.mfaEnabled,
  });

  final SettingsSnapshot settings;
  final AccountSessionSummary? accountSession;
  final AccountSyncState? accountState;
  final String serviceUrl;
  final String accountIdentifier;
  final String remoteSummary;
  final String syncScope;
  final bool mfaEnabled;

  @override
  Widget build(BuildContext context) {
    final cloudSync = settings.acpBridgeServerModeConfig.cloudSynced;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${appText('服务地址', 'Service URL')}: ${serviceUrl.isEmpty ? appText('待配置', 'Pending') : serviceUrl}',
            key: const ValueKey('settings-account-summary-service-url'),
          ),
          const SizedBox(height: 6),
          Text(
            '${appText('连接身份', 'Connection identity')}: ${accountIdentifier.isEmpty ? appText('待连接', 'Not connected') : accountIdentifier}',
            key: const ValueKey('settings-account-summary-account-identifier'),
          ),
          const SizedBox(height: 6),
          Text(
            '${appText('连接来源', 'Connection Source')}: ${_connectionSourceLabel(settings, accountState)}',
            key: const ValueKey('settings-account-summary-connection-source'),
          ),
          const SizedBox(height: 6),
          Text(
            '${appText('远端摘要', 'Remote Summary')}: ${remoteSummary.isEmpty ? appText('待同步', 'Pending sync') : remoteSummary}',
            key: const ValueKey('settings-account-summary-remote-summary'),
          ),
          const SizedBox(height: 6),
          Text(
            '${appText('最近同步', 'Last Sync')}: ${_formatSyncTime(cloudSync.lastSyncAt)}',
            key: const ValueKey('settings-account-summary-last-sync'),
          ),
          const SizedBox(height: 6),
          Text(
            '${appText('MFA 状态', 'MFA Status')}: ${mfaEnabled ? appText('已启用', 'Enabled') : appText('未启用', 'Disabled')}',
            key: const ValueKey('settings-account-summary-mfa-status'),
          ),
          const SizedBox(height: 6),
          Text(
            '${appText('同步范围', 'Sync Scope')}: $syncScope',
            key: const ValueKey('settings-account-summary-sync-scope'),
          ),
          const SizedBox(height: 6),
          _TokenConfiguredSummary(accountState: accountState),
        ],
      ),
    );
  }
}

enum _SignedInAccountMode { accountSync, manualBridge }

_SignedInAccountMode _signedInAccountModeFromSettings({
  required SettingsSnapshot settings,
  required AccountSyncState? accountState,
}) {
  if (settings.acpBridgeServerModeConfig.effective.source == 'bridge') {
    return _SignedInAccountMode.manualBridge;
  }
  if (accountState?.profileScope.trim().toLowerCase() == 'bridge') {
    return _SignedInAccountMode.accountSync;
  }
  return _SignedInAccountMode.manualBridge;
}

String _describeAccountSyncState(String syncState) {
  final normalized = syncState.trim().toLowerCase();
  switch (normalized) {
    case 'ready':
      return appText('已同步', 'Synced');
    case 'syncing':
      return appText('同步中', 'Syncing');
    case 'blocked':
    case 'error':
      return appText('失败', 'Failed');
    default:
      return appText('待同步', 'Pending sync');
  }
}

String _describeBridgeSaveState(SettingsSnapshot settings) {
  final configured = settings.acpBridgeServerModeConfig.selfHosted.isConfigured;
  return configured ? appText('已保存', 'Saved') : appText('未保存', 'Not saved');
}

String _connectionSourceLabel(
  SettingsSnapshot settings,
  AccountSyncState? accountState,
) {
  final mode = _signedInAccountModeFromSettings(
    settings: settings,
    accountState: accountState,
  );
  return mode == _SignedInAccountMode.accountSync
      ? 'svc.plus Workspace'
      : appText('自托管工作空间', 'Self-hosted Workspace');
}

class _TokenConfiguredSummary extends StatelessWidget {
  const _TokenConfiguredSummary({required this.accountState});

  final AccountSyncState? accountState;

  @override
  Widget build(BuildContext context) {
    final configured = <String>[
      if (accountState?.tokenConfigured.bridge == true)
        appText('Bridge Token', 'Bridge Token'),
      if (accountState?.tokenConfigured.vault == true) 'Vault Token',
    ];
    final summary = configured.isEmpty
        ? appText('未配置', 'Not configured')
        : configured.join(' / ');
    return Text(
      '${appText('已同步令牌', 'Synced Tokens')}: $summary',
      key: const ValueKey('settings-account-summary-token-configured'),
    );
  }
}

String _formatSyncTime(int lastSyncAtMs) {
  if (lastSyncAtMs <= 0) {
    return appText('尚未同步', 'Not synced yet');
  }
  return DateTime.fromMillisecondsSinceEpoch(
    lastSyncAtMs,
  ).toLocal().toIso8601String();
}
