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
    await widget.controller.settingsController.loginAccount(
      baseUrl: _accountBaseUrlController.text.trim(),
      identifier: _accountUsernameController.text.trim(),
      password: _accountPasswordController.text,
    );
  }

  Future<void> _verifyAccountMfa() async {
    await widget.controller.settingsController.verifyAccountMfa(
      baseUrl: _accountBaseUrlController.text.trim(),
      code: _accountMfaCodeController.text.trim(),
    );
  }

  Future<void> _syncAccountManagedSecrets(SettingsSnapshot settings) async {
    await _saveProfile(settings);
    await widget.controller.settingsController.syncAccountManagedSecrets(
      baseUrl: _accountBaseUrlController.text.trim(),
    );
  }

  Future<void> _logoutAccount() async {
    await widget.controller.settingsController.logoutAccount();
    _accountPasswordController.clear();
    _accountMfaCodeController.clear();
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
        final accountProfile = settingsController.accountProfile;
        final accountBusy = settingsController.accountBusy;
        final accountSignedIn = settingsController.accountSignedIn;
        final accountMfaRequired = settingsController.accountMfaRequired;
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
        final syncStatusText = accountProfile == null
            ? appText('idle · 尚未同步远程配置', 'idle · Remote config not synced yet')
            : '${accountProfile.syncState} · ${accountProfile.syncMessage}';
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
                SurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        settings.accountUsername.trim().isEmpty
                            ? appText('本地操作员', 'Local Operator')
                            : settings.accountUsername,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        settings.accountLocalMode
                            ? appText(
                                '本地模式 · 仅保存账号入口与工作区偏好',
                                'Local mode · saves account entry and workspace preferences only',
                              )
                            : appText(
                                '统一账号地址已配置，可作为后续接入入口',
                                'Unified account base URL is configured for future integration',
                              ),
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
                        decoration: InputDecoration(
                          labelText: appText('服务地址', 'Service URL'),
                        ),
                        onFieldSubmitted: (_) => _saveProfile(settings),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        key: const ValueKey('account-username-field'),
                        controller: _accountUsernameController,
                        decoration: InputDecoration(
                          labelText: appText('邮箱 / 用户名', 'Email / Username'),
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
                        ),
                        onFieldSubmitted: (_) => _loginAccount(settings),
                      ),
                      if (accountMfaRequired) ...[
                        const SizedBox(height: 14),
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
                          FilledButton(
                            key: const ValueKey('account-login-button'),
                            onPressed: accountBusy
                                ? null
                                : () => _loginAccount(settings),
                            child: Text(appText('登录', 'Log In')),
                          ),
                          if (accountMfaRequired)
                            FilledButton.tonal(
                              key: const ValueKey('account-verify-mfa-button'),
                              onPressed: accountBusy ? null : _verifyAccountMfa,
                              child: Text(appText('验证 MFA', 'Verify MFA')),
                            ),
                          if (accountSignedIn)
                            FilledButton.tonal(
                              key: const ValueKey('account-sync-button'),
                              onPressed: accountBusy
                                  ? null
                                  : () => _syncAccountManagedSecrets(settings),
                              child: Text(
                                appText('同步远程配置', 'Sync Remote Config'),
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
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton(
                          onPressed: () => _saveProfile(settings),
                          child: Text(appText('保存本地入口', 'Save Local Entry')),
                        ),
                      ),
                    ],
                  ),
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
