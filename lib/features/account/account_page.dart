import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/app_metadata.dart';
import '../../i18n/app_language.dart';
import '../../models/app_models.dart';
import '../../runtime/runtime_controllers.dart';
import '../../runtime/runtime_models.dart';
import '../../widgets/section_tabs.dart';
import '../../widgets/surface_card.dart';
import '../../widgets/top_bar.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  AccountTab _tab = AccountTab.profile;
  late final TextEditingController _accountBaseUrlController;
  late final TextEditingController _accountUsernameController;
  late final TextEditingController _accountPasswordController;
  late final TextEditingController _accountMfaCodeController;
  late final TextEditingController _accountWorkspaceController;
  String _lastSavedAccountBaseUrl = '';
  String _lastSavedAccountUsername = '';
  String _lastSavedAccountWorkspace = '';

  @override
  void initState() {
    super.initState();
    final settings = widget.controller.settings;
    _lastSavedAccountBaseUrl = settings.accountBaseUrl;
    _lastSavedAccountUsername = settings.accountUsername;
    _lastSavedAccountWorkspace = settings.accountWorkspace;
    _accountBaseUrlController = TextEditingController(
      text: _lastSavedAccountBaseUrl,
    );
    _accountUsernameController = TextEditingController(
      text: _lastSavedAccountUsername,
    );
    _accountPasswordController = TextEditingController();
    _accountMfaCodeController = TextEditingController();
    _accountWorkspaceController = TextEditingController(
      text: _lastSavedAccountWorkspace,
    );
  }

  @override
  void dispose() {
    _accountBaseUrlController.dispose();
    _accountUsernameController.dispose();
    _accountPasswordController.dispose();
    _accountMfaCodeController.dispose();
    _accountWorkspaceController.dispose();
    super.dispose();
  }

  void _syncControllers(SettingsSnapshot settings) {
    if (_accountBaseUrlController.text == _lastSavedAccountBaseUrl &&
        settings.accountBaseUrl != _lastSavedAccountBaseUrl) {
      _accountBaseUrlController.text = settings.accountBaseUrl;
    }
    if (_accountUsernameController.text == _lastSavedAccountUsername &&
        settings.accountUsername != _lastSavedAccountUsername) {
      _accountUsernameController.text = settings.accountUsername;
    }
    if (_accountWorkspaceController.text == _lastSavedAccountWorkspace &&
        settings.accountWorkspace != _lastSavedAccountWorkspace) {
      _accountWorkspaceController.text = settings.accountWorkspace;
    }
    _lastSavedAccountBaseUrl = settings.accountBaseUrl;
    _lastSavedAccountUsername = settings.accountUsername;
    _lastSavedAccountWorkspace = settings.accountWorkspace;
  }

  Future<void> _saveProfile(SettingsSnapshot settings) async {
    final nextSettings = settings.copyWith(
      accountBaseUrl: _accountBaseUrlController.text.trim(),
      accountUsername: _accountUsernameController.text.trim(),
    );
    await widget.controller.saveSettings(nextSettings);
    _lastSavedAccountBaseUrl = nextSettings.accountBaseUrl;
    _lastSavedAccountUsername = nextSettings.accountUsername;
  }

  Future<void> _saveWorkspace(SettingsSnapshot settings) async {
    final nextSettings = settings.copyWith(
      accountWorkspace: _accountWorkspaceController.text.trim(),
    );
    await widget.controller.saveSettings(nextSettings);
    _lastSavedAccountWorkspace = nextSettings.accountWorkspace;
  }

  Future<void> _loginAccount(SettingsSnapshot settings) async {
    await _saveProfile(settings);
    try {
      await widget.controller.settingsController.loginAccount(
        baseUrl: _accountBaseUrlController.text.trim(),
        identifier: _accountUsernameController.text.trim(),
        password: _accountPasswordController.text,
      );
    } finally {
      _accountPasswordController.clear();
    }
  }

  Future<void> _verifyAccountMfa() async {
    try {
      await widget.controller.settingsController.verifyAccountMfa(
        baseUrl: _accountBaseUrlController.text.trim(),
        code: _accountMfaCodeController.text.trim(),
      );
    } finally {
      _accountMfaCodeController.clear();
    }
  }

  Future<void> _syncAccountSettings(SettingsSnapshot settings) async {
    await _saveProfile(settings);
    await widget.controller.settingsController.syncAccountSettings(
      baseUrl: _accountBaseUrlController.text.trim(),
    );
  }

  Future<void> _logoutAccount() async {
    await widget.controller.settingsController.logoutAccount();
    _accountPasswordController.clear();
    _accountMfaCodeController.clear();
  }

  Future<void> _cancelAccountMfa() async {
    await widget.controller.settingsController.cancelAccountMfaChallenge();
    _accountPasswordController.clear();
    _accountMfaCodeController.clear();
  }

  Widget _buildSignedOutLoginCard(BuildContext context, SettingsSnapshot settings) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 840),
        child: SurfaceCard(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
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
                key: const ValueKey('account-base-url-field'),
                controller: _accountBaseUrlController,
                decoration: InputDecoration(
                  labelText: appText('服务地址', 'Service URL'),
                  prefixIcon: const Icon(Icons.dns_outlined),
                ),
                onFieldSubmitted: (_) => _saveProfile(settings),
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('account-username-field'),
                controller: _accountUsernameController,
                decoration: InputDecoration(
                  labelText: appText('邮箱或账号', 'Email or Username'),
                  prefixIcon: const Icon(Icons.person_outline_rounded),
                ),
                onFieldSubmitted: (_) => _saveProfile(settings),
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('account-password-field'),
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
                  key: const ValueKey('account-login-button'),
                  onPressed: widget.controller.settingsController.accountBusy
                      ? null
                      : () => _loginAccount(settings),
                  child: Text(appText('登录', 'Sign In')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileCard(
    BuildContext context,
    SettingsSnapshot settings,
    bool accountBusy,
    bool accountSignedIn,
    bool accountMfaRequired,
    String signedInLabel,
    String profileDescription,
    String sessionStatusText,
    String syncStatusText,
  ) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            accountSignedIn
                ? signedInLabel
                : settings.accountUsername.trim().isEmpty
                ? appText('本地操作员', 'Local Operator')
                : settings.accountUsername,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            profileDescription,
          ),
          const SizedBox(height: 16),
          Text(
            sessionStatusText,
            key: const ValueKey('account-session-status'),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 6),
          Text(
            syncStatusText,
            key: const ValueKey('account-sync-status'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: const ValueKey('account-base-url-field'),
            controller: _accountBaseUrlController,
            readOnly: accountMfaRequired,
            decoration: InputDecoration(
              labelText: appText('服务地址', 'Service URL'),
            ),
            onFieldSubmitted: (_) => _saveProfile(settings),
          ),
          const SizedBox(height: 14),
          TextFormField(
            key: const ValueKey('account-username-field'),
            controller: _accountUsernameController,
            readOnly: accountMfaRequired,
            decoration: InputDecoration(
              labelText: appText('邮箱 / 用户名', 'Email / Username'),
            ),
            onFieldSubmitted: (_) => _saveProfile(settings),
          ),
          if (accountMfaRequired) ...[
            const SizedBox(height: 16),
            TextFormField(
              key: const ValueKey('account-mfa-code-field'),
              controller: _accountMfaCodeController,
              decoration: InputDecoration(
                labelText: appText('双重验证代码', 'MFA Code'),
              ),
              onFieldSubmitted: (_) => _verifyAccountMfa(),
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              if (accountMfaRequired)
                FilledButton.tonal(
                  key: const ValueKey('account-verify-mfa-button'),
                  onPressed: accountBusy ? null : _verifyAccountMfa,
                  child: Text(appText('验证并同步', 'Verify & Sync')),
                ),
              if (accountMfaRequired)
                FilledButton.tonal(
                  key: const ValueKey('account-edit-button'),
                  onPressed: accountBusy ? null : _cancelAccountMfa,
                  child: Text(
                    appText('返回编辑', 'Back to Edit'),
                  ),
                ),
              if (accountSignedIn)
                FilledButton.tonal(
                  key: const ValueKey('account-sync-button'),
                  onPressed: accountBusy
                      ? null
                      : () => _syncAccountSettings(settings),
                  child: Text(
                    appText('重新同步', 'Sync Again'),
                  ),
                ),
              if (accountSignedIn)
                FilledButton.tonal(
                  key: const ValueKey('account-logout-button'),
                  onPressed: accountBusy ? null : _logoutAccount,
                  child: Text(appText('退出登录', 'Log Out')),
                ),
            ],
          ),
        ],
      ),
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
        final settings = controller.settings;
        final settingsController = controller.settingsController;
        _syncControllers(settings);
        final accountSession = settingsController.accountSession;
        final accountSyncState = settingsController.accountSyncState;
        final accountBusy = settingsController.accountBusy;
        final accountSignedIn = settingsController.accountSignedIn;
        final accountMfaRequired = settingsController.accountMfaRequired;
        final accountSignedOutLoginMode = !accountSignedIn && !accountMfaRequired;
        final signedInLabel = accountSession?.email.trim().isNotEmpty == true
            ? accountSession!.email.trim()
            : accountSession?.name.trim().isNotEmpty == true
            ? accountSession!.name.trim()
            : appText('当前账号', 'Current account');
        final sessionStatusText = accountSignedIn
            ? appText('已登录：$signedInLabel', 'Signed in: $signedInLabel')
            : accountMfaRequired
            ? appText('等待双重验证', 'Waiting for MFA verification')
            : appText('未登录', 'Signed out');
        final syncStatusText = accountSyncState == null
            ? appText('idle · 尚未同步远程配置', 'idle · Remote config not synced yet')
            : '${accountSyncState.syncState} · ${accountSyncState.syncMessage}';
        final profileDescription = accountSignedIn
            ? appText(
                '已登录，远端配置作为默认值；本地保存项优先',
                'Signed in. Remote defaults apply first, and local saved values win.',
              )
            : accountMfaRequired
            ? appText(
                '请输入 MFA 验证码完成同步，也可以返回编辑账号信息。',
                'Enter the MFA code to finish sync, or return to edit account details.',
              )
            : settings.accountLocalMode
            ? appText(
                '本地模式 · 仅保存工作区偏好',
                'Local mode · saves workspace preferences only',
              )
            : appText(
                '登录后会同步远端默认配置，本地保存项可以覆盖远端默认值。',
                'Signing in syncs remote defaults, and local saved values can override them.',
              );
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(32, 32, 32, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TopBar(
                breadcrumbs: [
                  AppBreadcrumbItem(
                    label: appText('主页', 'Home'),
                    icon: Icons.home_rounded,
                    onTap: controller.navigateHome,
                  ),
                  AppBreadcrumbItem(label: appText('账号', 'Account')),
                  AppBreadcrumbItem(label: _tab.label),
                ],
                title: appText('账号', 'Account'),
                subtitle: appText(
                  '用户身份、工作区切换与登录会话。',
                  'Identity, workspace switching, and sign-in sessions.',
                ),
              ),
              const SizedBox(height: 24),
              SectionTabs(
                items: AccountTab.values.map((item) => item.label).toList(),
                value: _tab.label,
                size: SectionTabsSize.small,
                onChanged: (value) => setState(
                  () => _tab = AccountTab.values.firstWhere(
                    (item) => item.label == value,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              if (_tab == AccountTab.profile)
                accountSignedOutLoginMode
                ? _buildSignedOutLoginCard(context, settings)
                : _buildProfileCard(
                    context,
                    settings,
                    accountBusy,
                    accountSignedIn,
                    accountMfaRequired,
                    signedInLabel,
                    profileDescription,
                    sessionStatusText,
                    syncStatusText,
                  ),
              if (_tab == AccountTab.workspace)
                SurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        settings.accountWorkspace,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        appText(
                          '$kProductBrandName 的工作区外壳',
                          'Workspace shell for $kProductBrandName',
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const ValueKey('account-workspace-field'),
                        controller: _accountWorkspaceController,
                        decoration: InputDecoration(
                          labelText: appText('工作区名称', 'Workspace Label'),
                        ),
                        onFieldSubmitted: (_) => _saveWorkspace(settings),
                      ),
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton(
                          onPressed: () => _saveWorkspace(settings),
                          child: Text(appText('保存工作区', 'Save Workspace')),
                        ),
                      ),
                    ],
                  ),
                ),
              if (_tab == AccountTab.sessions)
                if (controller.sessions.isEmpty)
                  SurfaceCard(
                    child: Text(
                      appText(
                        '还没有 Gateway 会话。请先连接并开始一次对话。',
                        'No gateway sessions yet. Connect and start a chat first.',
                      ),
                    ),
                  )
                else
                  ...controller.sessions.map(
                    (session) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: SurfaceCard(
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    session.label,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '${session.surface ?? appText('会话', 'Session')} · ${session.kind ?? 'chat'}',
                                  ),
                                ],
                              ),
                            ),
                            Text(session.model ?? appText('网关', 'gateway')),
                          ],
                        ),
                      ),
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }
}
