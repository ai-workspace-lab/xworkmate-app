@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xworkmate/app/app_controller_web.dart' as web_app;
import 'package:xworkmate/models/app_models.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/web/web_settings_page_core.dart';

import '../test_support.dart';

void main() {
  testWidgets('Web external ACP editor supports continuous input', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final controller = web_app.AppController();
    addTearDown(controller.dispose);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    final customProfile = buildCustomExternalAcpEndpointProfile(
      controller.settingsDraft.externalAcpEndpoints,
      label: 'Initial Name',
      endpoint: 'wss://initial.example.com/acp',
    );
    await controller.saveSettingsDraft(
      controller.settingsDraft.copyWith(
        externalAcpEndpoints: <ExternalAcpEndpointProfile>[
          ...controller.settingsDraft.externalAcpEndpoints,
          customProfile,
        ],
      ),
    );
    controller.setSettingsTab(SettingsTab.gateway);

    await pumpPage(
      tester,
      child: SizedBox(
        width: 1280,
        height: 960,
        child: WebSettingsPage(controller: controller, showSectionTabs: false),
      ),
      platform: TargetPlatform.macOS,
    );

    final labelField = find.byKey(
      ValueKey('web-external-acp-label-${customProfile.providerKey}'),
    );
    final testButton = find.byKey(
      ValueKey('web-external-acp-test-${customProfile.providerKey}'),
    );
    final saveButton = find.byKey(
      ValueKey('web-external-acp-save-${customProfile.providerKey}'),
    );

    expect(labelField, findsOneWidget);
    expect(testButton, findsOneWidget);
    expect(saveButton, findsOneWidget);

    await tester.enterText(labelField, 'A');
    await tester.pump();
    await tester.enterText(labelField, 'AB');
    await tester.pump();
    await tester.enterText(labelField, 'ABC');
    await tester.pump();

    expect(find.text('ABC'), findsOneWidget);
  });
}
