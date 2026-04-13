import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/ui_feature_manifest.dart';
import 'package:xworkmate/models/app_models.dart';

void main() {
  group('Desktop feature manifest cleanup', () {
    test('repo config only exposes assistant and settings on desktop', () {
      final raw = File('config/feature_flags.yaml').readAsStringSync();
      final manifest = UiFeatureManifest.fromYamlString(raw);
      final desktop = manifest.forPlatform(
        UiFeaturePlatform.desktop,
        buildMode: UiFeatureBuildMode.debug,
      );

      expect(
        desktop.allowedDestinations,
        <WorkspaceDestination>{
          WorkspaceDestination.assistant,
          WorkspaceDestination.settings,
        },
      );
    });

    test('fallback manifest only exposes assistant and settings on desktop', () {
      final desktop = UiFeatureManifest.fallback().forPlatform(
        UiFeaturePlatform.desktop,
        buildMode: UiFeatureBuildMode.debug,
      );

      expect(
        desktop.allowedDestinations,
        <WorkspaceDestination>{
          WorkspaceDestination.assistant,
          WorkspaceDestination.settings,
        },
      );
    });
  });
}
