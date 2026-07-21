import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/app/app_shell_desktop.dart';
import 'package:xworkmate/features/mobile/mobile_settings_page.dart';
import 'package:xworkmate/runtime/account_runtime_client.dart';
import 'package:xworkmate/runtime/runtime_controllers.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';
import 'package:xworkmate/theme/app_theme.dart';

import '../../mock_plugins.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Account sync persists through path_provider/package_info; without these
  // mocks the sync future never completes under the test binding.
  mockPlugins();
  group('MobileSettingsPage', () {
    testWidgets(
      'mobile shell renders mobile settings instead of desktop page',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(430, 932);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final controller = AppController(
          environmentOverride: const <String, String>{},
        );
        addTearDown(controller.dispose);
        controller.openSettings();

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light().copyWith(platform: TargetPlatform.iOS),
            home: AppShell(controller: controller),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('mobile-settings-page')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('settings-account-panel-card')),
          findsNothing,
        );
        expect(find.text('搜索设置'), findsNothing);
        expect(
          find.byKey(const Key('mobile-settings-account-login-card')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('mobile-settings-manual-bridge-card')),
          findsOneWidget,
        );
      },
    );

    testWidgets('login form uses mobile-friendly input hints and controls', (
      tester,
    ) async {
      final controller = AppController(
        environmentOverride: const <String, String>{},
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light().copyWith(platform: TargetPlatform.iOS),
          home: MediaQuery(
            data: const MediaQueryData(size: Size(390, 844)),
            child: Scaffold(body: MobileSettingsPage(controller: controller)),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));

      final emailField = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('mobile-settings-account-identifier-field')),
          matching: find.byType(TextField),
        ),
      );
      final passwordField = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('mobile-settings-account-password-field')),
          matching: find.byType(TextField),
        ),
      );

      expect(emailField.keyboardType, TextInputType.emailAddress);
      expect(emailField.textInputAction, TextInputAction.next);
      expect(passwordField.keyboardType, TextInputType.visiblePassword);
      expect(passwordField.textInputAction, TextInputAction.done);
      expect(passwordField.obscureText, isTrue);
      expect(
        find.byKey(const Key('mobile-settings-account-login-button')),
        findsOneWidget,
      );
    });

    testWidgets('login failure is visible on the mobile sign-in card', (
      tester,
    ) async {
      final client = _MobileFakeAccountRuntimeClient(
        loginError: const AccountRuntimeException(
          statusCode: 401,
          errorCode: 'INVALID_CREDENTIALS',
          message: 'Invalid credentials',
        ),
      );
      final controller = AppController(
        accountClientFactory: (_) => client,
        environmentOverride: const <String, String>{},
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light().copyWith(platform: TargetPlatform.iOS),
          home: MediaQuery(
            data: const MediaQueryData(size: Size(390, 844)),
            child: Scaffold(body: MobileSettingsPage(controller: controller)),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));

      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('mobile-settings-account-identifier-field')),
          matching: find.byType(TextFormField),
        ),
        'mobile@svc.plus',
      );
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('mobile-settings-account-password-field')),
          matching: find.byType(TextFormField),
        ),
        'wrong-password',
      );
      final loginButton = find.byKey(
        const Key('mobile-settings-account-login-button'),
      );
      await tester.ensureVisible(loginButton);
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(loginButton).onPressed, isNotNull);
      tester.widget<FilledButton>(loginButton).onPressed!();
      for (
        var attempt = 0;
        attempt < 50 && find.text('Invalid credentials').evaluate().isEmpty;
        attempt += 1
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Invalid credentials'), findsOneWidget);
      expect(client.loginCallCount, 1);
    });

    testWidgets('login button submits current mobile field values', (
      tester,
    ) async {
      final client = _MobileFakeAccountRuntimeClient(
        loginPayload: const <String, dynamic>{
          'token': 'session-token',
          'user': <String, dynamic>{'id': 'user-1', 'email': 'mobile@svc.plus'},
        },
        syncPayload: const <String, dynamic>{
          'BRIDGE_AUTH_TOKEN': 'bridge-token',
          'BRIDGE_SERVER_URL': 'https://xworkmate-bridge.svc.plus',
        },
      );
      var requestedBaseUrl = '';
      final controller = AppController(
        accountClientFactory: (baseUrl) {
          requestedBaseUrl = baseUrl;
          return client;
        },
        environmentOverride: const <String, String>{},
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light().copyWith(platform: TargetPlatform.iOS),
          home: MediaQuery(
            data: const MediaQueryData(size: Size(390, 844)),
            child: Scaffold(body: MobileSettingsPage(controller: controller)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('mobile-settings-account-base-url-field')),
          matching: find.byType(TextFormField),
        ),
        'https://accounts.svc.plus/',
      );
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('mobile-settings-account-identifier-field')),
          matching: find.byType(TextFormField),
        ),
        'mobile@svc.plus',
      );
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('mobile-settings-account-password-field')),
          matching: find.byType(TextFormField),
        ),
        'typed-password',
      );
      final loginButton = find.byKey(
        const Key('mobile-settings-account-login-button'),
      );
      await tester.ensureVisible(loginButton);
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(loginButton).onPressed, isNotNull);
      tester.widget<FilledButton>(loginButton).onPressed!();
      for (
        var attempt = 0;
        attempt < 50 &&
            find
                .byKey(const Key('mobile-settings-account-signed-in-card'))
                .evaluate()
                .isEmpty;
        attempt += 1
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(requestedBaseUrl, 'https://accounts.svc.plus');
      expect(client.lastIdentifier, 'mobile@svc.plus');
      expect(client.lastPassword, 'typed-password');
      expect(client.loginCallCount, 1);
      expect(controller.settingsController.accountSignedIn, isTrue);
      await tester.drag(
        find.byKey(const Key('mobile-settings-page')),
        const Offset(0, 500),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.byKey(const Key('mobile-settings-account-signed-in-card')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('mobile-settings-manual-bridge-card')),
        findsNothing,
      );
      expect(find.text('mobile@svc.plus'), findsOneWidget);
    });

    testWidgets('manual bridge save updates mobile runtime configuration', (
      tester,
    ) async {
      final store = _MemorySecureConfigStore();
      final controller = _NoopRefreshAppController(store: store);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light().copyWith(platform: TargetPlatform.iOS),
          home: MediaQuery(
            data: const MediaQueryData(size: Size(390, 844)),
            child: Scaffold(body: MobileSettingsPage(controller: controller)),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));

      final urlField = find.byKey(
        const Key('mobile-settings-manual-bridge-url-field'),
      );
      await tester.ensureVisible(urlField);
      await tester.enterText(
        find.descendant(of: urlField, matching: find.byType(TextFormField)),
        'http://127.0.0.1:1',
      );
      final tokenField = find.byKey(
        const Key('mobile-settings-manual-bridge-token-field'),
      );
      await tester.enterText(
        find.descendant(of: tokenField, matching: find.byType(TextFormField)),
        'mobile-manual-token',
      );
      final saveButton = find.byKey(
        const Key('mobile-settings-manual-bridge-save-button'),
      );
      await tester.ensureVisible(saveButton);
      tester.widget<FilledButton>(saveButton).onPressed!();

      for (
        var attempt = 0;
        attempt < 20 &&
            controller
                    .settings
                    .acpBridgeServerModeConfig
                    .selfHosted
                    .serverUrl !=
                'http://127.0.0.1:1';
        attempt += 1
      ) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      final bridgeConfig = controller.settings.acpBridgeServerModeConfig;
      expect(bridgeConfig.selfHosted.serverUrl, 'http://127.0.0.1:1');
      expect(bridgeConfig.effective.source, 'bridge');
      expect(
        await store.loadSecretValueByRef(bridgeConfig.selfHosted.passwordRef),
        'mobile-manual-token',
      );
      expect(
        controller.resolveGatewayAcpEndpointInternal()?.toString(),
        'http://127.0.0.1:1',
      );
      expect(
        await controller.resolveGatewayAcpAuthorizationHeaderInternal(
          Uri.parse('http://127.0.0.1:1/acp/rpc'),
        ),
        'mobile-manual-token',
      );
      // 保存链路在 test binding 下可能不返回（见 saveManualBridge 的超时
      // 兜底），因此这里按超时窗口推进时钟,不能用 pumpAndSettle——只要
      // 忙碌态的转圈图标还在,pumpAndSettle 永远不会 settle。
      await tester.pump(
        mobileManualBridgeFeedbackTimeoutInternal,
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.byKey(const Key('mobile-settings-manual-bridge-card')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('mobile-settings-account-login-card')),
        findsNothing,
      );
    });

    testWidgets('manual bridge save reports the connection result', (
      tester,
    ) async {
      final store = _MemorySecureConfigStore();
      final controller = _NoopRefreshAppController(store: store);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light().copyWith(platform: TargetPlatform.iOS),
          home: MediaQuery(
            data: const MediaQueryData(size: Size(390, 844)),
            child: Scaffold(body: MobileSettingsPage(controller: controller)),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));

      final urlField = find.byKey(
        const Key('mobile-settings-manual-bridge-url-field'),
      );
      await tester.ensureVisible(urlField);
      await tester.enterText(
        find.descendant(of: urlField, matching: find.byType(TextFormField)),
        'http://127.0.0.1:1',
      );
      final tokenField = find.byKey(
        const Key('mobile-settings-manual-bridge-token-field'),
      );
      await tester.enterText(
        find.descendant(of: tokenField, matching: find.byType(TextFormField)),
        'mobile-manual-token',
      );

      final saveButton = find.byKey(
        const Key('mobile-settings-manual-bridge-save-button'),
      );
      await tester.ensureVisible(saveButton);
      tester.widget<FilledButton>(saveButton).onPressed!();
      await tester.pump();

      // 保存进行中：按钮禁用并给出「正在连接…」的可见回执。
      expect(tester.widget<FilledButton>(saveButton).onPressed, isNull);
      expect(find.text('正在连接…'), findsOneWidget);

      // 不能用 pumpAndSettle：忙碌态的转圈图标会让它永远 settle 不了。
      // 按超时窗口推进时钟，验证兜底路径也一定给出反馈。
      await tester.pump(mobileManualBridgeFeedbackTimeoutInternal);
      await tester.pump(const Duration(milliseconds: 400));

      // 落地后必须给出结果反馈,而不是静默返回。
      expect(
        find.byKey(const Key('mobile-settings-manual-bridge-snackbar')),
        findsOneWidget,
      );
      expect(tester.widget<FilledButton>(saveButton).onPressed, isNotNull);
      expect(find.text('保存手动配置'), findsOneWidget);
    });

    testWidgets('sync button reports in-flight state while syncing', (
      tester,
    ) async {
      final client = _MobileFakeAccountRuntimeClient(
        syncPayload: _bridgeSyncPayload,
      );
      final controller = _MobileSyncAppController(client: client);
      addTearDown(controller.dispose);

      final syncButton = await _pumpSignedInMobileSettings(tester, controller);

      tester.widget<FilledButton>(syncButton).onPressed!();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.widget<FilledButton>(syncButton).onPressed, isNull);
      expect(find.text('同步中…'), findsWidgets);
      expect(
        find.descendant(
          of: syncButton,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('mobile-settings-account-logout-button')),
            )
            .onPressed,
        isNull,
      );

      await _settleSync(tester, syncButton);

      expect(tester.widget<FilledButton>(syncButton).onPressed, isNotNull);
      expect(find.text('同步中…'), findsNothing);
    });

    testWidgets('sync completion refreshes last sync row and shows feedback', (
      tester,
    ) async {
      final client = _MobileFakeAccountRuntimeClient(
        syncPayload: _bridgeSyncPayload,
      );
      final controller = _MobileSyncAppController(client: client);
      addTearDown(controller.dispose);

      final syncButton = await _pumpSignedInMobileSettings(tester, controller);

      tester.widget<FilledButton>(syncButton).onPressed!();
      await _settleSync(tester, syncButton);

      expect(
        find.byKey(const Key('mobile-settings-account-sync-snackbar')),
        findsOneWidget,
      );
      expect(find.textContaining('同步完成：'), findsOneWidget);
      expect(
        find.byKey(const Key('mobile-settings-account-last-sync-row')),
        findsOneWidget,
      );
      expect(find.text('尚未同步'), findsNothing);
      expect(
        find.textContaining(RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$')),
        findsOneWidget,
      );
      expect(
        controller.settingsController.accountSyncState?.lastSyncAtMs ?? 0,
        greaterThan(0),
      );
    });

    testWidgets('sync failure surfaces the error instead of a silent no-op', (
      tester,
    ) async {
      final client = _MobileFakeAccountRuntimeClient(
        syncPayload: _bridgeSyncPayload,
      );
      final controller = _MobileSyncAppController(client: client);
      addTearDown(controller.dispose);

      final syncButton = await _pumpSignedInMobileSettings(tester, controller);

      // A sync response without bridge authorization is a contract failure.
      client.syncPayload = const <String, dynamic>{};
      tester.widget<FilledButton>(syncButton).onPressed!();
      await _settleSync(tester, syncButton);

      expect(
        find.byKey(const Key('mobile-settings-account-sync-snackbar')),
        findsOneWidget,
      );
      expect(find.textContaining('同步失败：'), findsOneWidget);
      expect(tester.widget<FilledButton>(syncButton).onPressed, isNotNull);
    });
  });
}

