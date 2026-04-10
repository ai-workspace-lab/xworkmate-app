import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/helpers/test_keys.dart';
import 'test_support.dart';

class _RealEnvConfig {
  const _RealEnvConfig({
    required this.accountBaseUrl,
    required this.accountIdentifier,
    required this.accountPassword,
    required this.expectedRemoteHost,
    required this.enableGatewayConnectionCheck,
  });

  final String accountBaseUrl;
  final String accountIdentifier;
  final String accountPassword;
  final String expectedRemoteHost;
  final bool enableGatewayConnectionCheck;

  static _RealEnvConfig? load() {
    final env = _loadMergedEnv();
    final accountBaseUrl = _readEnv(env, <String>[
      'XWORKMATE_TEST_ACCOUNT_BASE_URL',
      'ACCOUNTS_SVC_PLUS_URL',
      'XWORKMATE_ACCOUNT_BASE_URL',
    ], fallback: 'https://accounts.svc.plus');
    final accountIdentifier = _readEnv(env, <String>[
      'XWORKMATE_TEST_ACCOUNT_IDENTIFIER',
      'XWORKMATE_TEST_LOGIN_NAME',
      'XWORKMATE_LOGIN_NAME',
      'LOGIN_NAME',
    ]);
    final accountPassword = _readEnv(env, <String>[
      'XWORKMATE_TEST_ACCOUNT_PASSWORD',
      'XWORKMATE_TEST_LOGIN_PASSWORD',
      'XWORKMATE_LOGIN_PASSWORD',
      'LOGIN_PASSWORD',
    ]);
    if (accountIdentifier.isEmpty || accountPassword.isEmpty) {
      return null;
    }

    final expectedRemoteHost = _readEnv(env, <String>[
      'XWORKMATE_TEST_EXPECT_REMOTE_HOST',
      'XWORKMATE_TEST_GATEWAY_REMOTE_HOST',
      'OPENCLAW_REMOTE_HOST',
    ], fallback: 'openclaw.svc.plus');
    return _RealEnvConfig(
      accountBaseUrl: accountBaseUrl,
      accountIdentifier: accountIdentifier,
      accountPassword: accountPassword,
      expectedRemoteHost: expectedRemoteHost,
      enableGatewayConnectionCheck: _readBoolEnv(env, <String>[
        'XWORKMATE_TEST_ENABLE_GATEWAY_CONNECTION_CHECK',
        'XWORKMATE_TEST_GATEWAY_CONNECT',
      ]),
    );
  }
}

Map<String, String> _loadMergedEnv() {
  final fileValues = _loadDotEnvValues();
  return <String, String>{...fileValues, ...Platform.environment};
}

Map<String, String> _loadDotEnvValues() {
  final file = File('.env');
  if (!file.existsSync()) {
    return const <String, String>{};
  }
  final values = <String, String>{};
  for (final rawLine in file.readAsLinesSync()) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#') || !line.contains('=')) {
      continue;
    }
    final index = line.indexOf('=');
    final key = line.substring(0, index).trim();
    var value = line.substring(index + 1).trim();
    if ((value.startsWith("'") && value.endsWith("'")) ||
        (value.startsWith('"') && value.endsWith('"'))) {
      value = value.substring(1, value.length - 1);
    }
    if (key.isNotEmpty) {
      values[key] = value;
    }
  }
  return values;
}

String _readEnv(
  Map<String, String> env,
  List<String> keys, {
  String fallback = '',
}) {
  for (final key in keys) {
    final value = env[key]?.trim() ?? '';
    if (value.isNotEmpty) {
      return value;
    }
  }
  return fallback;
}

bool _readBoolEnv(Map<String, String> env, List<String> keys) {
  final value = _readEnv(env, keys).toLowerCase();
  return value == '1' || value == 'true' || value == 'yes' || value == 'on';
}

Future<void> _waitForCondition(
  WidgetTester tester,
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 20),
  Duration step = const Duration(milliseconds: 250),
  String label = 'condition',
}) async {
  final maxIterations = timeout.inMilliseconds ~/ step.inMilliseconds;
  for (var i = 0; i < maxIterations; i += 1) {
    await tester.pump(step);
    if (predicate()) {
      return;
    }
  }
  throw TestFailure('Timed out waiting for $label');
}

Future<void> _openIntegrationsSettings(WidgetTester tester) async {
  await tester.tap(find.byKey(TestKeys.sidebarFooterSettings));
  await settleIntegrationUi(tester);
  await tester.tap(find.byKey(TestKeys.settingsIntegrationsTab));
  await settleIntegrationUi(tester);
}

