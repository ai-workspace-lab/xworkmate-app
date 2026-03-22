@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/features/settings/settings_page.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';
import 'package:xworkmate/theme/app_theme.dart';

void main() {
  testWidgets(
    'SettingsPage AI Gateway draft/save/apply flow persists edited fields through the global actions',
    (WidgetTester tester) async {
      late AppController controller;
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        controller = AppController(
          store: SecureConfigStore(
            enableSecureStorage: false,
            fallbackDirectoryPathResolver: () async =>
                '${Directory.systemTemp.path}/xworkmate-widget-tests',
          ),
        );
        await _waitFor(() => !controller.initializing);
        final staleGateway = controller.settings.aiGateway.copyWith(
          name: 'default',
          baseUrl: '',
          apiKeyRef: 'ai_gateway_api_key',
          availableModels: const <String>['stale-model'],
          selectedModels: const <String>['stale-model'],
          syncState: 'invalid',
          syncMessage: 'Missing AI Gateway URL',
        );
        await controller.saveSettings(
          controller.settings.copyWith(
            aiGateway: staleGateway,
            multiAgent: controller.settings.multiAgent.copyWith(
              autoSync: false,
            ),
          ),
          refreshAfterSave: false,
        );
      });
      addTearDown(controller.dispose);

      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1600, 1000);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: const [Locale('zh'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          home: Scaffold(body: SettingsPage(controller: controller)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.text('集成'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('ai-gateway-name-field')),
        'default',
      );
      await tester.enterText(
        find.byKey(const ValueKey('ai-gateway-url-field')),
        'https://api.svc.plus/v1',
      );
      await tester.enterText(
        find.byKey(const ValueKey('ai-gateway-api-key-ref-field')),
        'ai_gateway_api_key',
      );
      await tester.enterText(
        find.byKey(const ValueKey('ai-gateway-api-key-field')),
        'live-secret',
      );

      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('ai-gateway-url-field')),
            )
            .controller!
            .text,
        'https://api.svc.plus/v1',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('ai-gateway-save-draft-button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('ai-gateway-save-draft-button')),
      );
      await tester.pumpAndSettle();

      expect(controller.settings.aiGateway.baseUrl, isEmpty);
      expect(
        controller.settingsDraft.aiGateway.baseUrl,
        'https://api.svc.plus/v1',
      );

      expect(
        find.byKey(const ValueKey('settings-global-save-button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-global-apply-button')),
        findsOneWidget,
      );
      await tester.runAsync(() async {
        await controller.persistSettingsDraft();
      });
      await tester.runAsync(() async {
        await _waitFor(() => controller.hasPendingSettingsApply);
      });
      await tester.pump(const Duration(milliseconds: 250));

      expect(controller.hasPendingSettingsApply, isTrue);

      await tester.runAsync(() async {
        await controller.applySettingsDraft();
      });
      await tester.pumpAndSettle();

      expect(controller.settings.aiGateway.name, 'default');
      expect(controller.settings.aiGateway.baseUrl, 'https://api.svc.plus/v1');
      expect(controller.settings.aiGateway.apiKeyRef, 'ai_gateway_api_key');
      expect(controller.settings.aiGateway.availableModels, isEmpty);
      expect(controller.settings.aiGateway.selectedModels, isEmpty);
      expect(controller.settings.aiGateway.syncState, 'idle');
      expect(controller.settings.aiGateway.syncMessage, 'Ready to sync models');
      expect(controller.hasPendingSettingsApply, isFalse);
      expect(find.text('Missing AI Gateway URL'), findsNothing);
      expect(find.text('Ready to sync models'), findsOneWidget);
    },
  );
}

Future<void> _waitFor(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition not met before timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