const Map<String, dynamic> _bridgeSyncPayload = <String, dynamic>{
  'BRIDGE_AUTH_TOKEN': 'bridge-token',
  'BRIDGE_SERVER_URL': 'https://xworkmate-bridge.svc.plus',
};

/// Account sync persists settings through real file I/O, which only advances
/// inside [WidgetTester.runAsync]. Pumping alone leaves the sync mid-flight —
/// which is exactly what the in-flight assertions rely on.
Future<void> _settleSync(WidgetTester tester, Finder syncButton) async {
  for (var attempt = 0; attempt < 20; attempt += 1) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    if (tester.widget<FilledButton>(syncButton).onPressed != null) {
      // One more frame lets the SnackBar finish entering.
      await tester.pump(const Duration(milliseconds: 400));
      return;
    }
  }
  fail('Sync did not return to an idle state');
}

/// Brings the page up in a signed-in state with one completed sync behind it,
/// then returns the sync button finder once it is tappable.
Future<Finder> _pumpSignedInMobileSettings(
  WidgetTester tester,
  AppController controller,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light().copyWith(platform: TargetPlatform.iOS),
      home: MediaQuery(
        data: const MediaQueryData(size: Size(390, 844)),
        child: Scaffold(body: MobileSettingsPage(controller: controller)),
      ),
    ),
  );
  await tester.pumpAndSettle();

  await tester.runAsync(
    () => controller.settingsController.syncAccountSettings(
      baseUrl: 'https://accounts.svc.plus',
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));

  final signedInCard = find.byKey(
    const Key('mobile-settings-account-signed-in-card'),
  );
  expect(signedInCard, findsOneWidget);

  final syncButton = find.byKey(
    const Key('mobile-settings-account-sync-button'),
  );
  await tester.ensureVisible(syncButton);
  await tester.pump(const Duration(milliseconds: 100));
  expect(tester.widget<FilledButton>(syncButton).onPressed, isNotNull);
  return syncButton;
}

