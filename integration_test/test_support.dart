import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xworkmate/app/app.dart';
import 'package:xworkmate/runtime/runtime_controllers.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

void initializeIntegrationHarness() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
}

Future<void> resetIntegrationPreferences() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final isolatedRoot = await Directory.systemTemp.createTemp(
    'xworkmate-integration-store-',
  );
  debugOverridePersistentSupportRoot(isolatedRoot.path);
  final store = SecureConfigStore(
    enableSecureStorage: false,
    databasePathResolver: () async =>
        '${isolatedRoot.path}/${SettingsStore.databaseFileName}',
    fallbackDirectoryPathResolver: () async => isolatedRoot.path,
  );
  final defaults = SettingsSnapshot.defaults();
  await SettingsController(store).saveSnapshot(
    defaults.copyWith(
      gatewayProfiles: replaceGatewayProfileAt(
        replaceGatewayProfileAt(
          defaults.gatewayProfiles,
          kGatewayLocalProfileIndex,
          defaults.primaryLocalGatewayProfile.copyWith(
            host: '127.0.0.1',
            port: 4317,
            tls: false,
          ),
        ),
        kGatewayRemoteProfileIndex,
        defaults.primaryRemoteGatewayProfile.copyWith(
          host: 'gateway.example.com',
          port: 9443,
          tls: true,
        ),
      ),
      externalAcpEndpoints: normalizeExternalAcpEndpoints(
        profiles: <ExternalAcpEndpointProfile>[
          ...defaults.externalAcpEndpoints,
          ExternalAcpEndpointProfile.defaultsForProvider(
            SingleAgentProvider.opencode,
          ).copyWith(
            endpoint: 'https://acp-server.svc.plus/opencode',
            enabled: true,
          ),
        ],
      ),
    )
        .markGatewayTargetSaved(AssistantExecutionTarget.local)
        .markGatewayTargetSaved(AssistantExecutionTarget.remote),
  );
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

Future<void> waitForIntegrationFinder(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 12),
  Duration step = const Duration(milliseconds: 200),
}) async {
  final maxIterations = timeout.inMilliseconds ~/ step.inMilliseconds;
  for (var i = 0; i < maxIterations; i += 1) {
    await tester.pump(step);
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
  throw TestFailure('Timed out waiting for finder: $finder');
}

Future<void> switchNewConversationExecutionTargetForIntegration(
  WidgetTester tester,
  Finder menuItemFinder,
) async {
  final desktopNewTaskButton = find.byKey(
    const Key('workspace-sidebar-new-task-button'),
  );
  if (desktopNewTaskButton.evaluate().isNotEmpty) {
    await tester.tap(desktopNewTaskButton);
  } else {
    await tester.tap(find.byKey(const Key('assistant-new-task-button')));
  }
  await settleIntegrationUi(tester);
  await tester.tap(find.byKey(const Key('assistant-execution-target-button')));
  await settleIntegrationUi(tester);
  await tester.tap(menuItemFinder);
  await settleIntegrationUi(tester);
}
