import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/app_metadata.dart';
import '../../app/workspace_navigation.dart';
import '../../i18n/app_language.dart';
import '../../models/app_models.dart';
import '../../runtime/runtime_controllers.dart';
import '../../runtime/runtime_models.dart';
import '../../widgets/settings_page_shell.dart';
import '../../widgets/surface_card.dart';
import 'settings_account_panel.dart';
import 'settings_about_panel.dart';

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
  late final TextEditingController _bridgeUrlController;
  late final TextEditingController _bridgeTokenController;
  SettingsAboutSnapshot _aboutSnapshot = const SettingsAboutSnapshot.defaults();
  bool _aboutBusy = false;
  String _lastSavedAccountBaseUrl = '';
  String _lastSavedAccountIdentifier = '';
  String _lastSavedBridgeUrl = '';

  @override
  void initState() {
    super.initState();
    final settings = widget.controller.settings;
    _lastSavedAccountBaseUrl = settings.accountBaseUrl;
    _lastSavedAccountIdentifier = settings.accountUsername;
    _lastSavedBridgeUrl = settings.acpBridgeServerModeConfig.selfHosted.serverUrl;
    _accountBaseUrlController = TextEditingController(
      text: _lastSavedAccountBaseUrl,
    );
    _accountIdentifierController = TextEditingController(
      text: _lastSavedAccountIdentifier,
    );
    _accountPasswordController = TextEditingController();
    _accountMfaCodeController = TextEditingController();
    _bridgeUrlController = TextEditingController(text: _lastSavedBridgeUrl);
    _bridgeTokenController = TextEditingController();
    unawaited(_refreshAboutSnapshot());
    unawaited(_loadBridgeToken());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _accountBaseUrlController.dispose();
    _accountIdentifierController.dispose();
    _accountPasswordController.dispose();
    _accountMfaCodeController.dispose();
    _bridgeUrlController.dispose();
    _bridgeTokenController.dispose();
    super.dispose();
  }

  Future<void> _loadBridgeToken() async {
    final token = await widget.controller.settingsController
        .loadSecretValueByRef(widget.controller.settings.acpBridgeServerModeConfig.selfHosted.passwordRef);
    if (mounted) {
      _bridgeTokenController.text = token;
    }
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

    final bridgeConfig = settings.acpBridgeServerModeConfig;
    if (_bridgeUrlController.text == _lastSavedBridgeUrl &&
        bridgeConfig.selfHosted.serverUrl != _lastSavedBridgeUrl) {
      _bridgeUrlController.text = bridgeConfig.selfHosted.serverUrl;
    }
    _lastSavedBridgeUrl = bridgeConfig.selfHosted.serverUrl;
  }

  Future<void> _saveAccountProfile(
    SettingsSnapshot settings, {
    required bool isManualBridge,
  }) async {
    final bridgeConfig = settings.acpBridgeServerModeConfig;
    var nextBridgeConfig = bridgeConfig.copyWith(
      selfHosted: bridgeConfig.selfHosted.copyWith(
        serverUrl: _bridgeUrlController.text.trim(),
        username: isManualBridge ? 'admin' : bridgeConfig.selfHosted.username,
      ),
    );

    // Resolve the effective config based on the new sources
    final nextEffective = widget.controller.settingsController.resolveAcpBridgeServerEffectiveConfig(
      config: nextBridgeConfig,
      accountSyncState: widget.controller.settingsController.accountSyncState,
    );

    final nextSettings = settings.copyWith(
      accountBaseUrl: _accountBaseUrlController.text.trim(),
      accountUsername: _accountIdentifierController.text.trim(),
      acpBridgeServerModeConfig: nextBridgeConfig.copyWith(
        effective: nextEffective,
      ),
    );
    if (isManualBridge && _bridgeTokenController.text.isNotEmpty) {
      await widget.controller.settingsController.saveSecretValueByRef(
        nextSettings.acpBridgeServerModeConfig.selfHosted.passwordRef,
        _bridgeTokenController.text,
        provider: 'Bridge',
        module: 'Manual',
      );
    }
    await widget.controller.saveSettings(nextSettings);

    _lastSavedAccountBaseUrl = nextSettings.accountBaseUrl;
    _lastSavedAccountIdentifier = nextSettings.accountUsername;
    _lastSavedBridgeUrl = nextSettings.acpBridgeServerModeConfig.selfHosted.serverUrl;
  }

  Future<void> _loginAccount(SettingsSnapshot settings) async {
    final baseUrl = _accountBaseUrlController.text.trim();
    final identifier = _accountIdentifierController.text.trim();
    try {
      await _saveAccountProfile(settings, isManualBridge: false);
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
    await _saveAccountProfile(settings, isManualBridge: false);
    await widget.controller.settingsController.syncAccountSettings(
      baseUrl: _accountBaseUrlController.text.trim(),
    );
    await _refreshBridgeCapabilities();
    await _refreshAboutSnapshot();
  }

  Future<void> _verifyAccountMfa(SettingsSnapshot settings) async {
    try {
      await _saveAccountProfile(settings, isManualBridge: false);
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
    await _refreshAboutSnapshot();
  }

  Future<void> _refreshAboutSnapshot() async {
    if (!mounted) {
      return;
    }
    setState(() {
      _aboutBusy = true;
    });
    final snapshot = await _loadAboutSnapshot();
    if (!mounted) {
      return;
    }
    setState(() {
      _aboutSnapshot = snapshot;
      _aboutBusy = false;
    });
  }

  Future<SettingsAboutSnapshot> _loadAboutSnapshot() async {
    final bridgeMetadata = await _loadBridgeMetadata();
    return SettingsAboutSnapshot(
      appVersion: kAppVersion,
      appBuildNumber: kAppBuildNumber,
      appBuildDate: kAppBuildDate,
      appCommit: kAppBuildCommit,
      bridgeEndpoint: kManagedBridgeServerUrl,
      bridgeStatus: _stringValue(bridgeMetadata['status']),
      bridgeVersion: _resolveBridgeVersion(bridgeMetadata),
      bridgeBuildDate: _resolveBridgeBuildDate(bridgeMetadata),
      bridgeCommit: _stringValue(bridgeMetadata['commit']),
      bridgeImage: _stringValue(bridgeMetadata['image']),
    );
  }

  Future<Map<String, dynamic>> _loadBridgeMetadata() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    try {
      final request = await client
          .getUrl(Uri.parse('$kManagedBridgeServerUrl/api/ping'))
          .timeout(const Duration(seconds: 4));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(const Duration(seconds: 4));
      final body = await utf8
          .decodeStream(response)
          .timeout(const Duration(seconds: 4));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return <String, dynamic>{
          'status': 'error',
          'version': '',
          'commit': '',
          'image': '',
          'buildDate': '',
        };
      }
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.cast<String, dynamic>();
      }
    } catch (_) {
      return const <String, dynamic>{
        'status': 'unavailable',
        'version': '',
        'commit': '',
        'image': '',
        'buildDate': '',
      };
    } finally {
      client.close(force: true);
    }
    return const <String, dynamic>{
      'status': 'unavailable',
      'version': '',
      'commit': '',
      'image': '',
      'buildDate': '',
    };
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
        final accountStatus = controller.settingsController.accountStatus;
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
                accountStatus: accountStatus,
                accountSignedIn: accountSignedIn,
                accountMfaRequired: accountMfaRequired,
                accountBaseUrlController: _accountBaseUrlController,
                accountIdentifierController: _accountIdentifierController,
                accountPasswordController: _accountPasswordController,
                accountMfaCodeController: _accountMfaCodeController,
                bridgeUrlController: _bridgeUrlController,
                bridgeTokenController: _bridgeTokenController,
                onSaveAccountProfile: ({required bool isManualBridge}) =>
                    _saveAccountProfile(
                      widget.controller.settings,
                      isManualBridge: isManualBridge,
                    ),
                onLogin: () => _loginAccount(widget.controller.settings),
                onVerifyMfa: () => _verifyAccountMfa(widget.controller.settings),
                onCancelMfa: _cancelAccountMfa,
                onSync: () => _syncAccount(widget.controller.settings),
                onLogout: _logoutAccount,
              ),
            ),
            const SizedBox(height: 24),
            SurfaceCard(
              key: const ValueKey('settings-about-panel-card'),
              child: SettingsAboutPanel(
                snapshot: _aboutSnapshot,
                busy: _aboutBusy,
                onRefresh: _refreshAboutSnapshot,
              ),
            ),
          ],
        );
      },
    );
  }
}

String _stringValue(Object? value) {
  return value == null ? '' : value.toString().trim();
}

String _resolveBridgeVersion(Map<String, dynamic> payload) {
  final explicit = _stringValue(payload['version']);
  if (explicit.isNotEmpty) {
    return explicit;
  }
  final tag = _stringValue(payload['tag']);
  if (tag.isNotEmpty) {
    return tag;
  }
  return '';
}

String _resolveBridgeBuildDate(Map<String, dynamic> payload) {
  final candidates = <Object?>[
    payload['buildDate'],
    payload['build-date'],
    payload['builtAt'],
    payload['build_at'],
  ];
  for (final candidate in candidates) {
    final value = _stringValue(candidate);
    if (value.isNotEmpty) {
      return value;
    }
  }
  return '';
}
