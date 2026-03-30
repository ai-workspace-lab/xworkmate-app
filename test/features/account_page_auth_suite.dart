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
  testWidgets('AccountPage logs in and shows remote sync status inline', (
    WidgetTester tester,
  ) async {
    final controller = await createTestController(
      tester,
      accountClientFactory: (_) => _FakeAccountRuntimeClient(requireMfa: false),
    );
    await tester.runAsync(() async {
      await controller.settingsController.saveVaultToken(
        _FakeAccountRuntimeClient.expectedVaultToken,
      );
    });

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
    expect(find.byKey(const ValueKey('account-logout-button')), findsOneWidget);
  });

  testWidgets('AccountPage completes MFA verification and can log out', (
    WidgetTester tester,
  ) async {
    final controller = await createTestController(
      tester,
      accountClientFactory: (_) => _FakeAccountRuntimeClient(requireMfa: true),
    );
    await tester.runAsync(() async {
      await controller.settingsController.saveVaultToken(
        _FakeAccountRuntimeClient.expectedVaultToken,
      );
    });

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

    expect(find.byKey(const ValueKey('account-logout-button')), findsOneWidget);

    await tester.runAsync(() async {
      await controller.settingsController.logoutAccount();
    });
    await tester.pump();

    final sessionStatus = tester.widget<Text>(
      find.byKey(const ValueKey('account-session-status')),
    );
    expect(sessionStatus.data, contains('未登录'));
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
  static const String expectedVaultToken = 'vault-root-token';
  static const String openclawGatewayToken = 'remote-openclaw-token';
  static const String aiGatewayAccessToken = 'remote-ai-gateway-token';
  static const String ollamaCloudApiKey = 'remote-ollama-api-key';

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
  Future<AccountRemoteProfile> loadProfile({required String token}) async {
    if (token != sessionToken) {
      throw const AccountRuntimeException(
        statusCode: 401,
        errorCode: 'session_not_found',
        message: 'session not found',
      );
    }
    return AccountRemoteProfile.defaults().copyWith(
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
    );
  }

  @override
  Future<String> readVaultSecretValue({
    required String vaultUrl,
    required String namespace,
    required String vaultToken,
    required String secretPath,
    required String secretKey,
  }) async {
    if (vaultToken != expectedVaultToken) {
      throw const AccountRuntimeException(
        statusCode: 403,
        errorCode: 'invalid_vault_token',
        message: 'invalid vault token',
      );
    }
    return switch ('$secretPath::$secretKey') {
      'kv/openclaw::OPENCLAW_GATEWAY_TOKEN' => openclawGatewayToken,
      'kv/apisix::AI_GATEWAY_ACCESS_TOKEN' => aiGatewayAccessToken,
      'kv/ollama::OLLAMA_API_KEY' => ollamaCloudApiKey,
      _ => throw const AccountRuntimeException(
        statusCode: 404,
        errorCode: 'secret_not_found',
        message: 'secret not found',
      ),
    };
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
