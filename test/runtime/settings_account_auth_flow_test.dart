import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/account_runtime_client.dart';
import 'package:xworkmate/runtime/runtime_controllers.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsController account auth flow', () {
    test('login persists session summary and bridge sync metadata', () async {
      final root = await Directory.systemTemp.createTemp(
        'xworkmate-account-auth-login-',
      );
      final store = SecureConfigStore(
        enableSecureStorage: false,
        appDataRootPathResolver: () async => root.path,
        secretRootPathResolver: () async => root.path,
        supportRootPathResolver: () async => root.path,
      );
      final client = _SuccessfulAccountRuntimeClient();
      final controller = SettingsController(
        store,
        accountClientFactory: (_) => client,
      );
      addTearDown(() async {
        controller.dispose();
        store.dispose();
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });

      await store.initialize();
      await controller.initialize();
      await controller.saveSnapshot(
        controller.snapshot.copyWith(
          accountBaseUrl: 'https://accounts.svc.plus',
          accountUsername: 'review@svc.plus',
        ),
      );

      await controller.loginAccount(
        baseUrl: 'https://accounts.svc.plus',
        identifier: 'review@svc.plus',
        password: '***REMOVED-CREDENTIAL***',
      );

      expect(controller.accountSignedIn, isTrue);
      expect(controller.accountStatus, 'Signed in as review@svc.plus');
      expect(controller.accountSession?.email, 'review@svc.plus');
      expect(controller.accountSession?.totpEnabled, isTrue);
      expect(controller.accountSession?.totpPending, isFalse);
      expect(controller.accountSyncState?.syncState, 'ready');
      expect(controller.accountSyncState?.profileScope, 'bridge');
      expect(controller.accountSyncState?.tokenConfigured.bridge, isTrue);
      expect(controller.accountSyncState?.tokenConfigured.apisix, isFalse);
      expect(await store.loadAccountSessionToken(), 'session-token');
      expect(
        await store.loadAccountManagedSecret(
          target: kAccountManagedSecretTargetBridgeAuthToken,
        ),
        'bridge-token',
      );
      expect(client.loadSessionCalls, 0);
      expect(
        controller.accountSyncState?.syncedDefaults.bridgeServerUrl,
        'https://xworkmate-bridge.svc.plus',
      );
      expect(
        controller
            .snapshot
            .acpBridgeServerModeConfig
            .cloudSynced
            .remoteServerSummary
            .endpoint,
        'https://xworkmate-bridge.svc.plus',
      );
    });

    test('mfa challenge transitions to verified signed-in session', () async {
      final root = await Directory.systemTemp.createTemp(
        'xworkmate-account-auth-mfa-',
      );
      final store = SecureConfigStore(
        enableSecureStorage: false,
        appDataRootPathResolver: () async => root.path,
        secretRootPathResolver: () async => root.path,
        supportRootPathResolver: () async => root.path,
      );
      final client = _MfaAccountRuntimeClient();
      final controller = SettingsController(
        store,
        accountClientFactory: (_) => client,
      );
      addTearDown(() async {
        controller.dispose();
        store.dispose();
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });

      await store.initialize();
      await controller.initialize();
      await controller.saveSnapshot(
        controller.snapshot.copyWith(
          accountBaseUrl: 'https://accounts.svc.plus',
          accountUsername: 'review@svc.plus',
        ),
      );

      await controller.loginAccount(
        baseUrl: 'https://accounts.svc.plus',
        identifier: 'review@svc.plus',
        password: '***REMOVED-CREDENTIAL***',
      );

      expect(controller.accountSignedIn, isFalse);
      expect(controller.accountMfaRequired, isTrue);
      expect(controller.accountStatus, 'MFA required');

      await controller.verifyAccountMfa(
        baseUrl: 'https://accounts.svc.plus',
        code: '123456',
      );

      expect(client.lastVerifiedCode, '123456');
      expect(controller.accountSignedIn, isTrue);
      expect(controller.accountMfaRequired, isFalse);
      expect(controller.accountSession?.email, 'review@svc.plus');
      expect(controller.accountSyncState?.syncState, 'ready');
    });
  });
}

class _SuccessfulAccountRuntimeClient extends AccountRuntimeClient {
  _SuccessfulAccountRuntimeClient()
    : super(baseUrl: 'https://accounts.svc.plus');

  int loadSessionCalls = 0;

  @override
  Future<Map<String, dynamic>> login({
    required String identifier,
    required String password,
  }) async {
    expect(identifier, 'review@svc.plus');
    expect(password, '***REMOVED-CREDENTIAL***');
    return <String, dynamic>{
      'token': 'session-token',
      'BRIDGE_AUTH_TOKEN': 'bridge-token',
      'BRIDGE_SERVER_URL': 'https://xworkmate-bridge.svc.plus',
      'expiresAt': '2026-04-12T00:00:00Z',
      'user': <String, dynamic>{
        'id': 'u-1',
        'email': 'review@svc.plus',
        'name': 'Review',
        'role': 'readonly',
        'mfaEnabled': true,
        'mfa': <String, dynamic>{'totpEnabled': true, 'totpPending': false},
      },
    };
  }

  @override
  Future<AccountSessionSummary> loadSession({required String token}) async {
    loadSessionCalls += 1;
    expect(token, 'session-token');
    return const AccountSessionSummary(
      userId: 'u-1',
      email: 'review@svc.plus',
      name: 'Review',
      role: 'readonly',
      mfaEnabled: true,
      totpEnabled: true,
      totpPending: false,
    );
  }
}

class _MfaAccountRuntimeClient extends AccountRuntimeClient {
  _MfaAccountRuntimeClient() : super(baseUrl: 'https://accounts.svc.plus');

  String lastVerifiedCode = '';

  @override
  Future<Map<String, dynamic>> login({
    required String identifier,
    required String password,
  }) async {
    return <String, dynamic>{'mfaRequired': true, 'mfaTicket': 'ticket-123'};
  }

  @override
  Future<Map<String, dynamic>> verifyMfa({
    required String mfaToken,
    required String code,
  }) async {
    expect(mfaToken, 'ticket-123');
    lastVerifiedCode = code;
    return <String, dynamic>{
      'token': 'session-token',
      'BRIDGE_AUTH_TOKEN': 'bridge-token',
      'BRIDGE_SERVER_URL': 'https://xworkmate-bridge.svc.plus',
      'expiresAt': '2026-04-12T00:00:00Z',
      'user': <String, dynamic>{
        'id': 'u-1',
        'email': 'review@svc.plus',
        'name': 'Review',
        'role': 'readonly',
        'mfaEnabled': true,
        'mfa': <String, dynamic>{'totpEnabled': true, 'totpPending': false},
      },
    };
  }

  @override
  Future<AccountSessionSummary> loadSession({required String token}) async {
    return const AccountSessionSummary(
      userId: 'u-1',
      email: 'review@svc.plus',
      name: 'Review',
      role: 'readonly',
      mfaEnabled: true,
      totpEnabled: true,
      totpPending: false,
    );
  }
}
