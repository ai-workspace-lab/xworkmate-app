import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/features/settings/settings_account_panel.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/theme/app_theme.dart';
import 'package:xworkmate/widgets/surface_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsAccountPanel golden', () {
    testWidgets('signed out state', (tester) async {
      final controllers = _TestControllers();
      addTearDown(controllers.dispose);

      await tester.pumpWidget(
        _buildGoldenHarness(
          child: SettingsAccountPanel(
            settings: SettingsSnapshot.defaults(),
            accountSession: null,
            accountState: null,
            accountBusy: false,
            accountSignedIn: false,
            accountMfaRequired: false,
            accountBaseUrlController: controllers.baseUrl,
            accountIdentifierController: controllers.identifier,
            accountPasswordController: controllers.password,
            accountMfaCodeController: controllers.mfaCode,
            onSaveAccountProfile: () async {},
            onLogin: () async {},
            onVerifyMfa: () async {},
            onCancelMfa: () async {},
            onSync: () async {},
            onDisconnect: () async {},
            onLogout: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/settings_account_panel/signed_out.png'),
      );
    });

    testWidgets('signed in managed state', (tester) async {
      final controllers = _TestControllers();
      addTearDown(controllers.dispose);

      final settings = SettingsSnapshot.defaults().copyWith(
        accountLocalMode: false,
        accountBaseUrl: 'https://accounts.svc.plus',
        accountUsername: 'review@svc.plus',
        acpBridgeServerModeConfig: AcpBridgeServerModeConfig.defaults()
            .copyWith(
              cloudSynced: AcpBridgeServerModeConfig.defaults().cloudSynced
                  .copyWith(
                    lastSyncAt: DateTime(
                      2026,
                      4,
                      12,
                      10,
                      0,
                    ).millisecondsSinceEpoch,
                    remoteServerSummary: AcpBridgeServerModeConfig.defaults()
                        .cloudSynced
                        .remoteServerSummary
                        .copyWith(endpoint: 'https://bridge.svc.plus'),
                  ),
            ),
      );

      await tester.pumpWidget(
        _buildGoldenHarness(
          child: SettingsAccountPanel(
            settings: settings,
            accountSession: const AccountSessionSummary(
              userId: 'u-1',
              email: 'review@svc.plus',
              name: 'Review User',
              role: 'operator',
              mfaEnabled: true,
              totpEnabled: true,
            ),
            accountState: AccountSyncState.defaults().copyWith(
              syncState: 'ready',
              syncMessage: 'Bridge access synced',
              profileScope: 'bridge',
              tokenConfigured: const AccountTokenConfigured(
                bridge: true,
                vault: false,
                apisix: false,
              ),
            ),
            accountBusy: false,
            accountSignedIn: true,
            accountMfaRequired: false,
            accountBaseUrlController: controllers.baseUrl,
            accountIdentifierController: controllers.identifier,
            accountPasswordController: controllers.password,
            accountMfaCodeController: controllers.mfaCode,
            onSaveAccountProfile: () async {},
            onLogin: () async {},
            onVerifyMfa: () async {},
            onCancelMfa: () async {},
            onSync: () async {},
            onDisconnect: () async {},
            onLogout: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          'goldens/settings_account_panel/signed_in_managed.png',
        ),
      );
    });
  });
}

Widget _buildGoldenHarness({required Widget child}) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: Material(
      child: Center(
        child: SizedBox(
          width: 1200,
          height: 900,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SurfaceCard(child: child),
          ),
        ),
      ),
    ),
  );
}

class _TestControllers {
  final TextEditingController baseUrl = TextEditingController(
    text: 'https://accounts.svc.plus',
  );
  final TextEditingController identifier = TextEditingController(
    text: 'review@svc.plus',
  );
  final TextEditingController password = TextEditingController();
  final TextEditingController mfaCode = TextEditingController();

  void dispose() {
    baseUrl.dispose();
    identifier.dispose();
    password.dispose();
    mfaCode.dispose();
  }
}
