import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/app_metadata.dart';
import '../../app/ui_feature_manifest.dart';
import '../../app/workspace_navigation.dart';
import '../../i18n/app_language.dart';
import '../../models/app_models.dart';
import '../../runtime/runtime_controllers.dart';
import '../../runtime/runtime_models.dart';
import '../../widgets/settings_page_shell.dart';
import '../../widgets/surface_card.dart';
import 'settings_account_panel.dart';
import 'settings_about_panel.dart';
import 'settings_archived_tasks_panel.dart';
import 'settings_remote_desktop_panel.dart';

Future<Map<String, dynamic>> loadBridgeMetadataForSettingsAbout({
  required Uri bridgeEndpoint,
  required Future<String?> Function(Uri endpoint) authorizationResolver,
  HttpClient Function()? clientFactory,
}) async {
  final pingEndpoint = bridgeEndpoint.replace(
    path: '/api/ping',
    query: null,
    fragment: null,
  );
  final authorizationHeader = await authorizationResolver(pingEndpoint);
  final normalizedAuthorizationHeader = _normalizeAuthorizationHeader(
    authorizationHeader ?? '',
  );
  if (normalizedAuthorizationHeader.isEmpty) {
    return const <String, dynamic>{
      'status': 'unavailable',
      'version': '',
      'commit': '',
      'image': '',
      'buildDate': '',
    };
  }

  final client = (clientFactory ?? HttpClient.new)()
    ..connectionTimeout = const Duration(seconds: 4);
  try {
    final request = await client
        .getUrl(pingEndpoint)
        .timeout(const Duration(seconds: 4));
    request.headers.set(
      HttpHeaders.authorizationHeader,
      normalizedAuthorizationHeader,
    );
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close().timeout(const Duration(seconds: 4));
    final body = await utf8
        .decodeStream(response)
        .timeout(const Duration(seconds: 4));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == HttpStatus.unauthorized ||
          response.statusCode == HttpStatus.forbidden) {
        return const <String, dynamic>{
          'status': 'unauthorized',
          'message': 'Bridge authorization rejected',
          'version': '',
          'commit': '',
          'image': '',
          'buildDate': '',
        };
      }
      return const <String, dynamic>{
        'status': 'unavailable',
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

String _normalizeAuthorizationHeader(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  final separatorIndex = trimmed.indexOf(RegExp(r'\s'));
  if (separatorIndex > 0 && separatorIndex < trimmed.length - 1) {
    final scheme = trimmed.substring(0, separatorIndex);
    if (RegExp(r"^[A-Za-z][A-Za-z0-9!#$%&'*+.^_`|~-]*$").hasMatch(scheme)) {
      return trimmed;
    }
  }
  return 'Bearer $trimmed';
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.controller,
    this.initialTab = SettingsTab.gateway,
  });

  final AppController controller;
  final SettingsTab initialTab;

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
    _lastSavedBridgeUrl =
        settings.acpBridgeServerModeConfig.selfHosted.serverUrl;
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
        .loadSecretValueByRef(
          widget
              .controller
              .settings
              .acpBridgeServerModeConfig
              .selfHosted
              .passwordRef,
        );
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

  Future<void> _persistAccountProfileSettings(
    SettingsSnapshot settings, {
    required bool isManualBridge,
  }) async {
    final nextSettings = await widget.controller.settingsController
        .buildSavedAccountProfileSettings(
          settings: settings,
          accountBaseUrl: _accountBaseUrlController.text,
          accountIdentifier: _accountIdentifierController.text,
          bridgeServerUrl: _bridgeUrlController.text,
          bridgeToken: _bridgeTokenController.text,
          isManualBridge: isManualBridge,
        );
    await widget.controller.saveSettings(
      nextSettings,
      refreshAfterSave: !isManualBridge,
    );

    _lastSavedAccountBaseUrl = nextSettings.accountBaseUrl;
    _lastSavedAccountIdentifier = nextSettings.accountUsername;
    _lastSavedBridgeUrl =
        nextSettings.acpBridgeServerModeConfig.selfHosted.serverUrl;
    if (isManualBridge &&
        nextSettings.acpBridgeServerModeConfig.selfHosted.isConfigured) {
      unawaited(_refreshBridgeCapabilities());
      await _refreshAboutSnapshot();
    }
  }

  Future<void> _loginAccount(SettingsSnapshot settings) async {
    final baseUrl = _accountBaseUrlController.text.trim();
    final identifier = _accountIdentifierController.text.trim();
    try {
      await _persistAccountProfileSettings(settings, isManualBridge: false);
      await widget.controller.settingsController.loginAccount(
        baseUrl: baseUrl,
        identifier: identifier,
        password: _accountPasswordController.text,
      );
      await _refreshBridgeCapabilities();
      await _verifyAccountBridgeRuntimeAccess();
    } finally {
      _accountPasswordController.clear();
    }
  }

  Future<void> _syncAccount(SettingsSnapshot settings) async {
    await _persistAccountProfileSettings(settings, isManualBridge: false);
    final result = await widget.controller.settingsController
        .syncAccountSettings(baseUrl: _accountBaseUrlController.text.trim());
    await _refreshBridgeCapabilities();
    if (result.state == 'ready') {
      await _verifyAccountBridgeRuntimeAccess();
    } else {
      await _refreshAboutSnapshot();
    }
  }

  Future<void> _verifyAccountMfa(SettingsSnapshot settings) async {
    try {
      await _persistAccountProfileSettings(settings, isManualBridge: false);
      await widget.controller.settingsController.verifyAccountMfa(
        baseUrl: _accountBaseUrlController.text.trim(),
        code: _accountMfaCodeController.text.trim(),
      );
      await _refreshBridgeCapabilities();
      await _verifyAccountBridgeRuntimeAccess();
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

  Future<void> _restoreArchivedTask(String sessionKey) async {
    await widget.controller.saveAssistantTaskArchived(sessionKey, false);
  }

  Future<void> _deleteArchivedTask(String sessionKey) async {
    await widget.controller.deleteArchivedAssistantTask(sessionKey);
  }

  Future<SettingsAboutSnapshot> _loadAboutSnapshot() async {
    final bridgeEndpoint =
        widget.controller.resolveGatewayAcpEndpointInternal() ??
        Uri.parse(kManagedBridgeServerUrl);
    final bridgeMetadata = await _loadBridgeMetadata(bridgeEndpoint);
    return SettingsAboutSnapshot(
      appVersion: kAppVersion,
      appBuildNumber: kAppBuildNumber,
      appBuildDate: kAppBuildDate,
      appCommit: kAppBuildCommit,
      bridgeEndpoint: bridgeEndpoint.toString(),
      bridgeStatus: _stringValue(bridgeMetadata['status']),
      bridgeVersion: _resolveBridgeVersion(bridgeMetadata),
      bridgeBuildDate: _resolveBridgeBuildDate(bridgeMetadata),
      bridgeCommit: _stringValue(bridgeMetadata['commit']),
      bridgeImage: _stringValue(bridgeMetadata['image']),
    );
  }

  Future<Map<String, dynamic>> _loadBridgeMetadata(Uri bridgeEndpoint) async {
    return loadBridgeMetadataForSettingsAbout(
      bridgeEndpoint: bridgeEndpoint,
      authorizationResolver:
          widget.controller.resolveGatewayAcpAuthorizationHeaderInternal,
    );
  }

  Future<void> _verifyAccountBridgeRuntimeAccess() async {
    if (!widget.controller.settingsController.accountSignedIn) {
      await _refreshAboutSnapshot();
      return;
    }
    final bridgeEndpoint =
        widget.controller.resolveGatewayAcpEndpointInternal() ??
        Uri.parse(kManagedBridgeServerUrl);
    final bridgeMetadata = await _loadBridgeMetadata(bridgeEndpoint);
    final status = _stringValue(bridgeMetadata['status']).toLowerCase();
    if (status == 'ok') {
      if (mounted) {
        setState(() {
          _aboutSnapshot = _aboutSnapshotFromMetadata(
            bridgeEndpoint,
            bridgeMetadata,
          );
          _aboutBusy = false;
        });
      }
      return;
    }
    if (status == 'unauthorized') {
      await widget.controller.settingsController
          .markAccountBridgeRuntimeUnavailable('Bridge authorization rejected');
    }
    if (mounted) {
      setState(() {
        _aboutSnapshot = _aboutSnapshotFromMetadata(
          bridgeEndpoint,
          bridgeMetadata,
        );
        _aboutBusy = false;
      });
    }
  }

  SettingsAboutSnapshot _aboutSnapshotFromMetadata(
    Uri bridgeEndpoint,
    Map<String, dynamic> bridgeMetadata,
  ) {
    return SettingsAboutSnapshot(
      appVersion: kAppVersion,
      appBuildNumber: kAppBuildNumber,
      appBuildDate: kAppBuildDate,
      appCommit: kAppBuildCommit,
      bridgeEndpoint: bridgeEndpoint.toString(),
      bridgeStatus: _stringValue(bridgeMetadata['status']),
      bridgeVersion: _resolveBridgeVersion(bridgeMetadata),
      bridgeBuildDate: _resolveBridgeBuildDate(bridgeMetadata),
      bridgeCommit: _stringValue(bridgeMetadata['commit']),
      bridgeImage: _stringValue(bridgeMetadata['image']),
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
        final accountStatus = controller.settingsController.accountStatus;
        final accountSignedIn = controller.settingsController.accountSignedIn;
        final accountMfaRequired =
            controller.settingsController.accountMfaRequired;
        final accountSession = controller.settingsController.accountSession;
        final currentTab = controller.settingsTab;
        final availableTabs = controller
            .featuresFor(resolveUiFeaturePlatformFromContext(context))
            .availableSettingsTabs;

        return SettingsPageBodyShell(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          breadcrumbs: buildSettingsBreadcrumbs(controller, tab: currentTab),
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
            if (availableTabs.length > 1) ...[
              _SettingsTabSelector(
                currentTab: currentTab,
                availableTabs: availableTabs,
                onChanged: (tab) => controller.openSettings(tab: tab),
              ),
              const SizedBox(height: 18),
            ],
            if (currentTab == SettingsTab.gateway) ...[
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
                      _persistAccountProfileSettings(
                        widget.controller.settings,
                        isManualBridge: isManualBridge,
                      ),
                  onLogin: () => _loginAccount(widget.controller.settings),
                  onVerifyMfa: () =>
                      _verifyAccountMfa(widget.controller.settings),
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
            ] else if (currentTab == SettingsTab.archivedTasks) ...[
              SurfaceCard(
                key: const ValueKey('settings-archived-tasks-panel-card'),
                child: SettingsArchivedTasksPanel(
                  sessions: controller.archivedAssistantSessions,
                  onRestore: _restoreArchivedTask,
                  onDelete: _deleteArchivedTask,
                ),
              ),
            ] else if (currentTab == SettingsTab.remoteDesktop) ...[
              SurfaceCard(
                key: const ValueKey('settings-remote-desktop-panel-card'),
                child: SettingsRemoteDesktopPanel(controller: controller),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _SettingsTabSelector extends StatelessWidget {
  const _SettingsTabSelector({
    required this.currentTab,
    required this.availableTabs,
    required this.onChanged,
  });

  final SettingsTab currentTab;
  final List<SettingsTab> availableTabs;
  final ValueChanged<SettingsTab> onChanged;

  @override
  Widget build(BuildContext context) {
    final selectedTab = availableTabs.contains(currentTab)
        ? currentTab
        : availableTabs.first;
    return Align(
      alignment: Alignment.centerLeft,
      child: SegmentedButton<SettingsTab>(
        key: const ValueKey('settings-tab-selector'),
        segments: [
          for (final tab in availableTabs)
            ButtonSegment<SettingsTab>(
              value: tab,
              icon: Icon(
                tab == SettingsTab.remoteDesktop
                    ? Icons.desktop_windows_outlined
                    : (tab == SettingsTab.archivedTasks
                        ? Icons.inventory_2_outlined
                        : Icons.hub_outlined),
              ),
              label: Text(tab.label),
            ),
        ],
        selected: <SettingsTab>{selectedTab},
        onSelectionChanged: (selection) {
          if (selection.isEmpty) {
            return;
          }
          final next = selection.first;
          if (next != selectedTab) {
            onChanged(next);
          }
        },
      ),
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
