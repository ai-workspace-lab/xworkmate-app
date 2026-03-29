@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/features/settings/settings_page.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';

import '../test_support.dart';

void main() {
  testWidgets(
    'SettingsPage Vault card updates the draft URL and token input state',
    (WidgetTester tester) async {
      late _VaultSettingsTestController controller;
      late Directory testRoot;
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        testRoot = await Directory.systemTemp.createTemp(
          'xworkmate-vault-widget-tests-',
        );
        controller = _VaultSettingsTestController(
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

      await pumpPage(
        tester,
        child: SettingsPage(controller: controller),
        platform: TargetPlatform.macOS,
      );

      await tester.tap(find.text('集成'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('vault-server-url-field')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('vault-namespace-field')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('vault-root-access-token-field')),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const ValueKey('vault-server-url-field')),
        'https://vault.example.com',
      );
      await tester.enterText(
        find.byKey(const ValueKey('vault-namespace-field')),
        'platform/team-a',
      );
      await tester.enterText(
        find.byKey(const ValueKey('vault-root-access-token-field')),
        'vault-root-secret',
      );

      expect(
        controller.settingsDraft.vault.address,
        'https://vault.example.com',
      );
      expect(
        controller.settings.vault.address,
        isNot('https://vault.example.com'),
      );
      expect(controller.settingsDraft.vault.namespace, 'platform/team-a');
      expect(controller.hasSettingsDraftChanges, isTrue);
    },
  );
}

class _VaultSettingsTestController extends AppController {
  _VaultSettingsTestController({super.store});

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
