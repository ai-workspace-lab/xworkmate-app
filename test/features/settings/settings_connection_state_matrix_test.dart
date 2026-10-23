import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/features/settings/settings_account_panel.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/theme/app_theme.dart';

// Synthetic UI fixtures only: no connection or health probe is performed.
void main() {
  for (final signedIn in [false, true]) {
    for (final busy in [false, true]) {
      testWidgets(
        'manual source isolates cloud state signedIn=$signedIn busy=$busy',
        (tester) async {
          tester.view.physicalSize = const Size(1400, 1200);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final controllers = List.generate(6, (_) => TextEditingController());
          addTearDown(() {
            for (final controller in controllers) {
              controller.dispose();
            }
          });
          var resets = 0;
          var logouts = 0;
          var syncs = 0;
          final defaults = AcpBridgeServerModeConfig.defaults();
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light(),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: SettingsAccountPanel(
                    settings: SettingsSnapshot.defaults().copyWith(
                      acpBridgeServerModeConfig: defaults.copyWith(
                        effective: const AcpBridgeServerEffectiveConfig(
                          endpoint: 'http://127.0.0.1:8787',
                          tokenRef: 'fixture-ref',
                          source: 'bridge',
                          reason: 'Synthetic saved configuration',
                        ),
                        selfHosted: defaults.selfHosted.copyWith(
                          serverUrl: 'http://127.0.0.1:8787',
                          username: 'local-fixture',
                        ),
                        cloudSynced: defaults.cloudSynced.copyWith(
                          accountBaseUrl: 'https://stale.example.invalid',
                          accountIdentifier: 'stale@example.invalid',
                          lastSyncAt: 1700000000000,
                        ),
                      ),
                    ),
                    accountSession: signedIn
                        ? const AccountSessionSummary(
                            userId: 'fixture',
                            email: 'stale@example.invalid',
                            name: 'Fixture',
                            role: 'operator',
                            mfaEnabled: true,
                          )
                        : null,
                    accountState: AccountSyncState.defaults().copyWith(
                      syncState: 'ready',
                      syncMessage: 'STALE_CLOUD_READY',
                      profileScope: 'STALE_SCOPE',
                    ),
                    accountBusy: busy,
                    accountSignedIn: signedIn,
                    accountMfaRequired: false,
                    accountBaseUrlController: controllers[0],
                    accountIdentifierController: controllers[1],
                    accountPasswordController: controllers[2],
                    accountMfaCodeController: controllers[3],
                    bridgeUrlController: controllers[4],
                    bridgeTokenController: controllers[5],
                    onSaveAccountProfile:
                        ({required bool isManualBridge}) async {},
                    onLogin: () async {},
                    onVerifyMfa: () async {},
                    onCancelMfa: () async {},
                    onSync: () async {
                      syncs++;
                    },
                    onResetManualBridge: () async {
                      resets++;
                    },
                    onLogout: () async {
                      logouts++;
                    },
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          final reset = find.byKey(
            const ValueKey('settings-account-manual-reset-button'),
          );
          expect(reset, findsOneWidget);
          expect(
            find.byKey(const ValueKey('settings-account-logout-button')),
            findsNothing,
          );
          expect(
            find.byKey(const ValueKey('settings-account-sync-button')),
            findsNothing,
          );
          expect(tester.widget<FilledButton>(reset).onPressed == null, busy);
          if (!busy) {
            expect(find.textContaining('连接状态未验证'), findsOneWidget);
            expect(find.text('断开连接'), findsOneWidget);
            await tester.tap(reset);
            await tester.pump();
          }
          await tester.tap(
            find.byKey(const ValueKey('settings-account-summary-expansion')),
          );
          // A busy spinner never settles; advance only the expansion animation.
          await tester.pump(const Duration(milliseconds: 400));
          expect(
            tester
                .widget<Text>(
                  find.byKey(
                    const ValueKey('settings-account-summary-service-url'),
                  ),
                )
                .data,
            '服务地址: http://127.0.0.1:8787',
          );
          expect(
            tester
                .widget<Text>(
                  find.byKey(
                    const ValueKey(
                      'settings-account-summary-account-identifier',
                    ),
                  ),
                )
                .data,
            '连接身份: local-fixture',
          );
          expect(find.textContaining('stale.example.invalid'), findsNothing);
          expect(find.textContaining('stale@example.invalid'), findsNothing);
          expect(find.textContaining('STALE_CLOUD_READY'), findsNothing);
          for (final field in [
            'remote-summary',
            'last-sync',
            'mfa-status',
            'sync-scope',
            'token-configured',
          ]) {
            expect(
              find.byKey(ValueKey('settings-account-summary-$field')),
              findsNothing,
            );
          }
          expect(resets, busy ? 0 : 1);
          expect(logouts, 0);
          expect(syncs, 0);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
