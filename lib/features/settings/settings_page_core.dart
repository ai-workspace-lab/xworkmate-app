import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/workspace_navigation.dart';
import '../../i18n/app_language.dart';
import '../../models/app_models.dart';
import '../../runtime/runtime_controllers.dart';
import '../../runtime/runtime_models.dart';
import '../../widgets/settings_page_shell.dart';
import '../../widgets/surface_card.dart';
import 'settings_account_panel.dart';

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
            SurfaceCard(
              key: const ValueKey('settings-account-panel-card'),
              child: SettingsAccountPanel(
                settings: currentSettings,
                accountSession: accountSession,
                accountState: accountState,
                accountBusy: accountBusy,
                accountSignedIn: accountSignedIn,
                accountMfaRequired: accountMfaRequired,
                accountBaseUrlController: _accountBaseUrlController,
                accountIdentifierController: _accountIdentifierController,
                accountPasswordController: _accountPasswordController,
                accountMfaCodeController: _accountMfaCodeController,
                onSaveAccountProfile: () =>
                    _saveAccountProfile(currentSettings),
                onLogin: () => _loginAccount(currentSettings),
                onVerifyMfa: () => _verifyAccountMfa(currentSettings),
                onCancelMfa: _cancelAccountMfa,
                onSync: () => _syncAccount(currentSettings),
                onLogout: _logoutAccount,
              ),
            ),
          ],
        );
      },
    );
  }
}
