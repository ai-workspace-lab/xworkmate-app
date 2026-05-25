import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/app/app_shell_desktop.dart';
import 'package:xworkmate/features/mobile/mobile_settings_page.dart';
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
      await tester.pumpAndSettle();

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
  });
}
