import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xworkmate/app/app.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';

void initializeIntegrationHarness() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
}

Future<void> resetIntegrationPreferences() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final isolatedRoot = await Directory.systemTemp.createTemp(
    'xworkmate-integration-store-',
  );
  debugOverridePersistentSupportRoot(isolatedRoot.path);
  addTearDown(() async {
    debugOverridePersistentSupportRoot(null);
    if (await isolatedRoot.exists()) {
      await isolatedRoot.delete(recursive: true);
    }
  });
}

Future<void> pumpDesktopApp(
  WidgetTester tester, {
  Size size = const Size(1600, 1000),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(const XWorkmateApp());
  await settleIntegrationUi(tester);
}

Future<void> settleIntegrationUi(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 150));
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump(const Duration(milliseconds: 400));
}
