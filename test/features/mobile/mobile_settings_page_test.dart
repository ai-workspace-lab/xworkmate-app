import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/app/app_shell_desktop.dart';
import 'package:xworkmate/features/mobile/mobile_settings_page.dart';
import 'package:xworkmate/runtime/account_runtime_client.dart';
import 'package:xworkmate/runtime/runtime_controllers.dart';
import 'package:xworkmate/theme/app_theme.dart';

void main() {
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
      expect(find.text('mobile@svc.plus'), findsOneWidget);
    });
  });
}

class _MobileFakeAccountRuntimeClient extends AccountRuntimeClient {
  _MobileFakeAccountRuntimeClient({
    this.loginPayload = const <String, dynamic>{},
    this.syncPayload = const <String, dynamic>{},
    this.loginError,
  }) : super(baseUrl: 'https://accounts.svc.plus');

  final Map<String, dynamic> loginPayload;
  final Map<String, dynamic> syncPayload;
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
}
