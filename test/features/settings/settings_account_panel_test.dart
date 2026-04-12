import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/features/settings/settings_account_panel.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/theme/app_theme.dart';
import 'package:xworkmate/widgets/surface_card.dart';

void main() {
  group('SettingsAccountPanel', () {
    testWidgets('shows login form and triggers login when signed out', (
      tester,
    ) async {
      final controllers = _TestControllers();
      addTearDown(controllers.dispose);

      var loginCount = 0;

      await tester.pumpWidget(
        _buildTestApp(
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
            onLogin: () async {
              loginCount += 1;
            },
            onVerifyMfa: () async {},
            onCancelMfa: () async {},
            onSync: () async {},
            onDisconnect: () async {},
            onLogout: () async {},
          ),
        ),
      );

      expect(find.text('账号登录'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('settings-account-login-button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-account-sync-button')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('settings-account-disconnect-button')),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const ValueKey('settings-account-login-button')),
      );
      await tester.pump();

      expect(loginCount, 1);
    });

    testWidgets('shows sync and disconnect actions for managed account state', (
      tester,
    ) async {
      final controllers = _TestControllers();
      addTearDown(controllers.dispose);

      var syncCount = 0;
      var disconnectCount = 0;

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
        _buildTestApp(
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
            onSync: () async {
              syncCount += 1;
            },
            onDisconnect: () async {
              disconnectCount += 1;
            },
            onLogout: () async {},
          ),
        ),
      );

      expect(find.text('账号登录与同步'), findsOneWidget);
      expect(find.textContaining('svc.plus 托管配置'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('settings-account-sync-button')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('settings-account-disconnect-button')),
      );
      await tester.pump();

      expect(syncCount, 1);
      expect(disconnectCount, 1);
    });

    testWidgets('disables disconnect when account already uses local config', (
      tester,
    ) async {
      final controllers = _TestControllers();
      addTearDown(controllers.dispose);

      await tester.pumpWidget(
        _buildTestApp(
          child: SettingsAccountPanel(
            settings: SettingsSnapshot.defaults().copyWith(
              accountUsername: 'review@svc.plus',
            ),
            accountSession: const AccountSessionSummary(
              userId: 'u-1',
              email: 'review@svc.plus',
              name: 'Review User',
              role: 'operator',
              mfaEnabled: false,
            ),
            accountState: AccountSyncState.defaults().copyWith(
              syncState: 'ready',
              syncMessage: 'Bridge access synced',
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

      expect(find.textContaining('本地配置'), findsOneWidget);
      expect(find.textContaining('已断开'), findsOneWidget);
      expect(find.textContaining('当前使用本地连接配置'), findsOneWidget);

      final disconnectButton = tester.widget<FilledButton>(
        find.byKey(const ValueKey('settings-account-disconnect-button')),
      );
      expect(disconnectButton.onPressed, isNull);
    });
  });
}

Widget _buildTestApp({required Widget child}) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: Material(
      child: Center(
        child: SizedBox(width: 1100, child: SurfaceCard(child: child)),
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
