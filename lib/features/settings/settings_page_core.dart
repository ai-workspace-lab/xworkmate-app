import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/workspace_navigation.dart';
import '../../i18n/app_language.dart';
import '../../models/app_models.dart';
import '../../runtime/runtime_controllers.dart';
import '../../runtime/runtime_models.dart';
import '../../widgets/section_tabs.dart';
import '../../widgets/settings_page_shell.dart';
import '../../widgets/surface_card.dart';

enum _SettingsIntegrationTab { accountStatus, baseConnection }

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.controller,
    this.initialTab = SettingsTab.gateway,
    this.initialDetail,
    this.navigationContext,
  });

  final AppController controller;
  final SettingsTab initialTab;
  final SettingsDetailPage? initialDetail;
  final SettingsNavigationContext? navigationContext;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final TextEditingController _searchController = TextEditingController();
  late final TextEditingController _accountBaseUrlController;
  late final TextEditingController _accountIdentifierController;
  late final TextEditingController _accountPasswordController;
  late final TextEditingController _accountMfaCodeController;
  _SettingsIntegrationTab _integrationTab =
      _SettingsIntegrationTab.accountStatus;
  String _lastSavedAccountBaseUrl = '';
  String _lastSavedAccountIdentifier = '';

  @override
  void initState() {
    super.initState();
    final settings = widget.controller.settings;
    _lastSavedAccountBaseUrl = settings.accountBaseUrl;
    _lastSavedAccountIdentifier = settings.accountUsername;
    _accountBaseUrlController = TextEditingController(
      text: _lastSavedAccountBaseUrl,
    );
    _accountIdentifierController = TextEditingController(
      text: _lastSavedAccountIdentifier,
    );
    _accountPasswordController = TextEditingController();
    _accountMfaCodeController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _accountBaseUrlController.dispose();
    _accountIdentifierController.dispose();
    _accountPasswordController.dispose();
    _accountMfaCodeController.dispose();
    super.dispose();
  }

  void _syncAccountControllers(SettingsSnapshot settings) {
    if (_accountBaseUrlController.text == _lastSavedAccountBaseUrl &&
        settings.accountBaseUrl != _lastSavedAccountBaseUrl) {
      _accountBaseUrlController.text = settings.accountBaseUrl;
    }
    if (_accountIdentifierController.text == _lastSavedAccountIdentifier &&
        settings.accountUsername != _lastSavedAccountIdentifier) {
      _accountIdentifierController.text = settings.accountUsername;
    }
    _lastSavedAccountBaseUrl = settings.accountBaseUrl;
    _lastSavedAccountIdentifier = settings.accountUsername;
  }

  Future<void> _saveAccountProfile(SettingsSnapshot settings) async {
    final nextSettings = settings.copyWith(
      accountBaseUrl: _accountBaseUrlController.text.trim(),
      accountUsername: _accountIdentifierController.text.trim(),
    );
    await widget.controller.settingsController.saveSnapshot(nextSettings);
    _lastSavedAccountBaseUrl = nextSettings.accountBaseUrl;
    _lastSavedAccountIdentifier = nextSettings.accountUsername;
  }

  Future<void> _loginAccount(SettingsSnapshot settings) async {
    final baseUrl = _accountBaseUrlController.text.trim();
    final identifier = _accountIdentifierController.text.trim();
    try {
      await _saveAccountProfile(settings);
      await widget.controller.settingsController.loginAccount(
        baseUrl: baseUrl,
        identifier: identifier,
        password: _accountPasswordController.text,
      );
      await _refreshBridgeCapabilities();
    } finally {
      _accountPasswordController.clear();
    }
  }

  Future<void> _syncAccount(SettingsSnapshot settings) async {
    await _saveAccountProfile(settings);
    await widget.controller.settingsController.syncAccountSettings(
      baseUrl: _accountBaseUrlController.text.trim(),
    );
    await _refreshBridgeCapabilities();
  }

  Future<void> _verifyAccountMfa(SettingsSnapshot settings) async {
    try {
      await _saveAccountProfile(settings);
      await widget.controller.settingsController.verifyAccountMfa(
        baseUrl: _accountBaseUrlController.text.trim(),
        code: _accountMfaCodeController.text.trim(),
      );
      await _refreshBridgeCapabilities();
    } finally {
      _accountMfaCodeController.clear();
    }
  }

  Future<void> _refreshBridgeCapabilities() async {
    final dynamic controller = widget.controller;
    try {
      await controller.refreshSingleAgentCapabilitiesInternal(
        forceRefresh: true,
      );
    } catch (_) {
      // Best effort only. Account sync should still succeed if runtime refresh
      // is temporarily unavailable.
    }
    try {
      await controller.refreshAcpCapabilitiesInternal(forceRefresh: true);
    } catch (_) {
      // Best effort only. Runtime capabilities can be retried later.
    }
  }

  Future<void> _cancelAccountMfa() async {
    await widget.controller.settingsController.cancelAccountMfaChallenge();
    _accountPasswordController.clear();
    _accountMfaCodeController.clear();
  }

  Future<void> _logoutAccount() async {
    await widget.controller.settingsController.logoutAccount();
    _accountPasswordController.clear();
    _accountMfaCodeController.clear();
  }

  Future<void> _disconnectManagedBase(SettingsSnapshot settings) async {
    final nextSettings = settings.copyWith(
      accountLocalMode: true,
      acpBridgeServerModeConfig: settings.acpBridgeServerModeConfig.copyWith(
        mode: AcpBridgeServerMode.cloudSynced,
        cloudSynced: settings.acpBridgeServerModeConfig.cloudSynced.copyWith(
          accountIdentifier: '',
        ),
      ),
    );
    await widget.controller.settingsController.saveSnapshot(nextSettings);
  }

  Widget _buildTokenConfiguredSummary(AccountSyncState? accountState) {
    final configured = <String>[
      if (accountState?.tokenConfigured.openclaw == true)
        appText('Gateway Token', 'Gateway Token'),
      if (accountState?.tokenConfigured.apisix == true)
        appText('AI Gateway Token', 'AI Gateway Token'),
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

  Widget _buildSignedOutAccountCard(
    BuildContext context,
    SettingsSnapshot settings,
    bool accountBusy,
  ) {
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
              appText('账号登录', 'Account Sign In'),
              style: theme.textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              appText('请先登录', 'Please sign in first'),
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
              controller: _accountBaseUrlController,
              decoration: InputDecoration(
                labelText: appText('服务地址', 'Service URL'),
                prefixIcon: const Icon(Icons.dns_outlined),
              ),
              onFieldSubmitted: (_) => _saveAccountProfile(settings),
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const ValueKey('settings-account-identifier-field'),
              controller: _accountIdentifierController,
              decoration: InputDecoration(
                labelText: appText('邮箱或账号', 'Email or Username'),
                prefixIcon: const Icon(Icons.person_outline_rounded),
              ),
              onFieldSubmitted: (_) => _saveAccountProfile(settings),
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const ValueKey('settings-account-password-field'),
              controller: _accountPasswordController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: appText('密码', 'Password'),
                prefixIcon: const Icon(Icons.lock_outline_rounded),
              ),
              onFieldSubmitted: (_) => _loginAccount(settings),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const ValueKey('settings-account-login-button'),
                onPressed: accountBusy ? null : () => _loginAccount(settings),
                child: Text(appText('登录', 'Sign In')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingMfaAccountCard(
    BuildContext context,
    SettingsSnapshot settings,
    bool accountBusy,
  ) {
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
                '请输入验证码完成登录并同步设置。',
                'Enter your code to finish signing in and sync settings.',
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
              controller: _accountBaseUrlController,
              readOnly: true,
              decoration: InputDecoration(
                labelText: appText('服务地址', 'Service URL'),
                prefixIcon: const Icon(Icons.dns_outlined),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const ValueKey('settings-account-identifier-field'),
              controller: _accountIdentifierController,
              readOnly: true,
              decoration: InputDecoration(
                labelText: appText('邮箱或账号', 'Email or Username'),
                prefixIcon: const Icon(Icons.person_outline_rounded),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const ValueKey('settings-account-mfa-code-field'),
              controller: _accountMfaCodeController,
              decoration: InputDecoration(
                labelText: appText('双重验证代码', 'MFA Code'),
                prefixIcon: const Icon(Icons.key_outlined),
              ),
              onFieldSubmitted: (_) => _verifyAccountMfa(settings),
            ),
            const SizedBox(height: 24),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton(
                  key: const ValueKey('settings-account-mfa-verify-button'),
                  onPressed: accountBusy
                      ? null
                      : () => _verifyAccountMfa(settings),
                  child: Text(appText('验证并同步', 'Verify & Sync')),
                ),
                FilledButton.tonal(
                  key: const ValueKey('settings-account-mfa-cancel-button'),
                  onPressed: accountBusy ? null : _cancelAccountMfa,
                  child: Text(appText('返回编辑', 'Back to Edit')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSignedInAccountCard(
    BuildContext context,
    SettingsSnapshot currentSettings,
    AccountSessionSummary? accountSession,
    AccountSyncState? accountState,
    bool accountBusy,
    bool accountSignedIn,
  ) {
    final cloudSync = currentSettings.acpBridgeServerModeConfig.cloudSynced;
    final serviceUrl = cloudSync.accountBaseUrl.trim().isNotEmpty
        ? cloudSync.accountBaseUrl.trim()
        : currentSettings.accountBaseUrl.trim();
    final accountIdentifier = cloudSync.accountIdentifier.trim().isNotEmpty
        ? cloudSync.accountIdentifier.trim()
        : currentSettings.accountUsername.trim().isNotEmpty
        ? currentSettings.accountUsername.trim()
        : (accountSession?.email.trim() ?? '');
    final mfaEnabled =
        accountSession?.totpEnabled == true ||
        accountSession?.mfaEnabled == true;
    final syncScope = accountState?.profileScope.trim().isNotEmpty == true
        ? accountState!.profileScope.trim()
        : appText('待同步', 'Pending sync');
    final sessionLabel = appText(
      '已登录：${accountSession?.email.trim().isNotEmpty == true ? accountSession!.email.trim() : appText('当前账号', 'Current account')}',
      'Signed in: ${accountSession?.email.trim().isNotEmpty == true ? accountSession!.email.trim() : appText('Current account', 'Current account')}',
    );
    final syncLabel = accountState == null
        ? appText('idle · 尚未同步远程配置', 'idle · Remote config not synced yet')
        : '${accountState.syncState} · ${accountState.syncMessage}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          accountSession?.email.trim().isNotEmpty == true
              ? accountSession!.email.trim()
              : appText('本地操作员', 'Local Operator'),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          appText(
            '这里继续只负责账号身份、MFA 与云端默认配置同步状态。设置页面主体层级保持不变，连接来源和覆盖策略仍在下方标签内管理。',
            'This card now owns identity, MFA, and cloud-default sync state while keeping the surrounding settings hierarchy unchanged.',
          ),
        ),
        const SizedBox(height: 14),
        Text(sessionLabel, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 4),
        Text(syncLabel, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                appText('登录状态摘要', 'Login Status Summary'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Text(
                '${appText('服务地址', 'Service URL')}: ${serviceUrl.isEmpty ? appText('待配置', 'Pending') : serviceUrl}',
                key: const ValueKey('settings-account-summary-service-url'),
              ),
              const SizedBox(height: 6),
              Text(
                '${appText('账户标识', 'Account Identifier')}: ${accountIdentifier.isEmpty ? appText('待登录', 'Not signed in') : accountIdentifier}',
                key: const ValueKey(
                  'settings-account-summary-account-identifier',
                ),
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
              _buildTokenConfiguredSummary(accountState),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.tonal(
              key: const ValueKey('settings-account-sync-button'),
              onPressed: accountBusy
                  ? null
                  : () => _syncAccount(currentSettings),
              child: Text(appText('重新同步', 'Sync Again')),
            ),
            FilledButton.tonal(
              key: const ValueKey('settings-account-logout-button'),
              onPressed: accountBusy || !accountSignedIn
                  ? null
                  : _logoutAccount,
              child: Text(appText('退出登录', 'Log Out')),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        controller,
        controller.settingsController,
      ]),
      builder: (context, _) {
        final currentSettings = controller.settings;
        _syncAccountControllers(currentSettings);
        final accountState = controller.settingsController.accountSyncState;
        final accountBusy = controller.settingsController.accountBusy;
        final accountSignedIn = controller.settingsController.accountSignedIn;
        final accountMfaRequired =
            controller.settingsController.accountMfaRequired;
        final accountSession = controller.settingsController.accountSession;
        final cloudSync = currentSettings.acpBridgeServerModeConfig.cloudSynced;
        final remoteSummary = cloudSync.remoteServerSummary.endpoint.trim();
        final accountSignedOutLoginMode =
            !accountSignedIn && !accountMfaRequired;

        return SettingsPageBodyShell(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          breadcrumbs: buildSettingsBreadcrumbs(
            controller,
            tab: SettingsTab.gateway,
            detail: null,
            navigationContext: null,
          ),
          title: appText('设置', 'Settings'),
          subtitle: appText(
            '配置 XWorkmate 工作区、网关默认项、界面与诊断选项',
            'Configure XWorkmate workspace, gateway defaults, and diagnostics.',
          ),
          trailing: SizedBox(
            width: 220,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: appText('搜索设置', 'Search settings'),
                prefixIcon: const Icon(Icons.search_rounded),
              ),
            ),
          ),
          bodyChildren: <Widget>[
            SectionTabs(
              items: <String>[
                appText('用户登录状态', 'User Login State'),
                appText('基础连接配置', 'Base Connection Configuration'),
              ],
              value: _integrationTab == _SettingsIntegrationTab.accountStatus
                  ? appText('用户登录状态', 'User Login State')
                  : appText('基础连接配置', 'Base Connection Configuration'),
              onChanged: (value) {
                setState(() {
                  _integrationTab =
                      value == appText('用户登录状态', 'User Login State')
                      ? _SettingsIntegrationTab.accountStatus
                      : _SettingsIntegrationTab.baseConnection;
                });
              },
            ),
            const SizedBox(height: 16),
            if (_integrationTab == _SettingsIntegrationTab.accountStatus)
              SurfaceCard(
                key: const ValueKey('settings-account-status-card'),
                child: accountSignedOutLoginMode
                    ? _buildSignedOutAccountCard(
                        context,
                        currentSettings,
                        accountBusy,
                      )
                    : accountMfaRequired
                    ? _buildPendingMfaAccountCard(
                        context,
                        currentSettings,
                        accountBusy,
                      )
                    : _buildSignedInAccountCard(
                        context,
                        currentSettings,
                        accountSession,
                        accountState,
                        accountBusy,
                        accountSignedIn,
                      ),
              )
            else
              SurfaceCard(
                key: const ValueKey('settings-base-connection-card'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      appText('基础连接配置', 'Base Connection Configuration'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      appText(
                        '这里维护默认连接来源与默认凭据。当前默认 UI 仅展示 svc.plus 提供的托管配置入口。',
                        'Default connection source and credentials are managed here. The current UI only exposes svc.plus managed configuration.',
                      ),
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton(
                      onPressed: null,
                      child: Text(
                        appText('svc.plus 提供', 'Provided by svc.plus'),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        Chip(
                          label: Text(
                            appText(
                              '默认连接来源: svc.plus 提供',
                              'Default source: svc.plus',
                            ),
                          ),
                        ),
                        Chip(
                          label: Text(
                            '${appText('同步状态', 'Sync')}: ${accountState?.syncState ?? 'idle'}',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      appText(
                        '当前默认来源为 svc.plus 提供的托管配置。你可以直接同步远端默认配置。',
                        'The current default source is the managed svc.plus profile. You can sync remote defaults directly.',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${appText('远端摘要', 'Remote Summary')}: ${remoteSummary.isEmpty ? appText('待同步', 'Pending sync') : remoteSummary}',
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${appText('最近同步', 'Last Sync')}: ${_formatSyncTime(cloudSync.lastSyncAt)}',
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        FilledButton.tonal(
                          key: const ValueKey('settings-base-sync-button'),
                          onPressed: accountBusy
                              ? null
                              : () => _syncAccount(currentSettings),
                          child: Text(appText('重新同步', 'Sync Again')),
                        ),
                        FilledButton.tonal(
                          key: const ValueKey(
                            'settings-base-disconnect-button',
                          ),
                          onPressed: accountBusy
                              ? null
                              : () => _disconnectManagedBase(currentSettings),
                          child: Text(appText('断开', 'Disconnect')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  String _formatSyncTime(int lastSyncAtMs) {
    if (lastSyncAtMs <= 0) {
      return appText('尚未同步', 'Not synced yet');
    }
    return DateTime.fromMillisecondsSinceEpoch(
      lastSyncAtMs,
    ).toLocal().toIso8601String();
  }
}
