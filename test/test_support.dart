import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/app/ui_feature_manifest.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';
import 'package:xworkmate/theme/app_theme.dart';
import 'package:xworkmate/runtime/desktop_platform_service.dart';

SecureConfigStore createIsolatedTestStore({bool enableSecureStorage = true}) {
  final testRoot = Directory.systemTemp.createTempSync(
    'xworkmate-store-test-',
  );
  addTearDown(() async {
    if (await testRoot.exists()) {
      await testRoot.delete(recursive: true);
    }
  });
  return SecureConfigStore(
    enableSecureStorage: enableSecureStorage,
    databasePathResolver: () async =>
        '${testRoot.path}/${SettingsStore.databaseFileName}',
    fallbackDirectoryPathResolver: () async => testRoot.path,
  );
}

Future<AppController> createTestController(
  WidgetTester tester, {
  DesktopPlatformService? desktopPlatformService,
  UiFeatureManifest? uiFeatureManifest,
  List<String>? gatewayOnlySkillScanRoots,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final testRoot =
      '${Directory.systemTemp.path}/xworkmate-widget-tests-${DateTime.now().microsecondsSinceEpoch}';
  final controller = AppController(
    store: SecureConfigStore(
      enableSecureStorage: false,
      databasePathResolver: () async => '$testRoot/settings.sqlite3',
      fallbackDirectoryPathResolver: () async => testRoot,
    ),
    desktopPlatformService: desktopPlatformService,
    uiFeatureManifest: uiFeatureManifest,
    gatewayOnlySkillScanRoots: gatewayOnlySkillScanRoots,
  );
  addTearDown(controller.dispose);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pumpAndSettle();
  return controller;
}

Future<void> pumpPage(
  WidgetTester tester, {
  required Widget child,
  Size size = const Size(1600, 1000),
  TargetPlatform? platform,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh'),
      supportedLocales: const [Locale('zh'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: platform == null
          ? AppTheme.light()
          : AppTheme.light(platform: platform),
      darkTheme: platform == null
          ? AppTheme.dark()
          : AppTheme.dark(platform: platform),
      home: Scaffold(body: child),
    ),
  );
  await tester.pumpAndSettle();
}
