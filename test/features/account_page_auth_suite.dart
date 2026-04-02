@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/features/account/account_page.dart';
import 'package:xworkmate/runtime/account_runtime_client.dart';
import 'package:xworkmate/runtime/runtime_controllers.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

import '../test_support.dart';

void main() {
  testWidgets('AccountPage shows centered login card while signed out', (
    WidgetTester tester,
  ) async {
    final controller = await createTestController(
      tester,
      accountClientFactory: (_) => _FakeAccountRuntimeClient(requireMfa: false),
    );

    await pumpPage(tester, child: AccountPage(controller: controller));

    expect(find.text('账号登录'), findsOneWidget);
    expect(find.text('请先登录'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_outlined), findsOneWidget);
    expect(find.byKey(const ValueKey('account-password-field')), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '登录'), findsOneWidget);
    expect(find.byKey(const ValueKey('account-save-local-button')), findsOneWidget);
  });

  testWidgets('AccountPage logs in and shows remote sync status inline', (
    WidgetTester tester,
  ) async {
    final controller = await createTestController(
      tester,
      accountClientFactory: (_) => _FakeAccountRuntimeClient(requireMfa: false),
    );

    await pumpPage(tester, child: AccountPage(controller: controller));

    await tester.enterText(
      find.byKey(const ValueKey('account-base-url-field')),
      _FakeAccountRuntimeClient.accountBaseUrl,
    );
    await tester.enterText(
      find.byKey(const ValueKey('account-username-field')),
      _FakeAccountRuntimeClient.loginEmail,
    );
    await tester.enterText(
      find.byKey(const ValueKey('account-password-field')),
      _FakeAccountRuntimeClient.loginPassword,
    );

    expect(find.byKey(const ValueKey('account-login-button')), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '登录'), findsOneWidget);

    await tester.runAsync(() async {
      await controller.settingsController.loginAccount(
        baseUrl: _FakeAccountRuntimeClient.accountBaseUrl,
        identifier: _FakeAccountRuntimeClient.loginEmail,
        password: _FakeAccountRuntimeClient.loginPassword,
      );
    });
    await tester.pump();

    final sessionStatus = tester.widget<Text>(
      find.byKey(const ValueKey('account-session-status')),
    );
    final syncStatus = tester.widget<Text>(
      find.byKey(const ValueKey('account-sync-status')),
    );

    expect(sessionStatus.data, contains(_FakeAccountRuntimeClient.loginEmail));
    expect(syncStatus.data, contains('ready'));
    expect(find.byKey(const ValueKey('account-login-button')), findsNothing);
    expect(find.byKey(const ValueKey('account-sync-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('account-logout-button')), findsOneWidget);
  });

  testWidgets('AccountPage completes MFA verification and can log out', (
    WidgetTester tester,
  ) async {
    final controller = await createTestController(
      tester,
      accountClientFactory: (_) => _FakeAccountRuntimeClient(requireMfa: true),
    );

    await pumpPage(tester, child: AccountPage(controller: controller));

    await tester.enterText(
      find.byKey(const ValueKey('account-base-url-field')),
      _FakeAccountRuntimeClient.accountBaseUrl,
    );
    await tester.enterText(
      find.byKey(const ValueKey('account-username-field')),
      _FakeAccountRuntimeClient.loginEmail,
    );
    await tester.enterText(
      find.byKey(const ValueKey('account-password-field')),
      _FakeAccountRuntimeClient.loginPassword,
    );

    await tester.runAsync(() async {
      await controller.settingsController.loginAccount(
        baseUrl: _FakeAccountRuntimeClient.accountBaseUrl,
        identifier: _FakeAccountRuntimeClient.loginEmail,
        password: _FakeAccountRuntimeClient.loginPassword,
      );
    });
    await tester.pump();

    expect(
      find.byKey(const ValueKey('account-verify-mfa-button')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('account-password-field')), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('account-mfa-code-field')),
      _FakeAccountRuntimeClient.loginCode,
    );
    await tester.runAsync(() async {
      await controller.settingsController.verifyAccountMfa(
        baseUrl: _FakeAccountRuntimeClient.accountBaseUrl,
        code: _FakeAccountRuntimeClient.loginCode,
      );
    });
    await tester.pump();

    expect(find.byKey(const ValueKey('account-sync-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('account-logout-button')), findsOneWidget);

    await tester.runAsync(() async {
      await controller.settingsController.logoutAccount();
    });
    await tester.pump();

    expect(find.text('账号登录'), findsOneWidget);
    expect(find.byKey(const ValueKey('account-login-button')), findsOneWidget);
  });
}

class _FakeAccountRuntimeClient extends AccountRuntimeClient {
  _FakeAccountRuntimeClient({required this.requireMfa})
    : super(baseUrl: accountBaseUrl);

  static const String accountBaseUrl = 'https://accounts.widget.test';
  static const String loginEmail = 'user@example.com';
  static const String loginPassword = 'correct-password';
  static const String loginCode = '123456';
  static const String sessionToken = 'account-session-token';
  static const String mfaTicket = 'account-mfa-ticket';

  final bool requireMfa;

  @override
  Future<Map<String, dynamic>> login({
    required String identifier,
    required String password,
  }) async {
    if (identifier != loginEmail || password != loginPassword) {
      throw const AccountRuntimeException(
        statusCode: 401,
        errorCode: 'invalid_credentials',
        message: 'invalid credentials',
      );
    }
    if (requireMfa) {
      return <String, dynamic>{
        'message': 'mfa required',
        'mfaRequired': true,
        'mfa_required': true,
        'mfaToken': mfaTicket,
        'mfaTicket': mfaTicket,
      };
    }
    return <String, dynamic>{
      'message': 'login successful',
      'token': sessionToken,
      'access_token': sessionToken,
      'expiresAt': DateTime.utc(2030, 1, 1).toIso8601String(),
      'mfaRequired': false,
      'mfa_required': false,
      'user': _userPayload(mfaEnabled: false),
    };
  }

  @override
  Future<Map<String, dynamic>> verifyMfa({
    required String mfaToken,
    required String code,
  }) async {
    if (mfaToken != mfaTicket || code != loginCode) {
      throw const AccountRuntimeException(
        statusCode: 401,
        errorCode: 'invalid_mfa_code',
        message: 'invalid totp code',
      );
    }
    return <String, dynamic>{
      'message': 'login successful',
      'token': sessionToken,
      'access_token': sessionToken,
      'expiresAt': DateTime.utc(2030, 1, 1).toIso8601String(),
      'mfaRequired': false,
      'mfa_required': false,
      'user': _userPayload(mfaEnabled: true),
    };
  }

  @override
  Future<AccountSessionSummary> loadSession({required String token}) async {
    if (token != sessionToken) {
      throw const AccountRuntimeException(
        statusCode: 401,
        errorCode: 'session_not_found',
        message: 'session not found',
      );
    }
    return AccountSessionSummary(
      userId: 'user-1',
      email: loginEmail,
      name: 'Account User',
      role: 'operator',
      mfaEnabled: requireMfa,
    );
  }

  @override
  Future<AccountProfileResponse> loadProfile({required String token}) async {
    if (token != sessionToken) {
      throw const AccountRuntimeException(
        statusCode: 401,
        errorCode: 'session_not_found',
        message: 'session not found',
      );
    }
    return AccountProfileResponse(
      profile: AccountRemoteProfile.defaults().copyWith(
        openclawUrl: 'https://openclaw.account.example',
        openclawOrigin: 'https://openclaw.account.example',
        vaultUrl: accountBaseUrl,
        vaultNamespace: 'team-a',
        apisixUrl: '$accountBaseUrl/v1',
        secretLocators: const <AccountSecretLocator>[
          AccountSecretLocator(
            id: 'locator-openclaw',
            provider: 'vault',
            secretPath: 'kv/openclaw',
            secretKey: 'OPENCLAW_GATEWAY_TOKEN',
            target: kAccountManagedSecretTargetOpenclawGatewayToken,
            required: true,
          ),
          AccountSecretLocator(
            id: 'locator-ai-gateway',
            provider: 'vault',
            secretPath: 'kv/apisix',
            secretKey: 'AI_GATEWAY_ACCESS_TOKEN',
            target: kAccountManagedSecretTargetAIGatewayAccessToken,
            required: true,
          ),
          AccountSecretLocator(
            id: 'locator-ollama',
            provider: 'vault',
            secretPath: 'kv/ollama',
            secretKey: 'OLLAMA_API_KEY',
            target: kAccountManagedSecretTargetOllamaCloudApiKey,
            required: false,
          ),
        ],
      ),
      profileScope: 'user',
      tokenConfigured: const AccountTokenConfigured(
        openclaw: true,
        vault: false,
        apisix: true,
      ),
    );
  }

  Map<String, dynamic> _userPayload({required bool mfaEnabled}) {
    return <String, dynamic>{
      'id': 'user-1',
      'email': loginEmail,
      'name': 'Account User',
      'role': 'operator',
      'mfaEnabled': mfaEnabled,
    };
  }
}