class _MobileFakeAccountRuntimeClient extends AccountRuntimeClient {
  _MobileFakeAccountRuntimeClient({
    this.loginPayload = const <String, dynamic>{},
    this.syncPayload = const <String, dynamic>{},
    this.loginError,
  }) : super(baseUrl: 'https://accounts.svc.plus');

  final Map<String, dynamic> loginPayload;
  Map<String, dynamic> syncPayload;
  final AccountRuntimeException? loginError;
  int loginCallCount = 0;
  String lastIdentifier = '';
  String lastPassword = '';

  @override
  Future<Map<String, dynamic>> login({
    required String identifier,
    required String password,
  }) async {
    loginCallCount += 1;
    lastIdentifier = identifier;
    lastPassword = password;
    final error = loginError;
    if (error != null) {
      throw error;
    }
    return loginPayload;
  }

  @override
  Future<Map<String, dynamic>> loadXWorkmateProfileSync({
    required String token,
  }) async {
    return syncPayload;
  }

  @override
  Future<Map<String, dynamic>> loadProfile({required String token}) async {
    return const <String, dynamic>{
      'user': <String, dynamic>{'id': 'user-1', 'email': 'mobile@svc.plus'},
    };
  }
}

/// Round-trips the account session in memory so a signed-in sync can resolve
/// its session token without touching platform secure storage.
class _MemoryAccountSessionStore extends _MemorySecureConfigStore {
  String? _sessionToken = 'seed-session-token';
  String? _sessionIdentifier;
  AccountSessionSummary? _sessionSummary;
  AccountSyncState? _syncState;
  final Map<String, String> _managedSecrets = <String, String>{};

