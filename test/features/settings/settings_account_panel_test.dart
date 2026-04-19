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
            bridgeUrlController: controllers.bridgeUrl,
            bridgeTokenController: controllers.bridgeToken,
            onSaveAccountProfile: ({required bool isManualBridge}) async {},
            onLogin: () async {
              loginCount += 1;
            },
            onVerifyMfa: () async {},
            onCancelMfa: () async {},
            onSync: () async {},
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
        find.byKey(const ValueKey('settings-account-logout-button')),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const ValueKey('settings-account-login-button')),
      );
      await tester.pump();

      expect(loginCount, 1);
    });

    testWidgets('shows account sync status, resync, and exit in signed-in mode', (
      tester,
    ) async {
      final controllers = _TestControllers();
      addTearDown(controllers.dispose);

      var syncCount = 0;
      var logoutCount = 0;

      final settings = SettingsSnapshot.defaults().copyWith(
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
            bridgeUrlController: controllers.bridgeUrl,
            bridgeTokenController: controllers.bridgeToken,
            onSaveAccountProfile: ({required bool isManualBridge}) async {},
            onLogin: () async {},
            onVerifyMfa: () async {},
            onCancelMfa: () async {},
            onSync: () async {
              syncCount += 1;
            },
            onLogout: () async {
              logoutCount += 1;
            },
          ),
        ),
      );

      expect(find.text('账号登录与同步'), findsOneWidget);
      expect(find.text('账号同步'), findsOneWidget);
      expect(find.textContaining('账号同步状态'), findsOneWidget);
      expect(find.byKey(const ValueKey('settings-account-sync-button')), findsOneWidget);
      expect(find.byKey(const ValueKey('settings-account-manual-reset-button')), findsNothing);
      expect(
        find.byKey(const ValueKey('settings-account-logout-button')),
        findsOneWidget,
      );

      expect(find.byKey(const ValueKey('settings-account-summary-service-url')), findsNothing);
      expect(find.byKey(const ValueKey('settings-account-summary-account-identifier')), findsNothing);
      expect(find.byKey(const ValueKey('settings-account-summary-remote-summary')), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey('settings-account-sync-button')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('settings-account-logout-button')),
      );
      await tester.pump();

      expect(syncCount, 1);
      expect(logoutCount, 1);
    });

    testWidgets('keeps details collapsed by default and expands diagnostics', (
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
            bridgeUrlController: controllers.bridgeUrl,
            bridgeTokenController: controllers.bridgeToken,
            onSaveAccountProfile: ({required bool isManualBridge}) async {},
            onLogin: () async {},
            onVerifyMfa: () async {},
            onCancelMfa: () async {},
            onSync: () async {},
            onLogout: () async {},
          ),
        ),
      );

      expect(find.byKey(const ValueKey('settings-account-summary-service-url')), findsNothing);
      expect(find.byKey(const ValueKey('settings-account-summary-account-identifier')), findsNothing);
      expect(
        find.byKey(const ValueKey('settings-account-summary-expansion')),
        findsOneWidget,
      );

      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('settings-account-summary-service-url')), findsOneWidget);
      expect(find.byKey(const ValueKey('settings-account-summary-account-identifier')), findsOneWidget);
      expect(find.byKey(const ValueKey('settings-account-summary-remote-summary')), findsOneWidget);
      expect(find.byKey(const ValueKey('settings-account-summary-last-sync')), findsOneWidget);
      expect(find.byKey(const ValueKey('settings-account-summary-mfa-status')), findsOneWidget);
      expect(find.byKey(const ValueKey('settings-account-summary-sync-scope')), findsOneWidget);
      expect(find.byKey(const ValueKey('settings-account-summary-token-configured')), findsOneWidget);
    });

    testWidgets('shows manual bridge save status and reset action when not account sync', (
      tester,
    ) async {
      final controllers = _TestControllers();
      addTearDown(controllers.dispose);

      var saveCount = 0;
      var logoutCount = 0;

      await tester.pumpWidget(
        _buildTestApp(
          child: SettingsAccountPanel(
            settings: SettingsSnapshot.defaults().copyWith(
              acpBridgeServerModeConfig: AcpBridgeServerModeConfig.defaults().copyWith(
                selfHosted: AcpBridgeServerModeConfig.defaults().selfHosted.copyWith(
                  serverUrl: 'https://xworkmate-bridge.svc.plus',
                  passwordRef: 'bridge-token-ref',
                ),
              ),
            ),
            accountSession: const AccountSessionSummary(
              userId: 'u-1',
              email: 'review@svc.plus',
              name: 'Review User',
              role: 'operator',
              mfaEnabled: false,
            ),
            accountState: null,
            accountBusy: false,
            accountSignedIn: true,
            accountMfaRequired: false,
            accountBaseUrlController: controllers.baseUrl,
            accountIdentifierController: controllers.identifier,
            accountPasswordController: controllers.password,
            accountMfaCodeController: controllers.mfaCode,
            bridgeUrlController: controllers.bridgeUrl,
            bridgeTokenController: controllers.bridgeToken,
            onSaveAccountProfile: ({required bool isManualBridge}) async {
              saveCount += 1;
            },
            onLogin: () async {},
            onVerifyMfa: () async {},
            onCancelMfa: () async {},
            onSync: () async {},
            onLogout: () async {
              logoutCount += 1;
            },
          ),
        ),
      );

      expect(find.text('手动 Bridge'), findsOneWidget);
      expect(find.textContaining('保存状态'), findsOneWidget);
      expect(find.byKey(const ValueKey('settings-account-manual-reset-button')), findsOneWidget);
      expect(find.byKey(const ValueKey('settings-account-sync-button')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('settings-account-manual-reset-button')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('settings-account-logout-button')));
      await tester.pump();

      expect(saveCount, 1);
      expect(logoutCount, 1);
    });

    testWidgets('shows live syncing feedback while resync is running', (
      tester,
    ) async {
      final controllers = _TestControllers();
      addTearDown(controllers.dispose);

      await tester.pumpWidget(
        _buildTestApp(
          child: SettingsAccountPanel(
            settings: SettingsSnapshot.defaults().copyWith(
              accountBaseUrl: 'https://accounts.svc.plus',
              accountUsername: 'review@svc.plus',
            ),
            accountSession: const AccountSessionSummary(
              userId: 'u-1',
              email: 'review@svc.plus',
              name: 'Review User',
              role: 'operator',
              mfaEnabled: true,
            ),
            accountState: AccountSyncState.defaults().copyWith(
              syncState: 'ready',
              syncMessage: 'Bridge access synced',
              profileScope: 'bridge',
            ),
            accountBusy: true,
            accountStatus: 'Syncing bridge access...',
            accountSignedIn: true,
            accountMfaRequired: false,
            accountBaseUrlController: controllers.baseUrl,
            accountIdentifierController: controllers.identifier,
            accountPasswordController: controllers.password,
            accountMfaCodeController: controllers.mfaCode,
            bridgeUrlController: controllers.bridgeUrl,
            bridgeTokenController: controllers.bridgeToken,
            onSaveAccountProfile: ({required bool isManualBridge}) async {},
            onLogin: () async {},
            onVerifyMfa: () async {},
            onCancelMfa: () async {},
            onSync: () async {},
            onLogout: () async {},
          ),
        ),
      );

      expect(find.textContaining('Syncing bridge access...'), findsOneWidget);
      final syncButton = tester.widget<FilledButton>(
        find.byKey(const ValueKey('settings-account-sync-button')),
      );
      expect(syncButton.onPressed, isNull);
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
  final TextEditingController bridgeUrl = TextEditingController(
    text: 'https://xworkmate-bridge.svc.plus',
  );
  final TextEditingController bridgeToken = TextEditingController(
    text: 'bridge-token',
  );

  void dispose() {
    baseUrl.dispose();
    identifier.dispose();
    password.dispose();
    mfaCode.dispose();
    bridgeUrl.dispose();
    bridgeToken.dispose();
  }
}
