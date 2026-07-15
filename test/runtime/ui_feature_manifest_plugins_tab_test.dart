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

    test(
      'desktop debug exposes the plugins settings tab and composer entry',
      () {
        final desktop = loadManifest().forPlatform(
          UiFeaturePlatform.desktop,
          buildMode: UiFeatureBuildMode.debug,
        );
        expect(desktop.availableSettingsTabs, contains(SettingsTab.plugins));
        expect(desktop.supportsBuiltinPlugins, isTrue);
      },
    );

    test('desktop release exposes batch 1 by default (stable tier)', () {
      final desktop = loadManifest().forPlatform(
        UiFeaturePlatform.desktop,
        buildMode: UiFeatureBuildMode.release,
      );
      expect(desktop.availableSettingsTabs, contains(SettingsTab.plugins));
      expect(desktop.supportsBuiltinPlugins, isTrue);
    });

    test('mobile exposes batch 1 and web stays untouched', () {
      final manifest = loadManifest();
      final mobile = manifest.forPlatform(
        UiFeaturePlatform.mobile,
        buildMode: UiFeatureBuildMode.debug,
      );
      expect(mobile.availableSettingsTabs, contains(SettingsTab.plugins));
      expect(mobile.supportsBuiltinPlugins, isTrue);

      for (final platform in <UiFeaturePlatform>[UiFeaturePlatform.web]) {
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