  @override
  Future<String?> loadAccountSessionToken() async => _sessionToken;

  @override
  Future<void> saveAccountSessionToken(String value) async {
    _sessionToken = value;
  }

  @override
  Future<String?> loadAccountSessionIdentifier() async => _sessionIdentifier;

  @override
  Future<void> saveAccountSessionIdentifier(String value) async {
    _sessionIdentifier = value;
  }

  @override
  Future<AccountSessionSummary?> loadAccountSessionSummary() async =>
      _sessionSummary;

  @override
  Future<void> saveAccountSessionSummary(AccountSessionSummary value) async {
    _sessionSummary = value;
  }

  @override
  Future<AccountSyncState?> loadAccountSyncState() async => _syncState;

  @override
  Future<void> saveAccountSyncState(AccountSyncState value) async {
    _syncState = value;
  }

  @override
  Future<void> saveAccountManagedSecret({
    required String target,
    required String value,
  }) async {
    _managedSecrets[target] = value;
  }

  @override
  Future<void> clearAccountManagedSecret({required String target}) async {
    _managedSecrets.remove(target);
  }

  @override
  Future<String?> loadAccountManagedSecret({required String target}) async =>
      _managedSecrets[target];

  @override
  Future<Map<String, String>> loadAccountManagedSecrets() async =>
      Map<String, String>.of(_managedSecrets);

