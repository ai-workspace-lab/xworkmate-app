import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:xworkmate/app/app_controller_desktop_core.dart';
import 'package:xworkmate/features/settings/settings_page.dart';
import 'package:xworkmate/i18n/app_language.dart';
import 'package:xworkmate/models/app_models.dart';
import 'package:xworkmate/runtime/runtime_controllers_settings.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';
import 'package:xworkmate/theme/app_theme.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'settings page keeps canonical account status and logout behavior aligned',
    (tester) async {
      final fixtures = _buildSettingsPageFixtures();
      final controller = fixtures.controller;
      final canonicalSettings = fixtures.canonicalSettings;

      final staleDraft = canonicalSettings.copyWith(
        accountBaseUrl: 'https://draft-accounts.svc.plus',
        accountUsername: 'draft@svc.plus',
        acpBridgeServerModeConfig: canonicalSettings.acpBridgeServerModeConfig
            .copyWith(
              cloudSynced: canonicalSettings
                  .acpBridgeServerModeConfig
                  .cloudSynced
                  .copyWith(
                    accountBaseUrl: 'https://draft-accounts.svc.plus',
                    accountIdentifier: 'draft@svc.plus',
                    lastSyncAt: 987654321,
                    remoteServerSummary:
                        const AcpBridgeServerRemoteServerSummary(
                          endpoint: 'wss://draft-gateway.svc.plus',
                          hasAdvancedOverrides: true,
                        ),
                  ),
            ),
      );
      await controller.saveSettingsDraft(staleDraft);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(platform: TargetPlatform.macOS),
          home: Scaffold(
            body: RepaintBoundary(
              key: const ValueKey('settings-page-boundary'),
              child: SizedBox(
                width: 1600,
                height: 1200,
                child: SettingsPage(controller: controller),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      final serviceUrlText = tester.widget<Text>(
        find.byKey(const ValueKey('settings-account-summary-service-url')),
      );
      final accountIdentifierText = tester.widget<Text>(
        find.byKey(
          const ValueKey('settings-account-summary-account-identifier'),
        ),
      );
      expect(serviceUrlText.data ?? '', contains('https://accounts.svc.plus'));
      expect(
        serviceUrlText.data ?? '',
        isNot(contains('https://draft-accounts.svc.plus')),
      );
      expect(accountIdentifierText.data ?? '', contains('canonical@svc.plus'));
      expect(
        accountIdentifierText.data ?? '',
        isNot(contains('draft@svc.plus')),
      );

      await controller.settingsController.syncAccountSettings(
        baseUrl: controller.settings.accountBaseUrl,
      );
      await tester.pump();

      expect(
        controller.settingsController.syncedBaseUrls,
        contains('https://accounts.svc.plus'),
      );
      expect(
        controller.settingsController.syncedBaseUrls,
        isNot(contains('https://draft-accounts.svc.plus')),
      );

      await controller.settingsController.logoutAccount();
      await tester.pump();

      expect(find.text('未登录'), findsOneWidget);
      final loggedOutButton = tester.widget<FilledButton>(
        find.byKey(const ValueKey('settings-account-logout-button')),
      );
      expect(loggedOutButton.onPressed, isNull);
    },
  );
}

SettingsSnapshot _buildCanonicalSettings() {
  final defaults = SettingsSnapshot.defaults();
  return defaults.copyWith(
    accountBaseUrl: 'https://accounts.svc.plus',
    accountUsername: 'canonical@svc.plus',
    accountLocalMode: false,
    acpBridgeServerModeConfig: defaults.acpBridgeServerModeConfig.copyWith(
      cloudSynced: defaults.acpBridgeServerModeConfig.cloudSynced.copyWith(
        accountBaseUrl: 'https://accounts.svc.plus',
        accountIdentifier: 'canonical@svc.plus',
        lastSyncAt: 123456789,
        remoteServerSummary: const AcpBridgeServerRemoteServerSummary(
          endpoint: 'wss://gateway.svc.plus',
          hasAdvancedOverrides: false,
        ),
      ),
    ),
  );
}

_SettingsPageFixtures _buildSettingsPageFixtures() {
  final canonicalSettings = _buildCanonicalSettings().copyWith(
    appLanguage: AppLanguage.zh,
  );
  final settingsController = _FakeSettingsController()
    ..seedSignedInState(canonicalSettings);
  final controller = _FakeSettingsPageController(
    settingsController: settingsController,
    settingsDraft: canonicalSettings,
  );
  addTearDown(() {
    controller.dispose();
    settingsController.dispose();
  });
  return _SettingsPageFixtures(
    controller: controller,
    canonicalSettings: canonicalSettings,
  );
}

class _SettingsPageFixtures {
  _SettingsPageFixtures({
    required this.controller,
    required this.canonicalSettings,
  });

  final _FakeSettingsPageController controller;
  final SettingsSnapshot canonicalSettings;
}

class _FakeSettingsPageController extends ChangeNotifier
    implements AppController {
  _FakeSettingsPageController({
    required this.settingsController,
    required SettingsSnapshot settingsDraft,
  }) : _settingsDraft = settingsDraft;

  @override
  final _FakeSettingsController settingsController;
  SettingsSnapshot _settingsDraft;

  @override
  SettingsSnapshot get settings => settingsController.snapshot;

  @override
  SettingsSnapshot get settingsDraft => _settingsDraft;

  Future<void> saveSettingsDraft(SettingsSnapshot snapshot) async {
    _settingsDraft = snapshot;
    notifyListeners();
  }

  Future<void> saveSettings(SettingsSnapshot snapshot) async {
    settingsController.snapshotInternal = snapshot;
    _settingsDraft = snapshot;
    notifyListeners();
  }

  @override
  void navigateHome() {}

  @override
  void openSettings({
    SettingsTab tab = SettingsTab.gateway,
    SettingsDetailPage? detail,
    SettingsNavigationContext? navigationContext,
  }) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSettingsController extends SettingsController {
  _FakeSettingsController()
    : super(SecureConfigStore(enableSecureStorage: false));

  final List<String> syncedBaseUrls = <String>[];

  void seedSignedInState(SettingsSnapshot settings) {
    snapshotInternal = settings;
    lastSnapshotJsonInternal = settings.toJsonString();
    accountSessionTokenInternal = 'session-token';
    accountSessionInternal = const AccountSessionSummary(
      userId: 'u-1',
      email: 'canonical@svc.plus',
      name: 'Canonical',
      role: 'member',
      mfaEnabled: false,
    );
    accountSyncStateInternal = AccountSyncState.defaults().copyWith(
      syncState: 'ready',
      syncMessage: 'Remote defaults synced',
      lastSyncAtMs: 123456789,
      lastSyncSource: 'https://accounts.svc.plus',
      syncedDefaults: AccountRemoteProfile.defaults().copyWith(
        openclawUrl: 'wss://gateway.svc.plus',
        apisixUrl: 'https://apisix.svc.plus',
      ),
    );
    accountStatusInternal = 'Signed in as canonical@svc.plus';
    accountBusyInternal = false;
    pendingAccountMfaTicketInternal = '';
    pendingAccountBaseUrlInternal = '';
  }

  Future<AccountSyncResult> syncAccountSettings({String baseUrl = ''}) async {
    syncedBaseUrls.add(baseUrl);
    accountBusyInternal = true;
    notifyListeners();
    accountSyncStateInternal = AccountSyncState.defaults().copyWith(
      syncState: 'ready',
      syncMessage: 'Remote defaults synced',
      lastSyncAtMs: 123456789,
      lastSyncSource: baseUrl,
      syncedDefaults: AccountRemoteProfile.defaults().copyWith(
        openclawUrl: 'wss://gateway.svc.plus',
        apisixUrl: 'https://apisix.svc.plus',
      ),
    );
    accountBusyInternal = false;
    final email = accountSessionInternal?.email.trim() ?? '';
    accountStatusInternal = email.isEmpty ? 'Signed in' : 'Signed in as $email';
    notifyListeners();
    return const AccountSyncResult(
      state: 'ready',
      message: 'Remote defaults synced',
    );
  }

  Future<void> logoutAccount() async {
    accountSessionTokenInternal = '';
    accountSessionInternal = null;
    accountSyncStateInternal = null;
    accountStatusInternal = 'Signed out';
    pendingAccountMfaTicketInternal = '';
    pendingAccountBaseUrlInternal = '';
    notifyListeners();
  }
}
