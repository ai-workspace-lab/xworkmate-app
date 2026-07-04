import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/ui_feature_manifest.dart';
import 'package:xworkmate/models/app_models.dart';

void main() {
  group('Built-in plugins feature flags (batch 1)', () {
    UiFeatureManifest loadManifest() {
      final raw = File('config/feature_flags.yaml').readAsStringSync();
      return UiFeatureManifest.fromYamlString(raw);
    }

    test('desktop debug exposes the plugins settings tab and composer entry',
        () {
      final desktop = loadManifest().forPlatform(
        UiFeaturePlatform.desktop,
        buildMode: UiFeatureBuildMode.debug,
      );
      expect(desktop.availableSettingsTabs, contains(SettingsTab.plugins));
      expect(desktop.supportsBuiltinPlugins, isTrue);
    });

    test('desktop release keeps batch 1 hidden (beta tier)', () {
      final desktop = loadManifest().forPlatform(
        UiFeaturePlatform.desktop,
        buildMode: UiFeatureBuildMode.release,
      );
      expect(
        desktop.availableSettingsTabs,
        isNot(contains(SettingsTab.plugins)),
      );
      expect(desktop.supportsBuiltinPlugins, isFalse);
      expect(
        desktop.sanitizeSettingsTab(SettingsTab.plugins),
        SettingsTab.gateway,
      );
    });

    test('mobile and web stay untouched in batch 1', () {
      final manifest = loadManifest();
      for (final platform in <UiFeaturePlatform>[
        UiFeaturePlatform.mobile,
        UiFeaturePlatform.web,
      ]) {
        final access = manifest.forPlatform(
          platform,
          buildMode: UiFeatureBuildMode.debug,
        );
        expect(
          access.availableSettingsTabs,
          isNot(contains(SettingsTab.plugins)),
          reason: platform.name,
        );
        expect(access.supportsBuiltinPlugins, isFalse, reason: platform.name);
      }
    });
  });
}
