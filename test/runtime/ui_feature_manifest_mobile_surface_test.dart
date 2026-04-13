import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/ui_feature_manifest.dart';
import 'package:xworkmate/models/app_models.dart';

void main() {
  group('Mobile feature manifest cleanup', () {
    test('repo config only exposes assistant and settings on mobile', () {
      final raw = File('config/feature_flags.yaml').readAsStringSync();
      final manifest = UiFeatureManifest.fromYamlString(raw);
      final mobile = manifest.forPlatform(
        UiFeaturePlatform.mobile,
        buildMode: UiFeatureBuildMode.debug,
      );

      expect(
        mobile.allowedDestinations,
        <WorkspaceDestination>{
          WorkspaceDestination.assistant,
          WorkspaceDestination.settings,
        },
      );
    });
  });
}
