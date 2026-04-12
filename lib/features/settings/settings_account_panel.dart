import 'package:flutter/material.dart';

import '../../i18n/app_language.dart';
import '../../runtime/runtime_models.dart';

class SettingsAccountPanel extends StatelessWidget {
  const SettingsAccountPanel({
    super.key,
    required this.settings,
    required this.accountSession,
    required this.accountState,
    required this.accountBusy,
    required this.accountSignedIn,
    required this.accountMfaRequired,
    required this.accountBaseUrlController,
    required this.accountIdentifierController,
    required this.accountPasswordController,
    required this.accountMfaCodeController,
    required this.onSaveAccountProfile,
    required this.onLogin,
    required this.onVerifyMfa,
    required this.onCancelMfa,
    required this.onSync,
    required this.onLogout,
  });

  final SettingsSnapshot settings;
  final AccountSessionSummary? accountSession;
  final AccountSyncState? accountState;
  final bool accountBusy;
  final bool accountSignedIn;
  final bool accountMfaRequired;
  final TextEditingController accountBaseUrlController;
  final TextEditingController accountIdentifierController;
  final TextEditingController accountPasswordController;
  final TextEditingController accountMfaCodeController;
  final Future<void> Function() onSaveAccountProfile;
  final Future<void> Function() onLogin;
  final Future<void> Function() onVerifyMfa;
  final Future<void> Function() onCancelMfa;
  final Future<void> Function() onSync;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
    if (!accountSignedIn && !accountMfaRequired) {
      return _SignedOutAccountPanel(
        accountBusy: accountBusy,
        accountBaseUrlController: accountBaseUrlController,
        accountIdentifierController: accountIdentifierController,
        accountPasswordController: accountPasswordController,
        onSaveAccountProfile: onSaveAccountProfile,
        onLogin: onLogin,
      );
    }
    if (accountMfaRequired) {
      return _PendingMfaAccountPanel(
        accountBusy: accountBusy,
        accountBaseUrlController: accountBaseUrlController,
        accountIdentifierController: accountIdentifierController,
        accountMfaCodeController: accountMfaCodeController,
        onVerifyMfa: onVerifyMfa,
        onCancelMfa: onCancelMfa,
      );
    }
    return _SignedInAccountPanel(
      settings: settings,
      accountSession: accountSession,
      accountState: accountState,
      accountBusy: accountBusy,
      onSync: onSync,
      onLogout: onLogout,
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
  final Future<void> Function() onSaveAccountProfile;
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
              appText('账号登录', 'Account Sign In'),
              style: theme.textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              appText(
                '登录后可直接同步 svc.plus 托管连接配置。',
                'Sign in to sync the managed svc.plus connection profile.',
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
              onFieldSubmitted: (_) => onSaveAccountProfile(),
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const ValueKey('settings-account-identifier-field'),
              controller: accountIdentifierController,
              decoration: InputDecoration(
                labelText: appText('邮箱或账号', 'Email or Username'),
                prefixIcon: const Icon(Icons.person_outline_rounded),
              ),
              onFieldSubmitted: (_) => onSaveAccountProfile(),
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
                child: Text(appText('登录', 'Sign In')),
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
                  child: Text(appText('验证并同步', 'Verify & Sync')),
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
    required this.onSync,
    required this.onLogout,
  });

  final SettingsSnapshot settings;
  final AccountSessionSummary? accountSession;
  final AccountSyncState? accountState;
  final bool accountBusy;
  final Future<void> Function() onSync;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
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
    final mfaEnabled =
        accountSession?.totpEnabled == true ||
        accountSession?.mfaEnabled == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          appText('账号登录与同步', 'Account Sign In & Sync'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          appText(
            '登录身份和 svc.plus 托管连接同步已合并到这里，直接查看状态并执行重新同步或断开。',
            'Identity and managed svc.plus connection sync now live together here.',
          ),
        ),
        const SizedBox(height: 16),
        Text(
          accountSession?.email.trim().isNotEmpty == true
              ? accountSession!.email.trim()
              : appText('当前账号', 'Current account'),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          '${appText('同步状态', 'Sync Status')}: $syncState · $syncMessage',
          key: const ValueKey('settings-account-sync-status'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
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
                appText('登录与同步状态', 'Login and Sync Status'),
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
                '${appText('连接来源', 'Connection Source')}: ${appText('svc.plus 托管配置', 'svc.plus managed profile')}',
                key: const ValueKey(
                  'settings-account-summary-connection-source',
                ),
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
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.tonal(
              key: const ValueKey('settings-account-sync-button'),
              onPressed: accountBusy ? null : () => onSync(),
              child: Text(appText('重新同步', 'Sync Again')),
            ),
            TextButton(
              key: const ValueKey('settings-account-logout-button'),
              onPressed: accountBusy ? null : () => onLogout(),
              child: Text(appText('退出登录', 'Log Out')),
            ),
          ],
        ),
      ],
    );
  }
}

class _TokenConfiguredSummary extends StatelessWidget {
  const _TokenConfiguredSummary({required this.accountState});

  final AccountSyncState? accountState;

  @override
  Widget build(BuildContext context) {
    final configured = <String>[
      if (accountState?.tokenConfigured.bridge == true)
        appText('Bridge Token', 'Bridge Token'),
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
}

String _formatSyncTime(int lastSyncAtMs) {
  if (lastSyncAtMs <= 0) {
    return appText('尚未同步', 'Not synced yet');
  }
  return DateTime.fromMillisecondsSinceEpoch(
    lastSyncAtMs,
  ).toLocal().toIso8601String();
}
