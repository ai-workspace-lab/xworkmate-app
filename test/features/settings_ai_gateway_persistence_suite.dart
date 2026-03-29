@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/features/settings/settings_page.dart';
import 'package:xworkmate/models/app_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';

import '../test_support.dart';

void main() {
  testWidgets(
    'SettingsPage LLM API draft/save/apply flow persists edited fields through local actions',
    (WidgetTester tester) async {
      late _AiGatewaySettingsTestController controller;
      late Directory testRoot;
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        testRoot = await Directory.systemTemp.createTemp(
          'xworkmate-widget-tests-',
        );
        controller = _AiGatewaySettingsTestController(
          store: SecureConfigStore(
            enableSecureStorage: false,
            databasePathResolver: () async =>
                '${testRoot.path}/settings.sqlite3',
            fallbackDirectoryPathResolver: () async => testRoot.path,
          ),
        );
        await _waitFor(() => !controller.initializing);
      });
      addTearDown(controller.dispose);
      addTearDown(() async {
        if (await testRoot.exists()) {
          await testRoot.delete(recursive: true);
        }
      });

      final staleGateway = controller.settings.aiGateway.copyWith(
        name: 'default',
        baseUrl: '',
        apiKeyRef: 'ai_gateway_api_key',
        availableModels: const <String>['stale-model'],
        selectedModels: const <String>['stale-model'],
        syncState: 'invalid',
        syncMessage: 'Missing LLM API Endpoint',
      );
      await tester.runAsync(() async {
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

      controller.setSettingsTab(SettingsTab.gateway);
      await pumpPage(tester, child: SettingsPage(controller: controller));

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

      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('ai-gateway-url-field')),
            )
            .controller!
            .text,
        'https://api.svc.plus/v1',
      );
      expect(
        find.byKey(const ValueKey('ai-gateway-save-button')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('ai-gateway-apply-button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-global-save-button')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('settings-global-apply-button')),
        findsOneWidget,
      );

      expect(
        controller.settingsDraft.aiGateway.baseUrl,
        'https://api.svc.plus/v1',
      );
      expect(controller.settings.aiGateway.baseUrl, isEmpty);

      final applyButton = tester.widget<FilledButton>(
        find.byKey(const ValueKey('ai-gateway-apply-button')),
      );
      await tester.runAsync(() async {
        applyButton.onPressed!.call();
        await _waitFor(
          () =>
              controller.settings.aiGateway.baseUrl ==
              'https://api.svc.plus/v1',
        );
      });
      await tester.pump(const Duration(milliseconds: 300));

      expect(controller.settings.aiGateway.name, 'default');
      expect(controller.settings.aiGateway.baseUrl, 'https://api.svc.plus/v1');
      expect(controller.settings.aiGateway.apiKeyRef, 'ai_gateway_api_key');
      expect(controller.settings.aiGateway.availableModels, isEmpty);
      expect(controller.settings.aiGateway.selectedModels, isEmpty);
      expect(controller.settings.aiGateway.syncState, 'idle');
      expect(controller.settings.aiGateway.syncMessage, 'Ready to sync models');
      expect(controller.hasPendingSettingsApply, isFalse);
      expect(find.text('Missing LLM API Endpoint'), findsNothing);
      expect(find.text('Ready to sync models'), findsOneWidget);
    },
  );
}

class _AiGatewaySettingsTestController extends AppController {
  _AiGatewaySettingsTestController({super.store});

  @override
  Future<void> refreshMultiAgentMounts({bool sync = false}) async {}
}

Future<void> _waitFor(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('condition not met before timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
