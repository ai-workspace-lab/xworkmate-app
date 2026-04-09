@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/ui_feature_manifest.dart';
import 'package:xworkmate/features/settings/settings_page_core.dart';
import 'package:xworkmate/models/app_models.dart';

import '../test_support.dart';

void main() {
  testWidgets(
    'SettingsPage shows base connection card when self-hosted base is enabled',
    (WidgetTester tester) async {
      final manifest = UiFeatureManifest.fallback().copyWithFeature(
        platform: UiFeaturePlatform.desktop,
        module: 'settings',
        feature: 'gateway_self_hosted_base',
        enabled: true,
        releaseTier: UiFeatureReleaseTier.experimental,
      );
      final controller = await createTestController(
        tester,
        uiFeatureManifest: manifest,
      );
      controller.openSettings(tab: SettingsTab.gateway);

      await pumpPage(
        tester,
        child: SettingsPage(
          controller: controller,
          initialTab: SettingsTab.gateway,
          showSectionTabs: true,
        ),
        platform: TargetPlatform.macOS,
      );

      await tester.tap(find.byKey(const ValueKey('section-tab-基础连接配置')));
      await tester.pumpAndSettle();

      expect(find.text('基础连接配置'), findsWidgets);
      expect(
        find.byKey(const ValueKey('acp-bridge-mode-cloud')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('acp-bridge-mode-self-hosted')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('acp-bridge-mode-advanced')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('acp-bridge-self-hosted-url')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('acp-bridge-self-hosted-connect')),
        findsOneWidget,
      );
    },
  );
}