  @override
  Future<void> saveAccountSessionExpiresAtMs(int value) async {}

  @override
  Future<void> saveAccountSessionUserId(String value) async {}
}

class _MobileSyncAppController extends AppController {
  _MobileSyncAppController({required AccountRuntimeClient client})
    : super(
        accountClientFactory: (_) => client,
        environmentOverride: const <String, String>{},
        store: _MemoryAccountSessionStore(),
      );

  Future<void> refreshAcpCapabilitiesInternal({
    bool forceRefresh = false,
    bool persistMountTargets = false,
  }) async {}

  Future<void> refreshSingleAgentCapabilitiesInternal({
    bool forceRefresh = false,
  }) async {}
}

class _NoopRefreshAppController extends AppController {
  _NoopRefreshAppController({required SecureConfigStore store})
    : super(environmentOverride: const <String, String>{}, store: store);

  Future<void> refreshAcpCapabilitiesInternal({
    bool forceRefresh = false,
    bool persistMountTargets = false,
  }) async {}

  Future<void> refreshSingleAgentCapabilitiesInternal({
    bool forceRefresh = false,
  }) async {}
}

class _MemorySecureConfigStore extends SecureConfigStore {
  _MemorySecureConfigStore() : super(enableSecureStorage: false);

  SettingsSnapshot _settings = SettingsSnapshot.defaults();
  final Map<String, String> _secrets = <String, String>{};

  @override
  Future<void> initialize() async {}

  @override
  Future<SettingsSnapshot> loadSettingsSnapshot() async => _settings;

  @override
  Future<void> saveSettingsSnapshot(SettingsSnapshot snapshot) async {
    _settings = snapshot;
  }

  @override
  Future<Map<String, String>> loadSecureRefs() async => _secrets;

  @override
  Future<List<SecretAuditEntry>> loadAuditTrail() async =>
      const <SecretAuditEntry>[];

  @override
  Future<void> appendAudit(SecretAuditEntry entry) async {}

  @override
  Future<String?> loadSecretValueByRef(String refName) async =>
      _secrets[refName];

  @override
  Future<void> saveSecretValueByRef(String refName, String value) async {
    _secrets[refName] = value;
  }

  @override
  Future<String?> loadAccountSessionToken() async => null;

  @override
  Future<AccountSessionSummary?> loadAccountSessionSummary() async => null;

  @override
  Future<AccountSyncState?> loadAccountSyncState() async => null;
}