Future<void> _openGatewaySettings(WidgetTester tester) async {
  await tester.tap(find.byKey(TestKeys.settingsGatewayTab));
  await settleIntegrationUi(tester);
}

void main() {
  initializeIntegrationHarness();

  setUp(() async {
    await resetIntegrationPreferences();
  });

  testWidgets(
    'real env login chain signs in, syncs remote defaults, and exposes remote gateway profile',
    (WidgetTester tester) async {
      final config = _RealEnvConfig.load();
      if (config == null) {
        print(
          'Skipping real env login chain test: set '
          'XWORKMATE_TEST_ACCOUNT_IDENTIFIER/XWORKMATE_TEST_ACCOUNT_PASSWORD '
          'or LOGIN_NAME/LOGIN_PASSWORD in the environment or .env.',
        );
        return;
      }

      await pumpDesktopApp(tester);
      await waitForIntegrationFinder(
        tester,
        find.byKey(TestKeys.assistantConversationShell),
      );
      await _openIntegrationsSettings(tester);

      await tester.enterText(
        find.byKey(const ValueKey('account-base-url-field')),
        config.accountBaseUrl,
      );
      await tester.enterText(
        find.byKey(const ValueKey('account-username-field')),
        config.accountIdentifier,
      );
      await tester.enterText(
        find.byKey(const ValueKey('account-password-field')),
        config.accountPassword,
      );
      await settleIntegrationUi(tester);

      await tester.tap(find.byKey(const ValueKey('account-login-button')));
      await settleIntegrationUi(tester);

      await _waitForCondition(
        tester,
        () =>
            find
                .byKey(const ValueKey('account-sync-button'))
                .evaluate()
                .isNotEmpty ||
            find
                .byKey(const ValueKey('account-verify-mfa-button'))
                .evaluate()
                .isNotEmpty,
        label: 'account sign-in state',
      );

      expect(
        find.byKey(const ValueKey('account-verify-mfa-button')),
        findsNothing,
        reason: 'This real-env chain currently expects a non-MFA test account.',
      );
      expect(find.byKey(const ValueKey('account-sync-button')), findsOneWidget);

      final sessionStatus = tester.widget<Text>(
        find.byKey(const ValueKey('account-session-status')),
      );
      final syncStatus = tester.widget<Text>(
        find.byKey(const ValueKey('account-sync-status')),
      );
      expect(sessionStatus.data ?? '', contains('Signed in'));
      expect(syncStatus.data ?? '', contains('ready'));

      final lastSyncFinder = find.byKey(
        const ValueKey('acp-bridge-cloud-last-sync'),
      );
      if (lastSyncFinder.evaluate().isNotEmpty) {
        final lastSync = tester.widget<Text>(lastSyncFinder);
        expect(lastSync.data ?? '', isNot(contains('Not synced yet')));
      }

      await _openGatewaySettings(tester);
      await tester.tap(find.byKey(const ValueKey('gateway-profile-chip-1')));
      await settleIntegrationUi(tester);

      final gatewayHostField = tester.widget<TextField>(
        find.byKey(const ValueKey('gateway-host-field')),
      );
      final resolvedGatewayHost =
          gatewayHostField.controller?.text.trim() ?? '';
      expect(resolvedGatewayHost, isNotEmpty);
      expect(resolvedGatewayHost, contains(config.expectedRemoteHost));

      if (config.enableGatewayConnectionCheck) {
        await tester.tap(find.byKey(const ValueKey('gateway-test-button')));
        await settleIntegrationUi(tester);
        await _waitForCondition(
          tester,
          () =>
              find
                  .textContaining('Connection succeeded')
                  .evaluate()
                  .isNotEmpty ||
              find.textContaining('连接成功').evaluate().isNotEmpty ||
              find.textContaining('pairing required').evaluate().isNotEmpty ||
              find.textContaining('PAIRING_REQUIRED').evaluate().isNotEmpty,
          timeout: const Duration(seconds: 30),
          label: 'gateway test result',
        );
      }

      await tester.tap(
        find.byKey(const ValueKey<String>('workspace-breadcrumb-0')),
      );
      await settleIntegrationUi(tester);
      await waitForIntegrationFinder(
        tester,
        find.byKey(TestKeys.assistantConversationShell),
      );

      await switchNewConversationExecutionTargetForIntegration(
        tester,
        find.byKey(TestKeys.assistantExecutionTargetMenuItemRemote),
      );

      expect(find.textContaining(config.expectedRemoteHost), findsWidgets);
    },
  );
}
