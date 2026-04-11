import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:xworkmate/app/app_controller_desktop_core.dart';
import 'package:xworkmate/features/settings/settings_page.dart';
import 'package:xworkmate/i18n/app_language.dart';
import 'package:xworkmate/runtime/runtime_controllers_settings.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';
import 'package:xworkmate/theme/app_theme.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'settings login card reads canonical values instead of stale draft data',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1200));
      addTearDown(() async => tester.binding.setSurfaceSize(null));
      final fixtures = _buildSettingsPageFixtures();
      final controller = fixtures.controller;
      final canonicalSettings = fixtures.canonicalSettings;

      final staleDraft = canonicalSettings.copyWith(
        accountBaseUrl: 'https://draft-accounts.svc.plus',
        accountUsername: 'draft@svc.plus',
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

      final baseUrlField = tester.widget<TextFormField>(
        find.byKey(const ValueKey('settings-account-base-url-field')),
      );
      final identifierField = tester.widget<TextFormField>(
        find.byKey(const ValueKey('settings-account-identifier-field')),
      );

      expect(baseUrlField.controller?.text, 'https://accounts.svc.plus');
      expect(
        baseUrlField.controller?.text,
        isNot('https://draft-accounts.svc.plus'),
      );
      expect(identifierField.controller?.text, 'canonical@svc.plus');
      expect(identifierField.controller?.text, isNot('draft@svc.plus'));
    },
  );
}

SettingsSnapshot _buildCanonicalSettings() {
  final defaults = SettingsSnapshot.defaults();
  return defaults.copyWith(
    accountBaseUrl: 'https://accounts.svc.plus',
    accountUsername: 'canonical@svc.plus',
    accountLocalMode: true,
  );
}

_SettingsPageFixtures _buildSettingsPageFixtures() {
  final canonicalSettings = _buildCanonicalSettings().copyWith(
    appLanguage: AppLanguage.zh,
  );
  final settingsController = _FakeSettingsController()
    ..seedSignedOutState(canonicalSettings);
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

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSettingsController extends SettingsController {
  _FakeSettingsController()
    : super(SecureConfigStore(enableSecureStorage: false));

  void seedSignedOutState(SettingsSnapshot settings) {
    snapshotInternal = settings;
    lastSnapshotJsonInternal = settings.toJsonString();
    accountSessionTokenInternal = '';
    accountSessionInternal = null;
    accountSyncStateInternal = null;
    accountStatusInternal = 'Signed out';
    accountBusyInternal = false;
    pendingAccountMfaTicketInternal = '';
    pendingAccountBaseUrlInternal = '';
  }
}
